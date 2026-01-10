//
//  PEManager.swift
//  MIDI2Kit
//
//  High-level Property Exchange API
//
//  ## Responsibility Separation
//
//  - **PEManager**: Timeout scheduling, continuation management, response delivery, public API
//  - **PETransactionManager**: Request ID allocation, chunk assembly, transaction tracking
//
//  This separation ensures single source of truth for each concern:
//  - Timeout-to-continuation mapping lives only in PEManager
//  - Request ID lifecycle lives only in PETransactionManager
//

import Foundation
import MIDI2Core
import MIDI2CI
import MIDI2Transport

// MARK: - PE Response

/// Property Exchange response
public struct PEResponse: Sendable {
    /// HTTP-style status code
    public let status: Int
    
    /// Response header (parsed JSON)
    public let header: PEHeader?
    
    /// Response body (raw data, may be Mcoded7 encoded)
    public let body: Data
    
    /// Decoded body (Mcoded7 decoded if needed)
    public var decodedBody: Data {
        if header?.isMcoded7 == true {
            return Mcoded7.decode(body) ?? body
        }
        return body
    }
    
    /// Body as UTF-8 string
    public var bodyString: String? {
        String(data: decodedBody, encoding: .utf8)
    }
    
    /// Is success response
    public var isSuccess: Bool {
        status >= 200 && status < 300
    }
    
    /// Is error response
    public var isError: Bool {
        status >= 400
    }
    
    public init(status: Int, header: PEHeader?, body: Data) {
        self.status = status
        self.header = header
        self.body = body
    }
}

// MARK: - PE Error

/// Property Exchange errors
public enum PEError: Error, Sendable {
    /// Transaction timed out
    case timeout(resource: String)
    
    /// Transaction was cancelled
    case cancelled
    
    /// Request ID exhausted (all 128 in use)
    case requestIDExhausted
    
    /// Device returned error status
    case deviceError(status: Int, message: String?)
    
    /// Device not found
    case deviceNotFound(MUID)
    
    /// Invalid response format
    case invalidResponse(String)
    
    /// Transport error
    case transportError(Error)
    
    /// Not connected to any destination
    case noDestination
    
    /// Request validation failed
    case validationFailed(PERequestError)
}

// MARK: - PE Notification

/// Property Exchange subscription notification
public struct PENotification: Sendable {
    /// Resource that changed
    public let resource: String
    
    /// Subscription ID
    public let subscribeId: String
    
    /// Change header
    public let header: PEHeader?
    
    /// Change data
    public let data: Data
    
    /// Source device MUID
    public let sourceMUID: MUID
}

// MARK: - PE Subscription

/// Active subscription information
public struct PESubscription: Sendable {
    /// Subscription ID assigned by device
    public let subscribeId: String
    
    /// Resource being subscribed to
    public let resource: String
    
    /// Device handle
    public let device: PEDeviceHandle
}

/// Subscribe response
public struct PESubscribeResponse: Sendable {
    /// HTTP-style status code
    public let status: Int
    
    /// Subscription ID (if successful)
    public let subscribeId: String?
    
    /// Is success response
    public var isSuccess: Bool {
        status >= 200 && status < 300
    }
}

// MARK: - PEManager

/// High-level Property Exchange manager
///
/// ## Architecture
///
/// PEManager is the single source of truth for:
/// - **Timeout scheduling**: Each request has a dedicated timeout Task
/// - **Continuation management**: Maps Request ID to waiting continuation
/// - **Response delivery**: Resumes continuations with success/error/timeout
///
/// It delegates to PETransactionManager for:
/// - Request ID allocation/release
/// - Multi-chunk response assembly
/// - Transaction state tracking
///
/// ## Cancellation Support
///
/// All request methods support cooperative cancellation via `withTaskCancellationHandler`.
/// When a Task is cancelled:
/// - The pending transaction is cancelled
/// - The Request ID is released
/// - The continuation is resumed with `PEError.cancelled`
///
/// ## Thread Safety
///
/// All state is protected by Swift's actor isolation.
/// Timeout tasks capture weak self to prevent retain cycles.
public actor PEManager {
    
    // MARK: - Configuration
    
    /// Default transaction timeout
    public static let defaultTimeout: Duration = .seconds(5)
    
    /// Log category
    private static let logCategory = "PEManager"
    
    // MARK: - Dependencies
    
    private let transport: any MIDITransport
    private let sourceMUID: MUID
    private let transactionManager: PETransactionManager
    private let logger: any MIDI2Logger
    
    /// Destination resolver: given a MUID, returns the corresponding destination
    ///
    /// This enables MUID-only API without tight coupling to CIManager.
    /// When set, allows using `get(_:from:MUID)` instead of requiring `PEDeviceHandle`.
    ///
    /// ## Setup with CIManager
    /// ```swift
    /// peManager.destinationResolver = { [weak ciManager] muid in
    ///     await ciManager?.destination(for: muid)
    /// }
    /// ```
    public var destinationResolver: (@Sendable (MUID) async -> MIDIDestinationID?)?
    
    // MARK: - Receive State
    
    /// Task that processes incoming MIDI data
    private var receiveTask: Task<Void, Never>?
    
    // MARK: - GET/SET Request State
    
    /// Continuations waiting for GET/SET responses (keyed by Request ID)
    ///
    /// Single source of truth for request completion.
    /// When a response arrives or timeout fires, the continuation is resumed and removed.
    private var pendingContinuations: [UInt8: CheckedContinuation<PEResponse, Error>] = [:]
    
    /// Timeout tasks for pending requests (keyed by Request ID)
    ///
    /// Each request has its own timeout Task. This is more precise than
    /// periodic monitoring and ensures exact timeout semantics.
    private var timeoutTasks: [UInt8: Task<Void, Never>] = [:]
    
    // MARK: - Subscribe State
    
    /// Continuations waiting for Subscribe/Unsubscribe responses
    private var pendingSubscribeContinuations: [UInt8: CheckedContinuation<PESubscribeResponse, Error>] = [:]
    
    /// Active subscriptions by subscribeId
    private var activeSubscriptions: [String: PESubscription] = [:]
    
    /// Notification stream continuation (single listener)
    private var notificationContinuation: AsyncStream<PENotification>.Continuation?
    
    // MARK: - Initialization
    
    /// Initialize PEManager
    /// - Parameters:
    ///   - transport: MIDI transport for sending/receiving
    ///   - sourceMUID: Our MUID (for message filtering)
    ///   - logger: Optional logger (default: silent)
    public init(
        transport: any MIDITransport,
        sourceMUID: MUID,
        logger: any MIDI2Logger = NullMIDI2Logger()
    ) {
        self.transport = transport
        self.sourceMUID = sourceMUID
        self.logger = logger
        self.transactionManager = PETransactionManager(logger: logger)
    }
    
    deinit {
        receiveTask?.cancel()
    }
    
    // MARK: - Lifecycle
    
    /// Start receiving MIDI data
    public func startReceiving() async {
        guard receiveTask == nil else { return }
        
        receiveTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await received in transport.received {
                await self.handleReceived(received.data)
            }
        }
        
        logger.info("Started receiving", category: Self.logCategory)
    }
    
    /// Stop receiving and cancel all pending requests
    public func stopReceiving() async {
        // Stop receive loop
        receiveTask?.cancel()
        receiveTask = nil
        
        // Cancel all timeout tasks
        for (_, task) in timeoutTasks {
            task.cancel()
        }
        timeoutTasks.removeAll()
        
        // Resume all pending GET/SET continuations with cancellation
        for continuation in pendingContinuations.values {
            continuation.resume(throwing: PEError.cancelled)
        }
        pendingContinuations.removeAll()
        
        // Resume all pending Subscribe continuations with cancellation
        for continuation in pendingSubscribeContinuations.values {
            continuation.resume(throwing: PEError.cancelled)
        }
        pendingSubscribeContinuations.removeAll()
        
        // Clear subscriptions
        activeSubscriptions.removeAll()
        
        // Finish notification stream
        notificationContinuation?.finish()
        notificationContinuation = nil
        
        // Release all Request IDs
        await transactionManager.cancelAll()
        
        logger.info("Stopped receiving", category: Self.logCategory)
    }
    
    // MARK: - Unified Request API (Recommended)
    
    /// Send a Property Exchange request
    ///
    /// This is the unified entry point for GET and SET operations.
    /// It supports cooperative cancellation via `Task.cancel()`.
    ///
    /// ## Cancellation
    ///
    /// When the calling Task is cancelled:
    /// - The pending transaction is immediately cancelled
    /// - The Request ID is released for reuse
    /// - `PEError.cancelled` is thrown
    ///
    /// ## Example
    ///
    /// ```swift
    /// let handle = PEDeviceHandle(muid: device.muid, destination: destID)
    /// let request = PERequest.get("DeviceInfo", from: handle)
    /// let response = try await peManager.send(request)
    /// ```
    public func send(_ request: PERequest) async throws -> PEResponse {
        // Validate request
        do {
            try request.validate()
        } catch let error as PERequestError {
            throw PEError.validationFailed(error)
        }
        
        logger.debug(
            "\(request.operation.rawValue) \(request.resource) \(request.device.debugDescription)",
            category: Self.logCategory
        )
        
        // Acquire Request ID
        guard let requestID = await transactionManager.begin(
            resource: request.resource,
            destinationMUID: request.device.muid,
            timeout: request.timeout.timeInterval
        ) else {
            throw PEError.requestIDExhausted
        }
        
        // Build message
        let message = buildMessage(for: request, requestID: requestID)
        
        // Execute with cancellation support
        return try await withTaskCancellationHandler {
            try await performRequest(
                requestID: requestID,
                resource: request.resource,
                message: message,
                destination: request.device.destination,
                timeout: request.timeout
            )
        } onCancel: {
            Task { [weak self] in
                await self?.cancelRequest(requestID: requestID)
            }
        }
    }
    
    /// Cancel a pending request by Request ID
    private func cancelRequest(requestID: UInt8) async {
        // Cancel timeout
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        // Release transaction
        await transactionManager.cancel(requestID: requestID)
        
        // Resume continuation with cancellation
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: PEError.cancelled)
        }
        
        logger.debug("Cancelled request [\(requestID)]", category: Self.logCategory)
    }
    
    /// Build MIDI message for a request
    private func buildMessage(for request: PERequest, requestID: UInt8) -> [UInt8] {
        let headerData: Data
        
        // Build header based on request parameters
        if let channel = request.channel {
            headerData = CIMessageBuilder.channelResourceHeader(
                resource: request.resource,
                channel: channel
            )
        } else if let offset = request.offset, let limit = request.limit {
            headerData = CIMessageBuilder.paginatedRequestHeader(
                resource: request.resource,
                offset: offset,
                limit: limit
            )
        } else {
            headerData = CIMessageBuilder.resourceRequestHeader(resource: request.resource)
        }
        
        // Build message based on operation
        switch request.operation {
        case .get:
            return CIMessageBuilder.peGetInquiry(
                sourceMUID: sourceMUID,
                destinationMUID: request.device.muid,
                requestID: requestID,
                headerData: headerData
            )
            
        case .set:
            let encodedData = Mcoded7.encode(request.body ?? Data())
            return CIMessageBuilder.peSetInquiry(
                sourceMUID: sourceMUID,
                destinationMUID: request.device.muid,
                requestID: requestID,
                headerData: headerData,
                propertyData: encodedData
            )
            
        case .subscribe, .unsubscribe:
            // Subscribe/Unsubscribe use different path
            return CIMessageBuilder.peSubscribeInquiry(
                sourceMUID: sourceMUID,
                destinationMUID: request.device.muid,
                requestID: requestID,
                headerData: headerData
            )
        }
    }
    
    // MARK: - GET (Convenience with DeviceHandle)
    
    /// Get a resource from a device
    public func get(
        _ resource: String,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await send(.get(resource, from: device, timeout: timeout))
    }
    
    /// Get a channel-specific resource
    public func get(
        _ resource: String,
        channel: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await send(.get(resource, channel: channel, from: device, timeout: timeout))
    }
    
    /// Get a paginated resource
    public func get(
        _ resource: String,
        offset: Int,
        limit: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await send(.get(resource, offset: offset, limit: limit, from: device, timeout: timeout))
    }
    
    // MARK: - SET (Convenience with DeviceHandle)
    
    /// Set a resource value
    public func set(
        _ resource: String,
        data: Data,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await send(.set(resource, data: data, to: device, timeout: timeout))
    }
    
    /// Set a channel-specific resource
    public func set(
        _ resource: String,
        data: Data,
        channel: Int,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await send(.set(resource, data: data, channel: channel, to: device, timeout: timeout))
    }
    
    // MARK: - GET/SET (MUID-only, destination auto-resolved)
    
    /// Resolve a MUID to a PEDeviceHandle using the configured destinationResolver
    ///
    /// - Parameter muid: Device MUID to resolve
    /// - Returns: PEDeviceHandle if destination was found
    /// - Throws: `PEError.deviceNotFound` if resolver is not set or device not found
    private func resolveDevice(_ muid: MUID) async throws -> PEDeviceHandle {
        guard let resolver = destinationResolver else {
            throw PEError.deviceNotFound(muid)
        }
        guard let destination = await resolver(muid) else {
            throw PEError.deviceNotFound(muid)
        }
        return PEDeviceHandle(muid: muid, destination: destination)
    }
    
    /// Get a resource from a device (MUID-only, destination auto-resolved)
    ///
    /// Requires `destinationResolver` to be configured.
    ///
    /// ## Example
    /// ```swift
    /// peManager.destinationResolver = { muid in
    ///     await ciManager.destination(for: muid)
    /// }
    /// let response = try await peManager.get("DeviceInfo", from: deviceMUID)
    /// ```
    public func get(
        _ resource: String,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let device = try await resolveDevice(muid)
        return try await get(resource, from: device, timeout: timeout)
    }
    
    /// Get a channel-specific resource (MUID-only)
    public func get(
        _ resource: String,
        channel: Int,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let device = try await resolveDevice(muid)
        return try await get(resource, channel: channel, from: device, timeout: timeout)
    }
    
    /// Get a paginated resource (MUID-only)
    public func get(
        _ resource: String,
        offset: Int,
        limit: Int,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let device = try await resolveDevice(muid)
        return try await get(resource, offset: offset, limit: limit, from: device, timeout: timeout)
    }
    
    /// Set a resource value (MUID-only, destination auto-resolved)
    ///
    /// Requires `destinationResolver` to be configured.
    public func set(
        _ resource: String,
        data: Data,
        to muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let device = try await resolveDevice(muid)
        return try await set(resource, data: data, to: device, timeout: timeout)
    }
    
    /// Set a channel-specific resource (MUID-only)
    public func set(
        _ resource: String,
        data: Data,
        channel: Int,
        to muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let device = try await resolveDevice(muid)
        return try await set(resource, data: data, channel: channel, to: device, timeout: timeout)
    }
    
    /// Get DeviceInfo (MUID-only)
    public func getDeviceInfo(from muid: MUID) async throws -> PEDeviceInfo {
        let device = try await resolveDevice(muid)
        return try await getDeviceInfo(from: device)
    }
    
    /// Get ResourceList (MUID-only)
    public func getResourceList(from muid: MUID) async throws -> [PEResourceEntry] {
        let device = try await resolveDevice(muid)
        return try await getResourceList(from: device)
    }
    
    /// Subscribe to notifications (MUID-only)
    public func subscribe(
        to resource: String,
        on muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PESubscribeResponse {
        let device = try await resolveDevice(muid)
        return try await subscribe(to: resource, on: device, timeout: timeout)
    }
    
    // MARK: - Legacy API (MUID + Destination separate)
    
    /// Get a resource from a device (legacy API)
    @available(*, deprecated, message: "Use get(_:from:) with PEDeviceHandle instead")
    public func get(
        resource: String,
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await get(resource, from: handle, timeout: timeout)
    }
    
    /// Get a channel-specific resource (legacy API)
    @available(*, deprecated, message: "Use get(_:channel:from:) with PEDeviceHandle instead")
    public func get(
        resource: String,
        channel: Int,
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await get(resource, channel: channel, from: handle, timeout: timeout)
    }
    
    /// Get a paginated resource (legacy API)
    @available(*, deprecated, message: "Use get(_:offset:limit:from:) with PEDeviceHandle instead")
    public func get(
        resource: String,
        offset: Int,
        limit: Int,
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await get(resource, offset: offset, limit: limit, from: handle, timeout: timeout)
    }
    
    /// Set a resource value (legacy API)
    @available(*, deprecated, message: "Use set(_:data:to:) with PEDeviceHandle instead")
    public func set(
        resource: String,
        data: Data,
        to device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await set(resource, data: data, to: handle, timeout: timeout)
    }
    
    // MARK: - Subscribe
    
    /// Subscribe to notifications for a resource
    public func subscribe(
        to resource: String,
        on device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PESubscribeResponse {
        logger.debug("SUBSCRIBE \(resource) on \(device.debugDescription)", category: Self.logCategory)
        
        guard let requestID = await transactionManager.begin(
            resource: resource,
            destinationMUID: device.muid,
            timeout: timeout.timeInterval
        ) else {
            throw PEError.requestIDExhausted
        }
        
        let headerData = CIMessageBuilder.subscribeStartHeader(resource: resource)
        let message = CIMessageBuilder.peSubscribeInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: device.muid,
            requestID: requestID,
            headerData: headerData
        )
        
        let response = try await withTaskCancellationHandler {
            try await performSubscribeRequest(
                requestID: requestID,
                resource: resource,
                message: message,
                destination: device.destination,
                timeout: timeout
            )
        } onCancel: {
            Task { [weak self] in
                await self?.cancelSubscribeRequest(requestID: requestID)
            }
        }
        
        // Track successful subscription
        if response.isSuccess, let subscribeId = response.subscribeId {
            let subscription = PESubscription(
                subscribeId: subscribeId,
                resource: resource,
                device: device
            )
            activeSubscriptions[subscribeId] = subscription
            logger.info("Subscribed to \(resource): \(subscribeId)", category: Self.logCategory)
        }
        
        return response
    }
    
    /// Subscribe to notifications (legacy API)
    @available(*, deprecated, message: "Use subscribe(to:on:) with PEDeviceHandle instead")
    public func subscribe(
        to resource: String,
        on device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PESubscribeResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await subscribe(to: resource, on: handle, timeout: timeout)
    }
    
    /// Cancel a pending subscribe request
    private func cancelSubscribeRequest(requestID: UInt8) async {
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        await transactionManager.cancel(requestID: requestID)
        
        if let continuation = pendingSubscribeContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: PEError.cancelled)
        }
    }
    
    /// Unsubscribe from a resource
    public func unsubscribe(
        subscribeId: String,
        timeout: Duration = defaultTimeout
    ) async throws -> PESubscribeResponse {
        guard let subscription = activeSubscriptions[subscribeId] else {
            throw PEError.invalidResponse("Unknown subscribeId: \(subscribeId)")
        }
        
        logger.debug("UNSUBSCRIBE \(subscription.resource) [\(subscribeId)]", category: Self.logCategory)
        
        guard let requestID = await transactionManager.begin(
            resource: subscription.resource,
            destinationMUID: subscription.device.muid,
            timeout: timeout.timeInterval
        ) else {
            throw PEError.requestIDExhausted
        }
        
        let headerData = CIMessageBuilder.subscribeEndHeader(
            resource: subscription.resource,
            subscribeId: subscribeId
        )
        let message = CIMessageBuilder.peSubscribeInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: subscription.device.muid,
            requestID: requestID,
            headerData: headerData
        )
        
        let response = try await withTaskCancellationHandler {
            try await performSubscribeRequest(
                requestID: requestID,
                resource: subscription.resource,
                message: message,
                destination: subscription.device.destination,
                timeout: timeout
            )
        } onCancel: {
            Task { [weak self] in
                await self?.cancelSubscribeRequest(requestID: requestID)
            }
        }
        
        // Remove subscription on success
        if response.isSuccess {
            activeSubscriptions.removeValue(forKey: subscribeId)
            logger.info("Unsubscribed: \(subscribeId)", category: Self.logCategory)
        }
        
        return response
    }
    
    /// Get stream of notifications from all subscriptions
    public func startNotificationStream() -> AsyncStream<PENotification> {
        notificationContinuation?.finish()
        
        return AsyncStream { continuation in
            self.notificationContinuation = continuation
        }
    }
    
    /// Get list of active subscriptions
    public var subscriptions: [PESubscription] {
        Array(activeSubscriptions.values)
    }
    
    // MARK: - Convenience Methods
    
    /// Get DeviceInfo from a device
    public func getDeviceInfo(from device: PEDeviceHandle) async throws -> PEDeviceInfo {
        let response = try await get("DeviceInfo", from: device)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        do {
            return try JSONDecoder().decode(PEDeviceInfo.self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode DeviceInfo: \(error)")
        }
    }
    
    /// Get DeviceInfo (legacy API)
    @available(*, deprecated, message: "Use getDeviceInfo(from:) with PEDeviceHandle instead")
    public func getDeviceInfo(
        from device: MUID,
        via destination: MIDIDestinationID
    ) async throws -> PEDeviceInfo {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await getDeviceInfo(from: handle)
    }
    
    /// Get ResourceList from a device
    public func getResourceList(from device: PEDeviceHandle) async throws -> [PEResourceEntry] {
        let response = try await get("ResourceList", from: device)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        do {
            return try JSONDecoder().decode([PEResourceEntry].self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode ResourceList: \(error)")
        }
    }
    
    /// Get ResourceList (legacy API)
    @available(*, deprecated, message: "Use getResourceList(from:) with PEDeviceHandle instead")
    public func getResourceList(
        from device: MUID,
        via destination: MIDIDestinationID
    ) async throws -> [PEResourceEntry] {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await getResourceList(from: handle)
    }
    
    // MARK: - Private: Request Execution
    
    /// Perform a GET/SET request with timeout
    private func performRequest(
        requestID: UInt8,
        resource: String,
        message: [UInt8],
        destination: MIDIDestinationID,
        timeout: Duration
    ) async throws -> PEResponse {
        // Start timeout task
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                await self?.handleTimeout(requestID: requestID, resource: resource)
            } catch {
                // Cancelled - normal completion path
            }
        }
        timeoutTasks[requestID] = timeoutTask
        
        // Wait for response
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations[requestID] = continuation
            
            Task { [weak self] in
                do {
                    try await self?.transport.send(message, to: destination)
                } catch {
                    await self?.handleSendError(requestID: requestID, error: error)
                }
            }
        }
    }
    
    /// Perform a Subscribe/Unsubscribe request with timeout
    private func performSubscribeRequest(
        requestID: UInt8,
        resource: String,
        message: [UInt8],
        destination: MIDIDestinationID,
        timeout: Duration
    ) async throws -> PESubscribeResponse {
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                await self?.handleSubscribeTimeout(requestID: requestID, resource: resource)
            } catch {
                // Cancelled
            }
        }
        timeoutTasks[requestID] = timeoutTask
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingSubscribeContinuations[requestID] = continuation
            
            Task { [weak self] in
                do {
                    try await self?.transport.send(message, to: destination)
                } catch {
                    await self?.handleSubscribeSendError(requestID: requestID, error: error)
                }
            }
        }
    }
    
    // MARK: - Private: Timeout Handling
    
    private func handleTimeout(requestID: UInt8, resource: String) {
        timeoutTasks.removeValue(forKey: requestID)
        
        guard let continuation = pendingContinuations.removeValue(forKey: requestID) else {
            return
        }
        
        logger.notice("Timeout [\(requestID)] \(resource)", category: Self.logCategory)
        
        Task {
            await transactionManager.cancel(requestID: requestID)
        }
        
        continuation.resume(throwing: PEError.timeout(resource: resource))
    }
    
    private func handleSubscribeTimeout(requestID: UInt8, resource: String) {
        timeoutTasks.removeValue(forKey: requestID)
        
        guard let continuation = pendingSubscribeContinuations.removeValue(forKey: requestID) else {
            return
        }
        
        logger.notice("Subscribe timeout [\(requestID)] \(resource)", category: Self.logCategory)
        
        Task {
            await transactionManager.cancel(requestID: requestID)
        }
        
        continuation.resume(throwing: PEError.timeout(resource: resource))
    }
    
    // MARK: - Private: Send Error Handling
    
    private func handleSendError(requestID: UInt8, error: Error) async {
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        await transactionManager.cancel(requestID: requestID)
        
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: PEError.transportError(error))
        }
    }
    
    private func handleSubscribeSendError(requestID: UInt8, error: Error) async {
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        await transactionManager.cancel(requestID: requestID)
        
        if let continuation = pendingSubscribeContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: PEError.transportError(error))
        }
    }
    
    // MARK: - Private: Receive Handling
    
    private func handleReceived(_ data: [UInt8]) async {
        // Try Subscribe Reply first
        if let subscribeReply = CIMessageParser.parseFullSubscribeReply(data) {
            if subscribeReply.destinationMUID == sourceMUID {
                handleSubscribeReply(subscribeReply)
            }
            return
        }
        
        // Try Notify
        if let notify = CIMessageParser.parseFullNotify(data) {
            if notify.destinationMUID == sourceMUID {
                handleNotify(notify)
            }
            return
        }
        
        // Try PE Reply (GET/SET response)
        guard let reply = CIMessageParser.parseFullPEReply(data) else {
            return
        }
        
        guard reply.destinationMUID == sourceMUID else {
            return
        }
        
        let requestID = reply.requestID
        
        logger.debug(
            "Received [\(requestID)] chunk \(reply.thisChunk)/\(reply.numChunks)",
            category: Self.logCategory
        )
        
        // Process chunk through transaction manager
        let result = await transactionManager.processChunk(
            requestID: requestID,
            thisChunk: reply.thisChunk,
            numChunks: reply.numChunks,
            headerData: reply.headerData,
            propertyData: reply.propertyData
        )
        
        switch result {
        case .complete(let header, let body):
            handleComplete(requestID: requestID, header: header, body: body)
            
        case .incomplete:
            // Waiting for more chunks
            break
            
        case .timeout(let id, let received, let expected, _):
            logger.warning(
                "Chunk timeout [\(id)]: \(received)/\(expected) chunks",
                category: Self.logCategory
            )
            handleChunkTimeout(requestID: id)
            
        case .unknownRequestID(let id):
            logger.debug(
                "Ignoring reply for unknown [\(id)]",
                category: Self.logCategory
            )
        }
    }
    
    private func handleComplete(requestID: UInt8, header: Data, body: Data) {
        // Cancel timeout
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        // Release Request ID
        Task {
            await transactionManager.cancel(requestID: requestID)
        }
        
        guard let continuation = pendingContinuations.removeValue(forKey: requestID) else {
            logger.warning("No continuation for [\(requestID)]", category: Self.logCategory)
            return
        }
        
        // Parse header
        let parsedHeader: PEHeader?
        if !header.isEmpty {
            parsedHeader = try? JSONDecoder().decode(PEHeader.self, from: header)
        } else {
            parsedHeader = nil
        }
        
        let status = parsedHeader?.status ?? 200
        let response = PEResponse(status: status, header: parsedHeader, body: body)
        
        logger.debug(
            "Complete [\(requestID)] status=\(status) body=\(body.count)B",
            category: Self.logCategory
        )
        
        continuation.resume(returning: response)
    }
    
    private func handleChunkTimeout(requestID: UInt8) {
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        Task {
            await transactionManager.cancel(requestID: requestID)
        }
        
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: PEError.timeout(resource: "chunk assembly"))
        }
    }
    
    private func handleSubscribeReply(_ reply: CIMessageParser.FullSubscribeReply) {
        let requestID = reply.requestID
        
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        Task {
            await transactionManager.cancel(requestID: requestID)
        }
        
        guard let continuation = pendingSubscribeContinuations.removeValue(forKey: requestID) else {
            logger.warning("No continuation for subscribe [\(requestID)]", category: Self.logCategory)
            return
        }
        
        let response = PESubscribeResponse(
            status: reply.status ?? 200,
            subscribeId: reply.subscribeId
        )
        
        logger.debug(
            "Subscribe reply [\(requestID)] status=\(response.status) id=\(response.subscribeId ?? "nil")",
            category: Self.logCategory
        )
        
        continuation.resume(returning: response)
    }
    
    private func handleNotify(_ notify: CIMessageParser.FullNotify) {
        guard let subscribeId = notify.subscribeId else {
            logger.warning("Notify without subscribeId", category: Self.logCategory)
            return
        }
        
        guard let subscription = activeSubscriptions[subscribeId] else {
            logger.debug("Notify for unknown subscription: \(subscribeId)", category: Self.logCategory)
            return
        }
        
        let parsedHeader: PEHeader?
        if !notify.headerData.isEmpty {
            parsedHeader = try? JSONDecoder().decode(PEHeader.self, from: notify.headerData)
        } else {
            parsedHeader = nil
        }
        
        let decodedData: Data
        if parsedHeader?.isMcoded7 == true {
            decodedData = Mcoded7.decode(notify.propertyData) ?? notify.propertyData
        } else {
            decodedData = notify.propertyData
        }
        
        let notification = PENotification(
            resource: notify.resource ?? subscription.resource,
            subscribeId: subscribeId,
            header: parsedHeader,
            data: decodedData,
            sourceMUID: notify.sourceMUID
        )
        
        logger.debug(
            "Notify \(notification.resource) [\(subscribeId)] \(decodedData.count)B",
            category: Self.logCategory
        )
        
        notificationContinuation?.yield(notification)
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information
    public var diagnostics: String {
        get async {
            var lines: [String] = []
            lines.append("=== PEManager ===")
            lines.append("Source MUID: \(sourceMUID)")
            lines.append("Receiving: \(receiveTask != nil)")
            lines.append("Pending requests: \(pendingContinuations.count)")
            lines.append("Pending subscribe requests: \(pendingSubscribeContinuations.count)")
            lines.append("Active subscriptions: \(activeSubscriptions.count)")
            
            if !activeSubscriptions.isEmpty {
                for (id, sub) in activeSubscriptions {
                    lines.append("  - \(sub.resource) [\(id)]")
                }
            }
            
            lines.append("")
            lines.append(await transactionManager.diagnostics)
            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - Duration Extension

extension Duration {
    /// Convert to TimeInterval
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000
    }
}
