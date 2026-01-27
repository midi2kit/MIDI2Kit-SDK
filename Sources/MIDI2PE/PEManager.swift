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
    ///
    /// Decoding logic:
    /// 1. If header indicates Mcoded7 encoding, decode it
    /// 2. If body starts with '{' or '[', assume it's already JSON
    /// 3. Otherwise, try Mcoded7 decode as fallback (for devices like KORG that don't set the header flag)
    public var decodedBody: Data {
        // If header explicitly indicates Mcoded7
        if header?.isMcoded7 == true {
            return Mcoded7.decode(body) ?? body
        }
        
        // If body looks like JSON already (starts with '{' or '['), return as-is
        if let firstByte = body.first, firstByte == 0x7B || firstByte == 0x5B {
            return body
        }
        
        // Fallback: try Mcoded7 decode for devices that don't set the header flag
        // (e.g., KORG devices send Mcoded7-encoded data without mutualEncoding header)
        if let decoded = Mcoded7.decode(body) {
            return decoded
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
    
    /// Device returned NAK (Negative Acknowledge)
    ///
    /// Contains detailed information about why the request was rejected.
    /// Check `details.isTransient` to determine if retry might succeed.
    case nak(PENAKDetails)
}

// MARK: - PEError Description

extension PEError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .timeout(let resource):
            return "Timeout waiting for response: \(resource)"
        case .cancelled:
            return "Request was cancelled"
        case .requestIDExhausted:
            return "All 128 request IDs are in use"
        case .deviceError(let status, let message):
            if let msg = message {
                return "Device error (\(status)): \(msg)"
            }
            return "Device error: status \(status)"
        case .deviceNotFound(let muid):
            return "Device not found: \(muid)"
        case .invalidResponse(let reason):
            return "Invalid response: \(reason)"
        case .transportError(let error):
            return "Transport error: \(error)"
        case .noDestination:
            return "No destination configured"
        case .validationFailed(let error):
            return "Validation failed: \(error)"
        case .nak(let details):
            return details.description
        }
    }
}

extension PEError: LocalizedError {
    public var errorDescription: String? {
        description
    }
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
    private let notifyAssemblyManager: PENotifyAssemblyManager
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

    /// Send tasks for pending requests (keyed by Request ID)
    ///
    /// We track send Tasks so that `stopReceiving()` can cancel them deterministically.
    /// Without this, a send may occur *after* stop/ID reuse, causing flakey tests and subtle races.
    private var sendTasks: [UInt8: Task<Void, Never>] = [:]
    
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
    ///   - maxInflightPerDevice: Maximum concurrent requests per device (default: 2)
    ///   - logger: Optional logger (default: silent)
    public init(
        transport: any MIDITransport,
        sourceMUID: MUID,
        maxInflightPerDevice: Int = 2,
        notifyAssemblyTimeout: TimeInterval = 2.0,
        logger: any MIDI2Logger = NullMIDI2Logger()
    ) {
        self.transport = transport
        self.sourceMUID = sourceMUID
        self.logger = logger
        self.notifyAssemblyManager = PENotifyAssemblyManager(timeout: notifyAssemblyTimeout, logger: logger)
        self.transactionManager = PETransactionManager(
            maxInflightPerDevice: maxInflightPerDevice,
            logger: logger
        )
    }
    
    deinit {
        // Cancel all tasks
        receiveTask?.cancel()
        
        // Cancel timeout and send tasks
        for (_, task) in timeoutTasks {
            task.cancel()
        }
        for (_, task) in sendTasks {
            task.cancel()
        }
        
        // Finish notification stream
        notificationContinuation?.finish()
        
        // Note: pendingContinuations will be dropped without resuming.
        // Callers should ensure stopReceiving() is called before releasing PEManager.
    }
    
    // MARK: - Lifecycle
    
    /// Start receiving MIDI data
    public func startReceiving() async {
        guard receiveTask == nil else { return }
        
        // Reset transaction manager state (clear isStopped flag)
        await transactionManager.reset()
        await notifyAssemblyManager.cancelAll()
        
        receiveTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await received in transport.received {
                // Check cancellation inside loop since AsyncStream doesn't throw on cancel
                if Task.isCancelled { break }
                await self.handleReceived(received.data)
            }
        }
        
        logger.info("Started receiving", category: Self.logCategory)
    }
    
    /// Reset state for external dispatch mode
    ///
    /// Use this when messages will be dispatched externally via `handleReceivedExternal`
    /// instead of having PEManager consume the transport stream directly.
    /// This resets internal state without starting the receive loop.
    public func resetForExternalDispatch() async {
        // Reset transaction manager state (clear isStopped flag)
        await transactionManager.reset()
        await notifyAssemblyManager.cancelAll()
        
        logger.info("Reset for external dispatch", category: Self.logCategory)
    }
    
    /// Stop receiving and cancel all pending requests
    public func stopReceiving() async {
        // Cancel any pending send tasks first.
        // This prevents a send from firing after stopReceiving()/RequestID reuse.
        for (_, task) in sendTasks {
            task.cancel()
        }
        sendTasks.removeAll()

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

        // Drop any pending Notify assemblies
        await notifyAssemblyManager.cancelAll()
        
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
            timeout: request.timeout.asTimeInterval
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
            timeout: timeout.asTimeInterval
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
        cancelSendTask(requestID: requestID)
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
            timeout: timeout.asTimeInterval
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
    ///
    /// Only one listener is supported at a time. Calling this method
    /// again will finish the previous stream.
    ///
    /// - Returns: AsyncStream of notifications
    public func startNotificationStream() -> AsyncStream<PENotification> {
        // Store and clear old continuation atomically before finishing
        // This prevents handleNotify() from yielding to a finishing continuation
        let oldContinuation = notificationContinuation
        notificationContinuation = nil
        oldContinuation?.finish()
        
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
        
        // Debug: log body details
        let bodyPreview = response.body.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
        let decodedPreview = response.decodedBody.prefix(40).map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.info(
            "DeviceInfo body: raw=\(response.body.count)B [\(bodyPreview)...] decoded=\(response.decodedBody.count)B [\(decodedPreview)...]",
            category: Self.logCategory
        )
        if let str = String(data: response.decodedBody.prefix(100), encoding: .utf8) {
            logger.info("DeviceInfo decoded string: \(str)", category: Self.logCategory)
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
    ///
    /// Includes automatic retry on timeout (up to 3 attempts) to handle
    /// BLE MIDI chunk loss issues observed with some devices (e.g., KORG Module).
    public func getResourceList(
        from device: PEDeviceHandle,
        maxRetries: Int = 3
    ) async throws -> [PEResourceEntry] {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let response = try await get("ResourceList", from: device)
                
                guard response.isSuccess else {
                    throw PEError.deviceError(status: response.status, message: response.header?.message)
                }
                
                do {
                    let result = try JSONDecoder().decode([PEResourceEntry].self, from: response.decodedBody)
                    if attempt > 1 {
                        logger.info("ResourceList succeeded on attempt \(attempt)", category: Self.logCategory)
                    }
                    return result
                } catch {
                    throw PEError.invalidResponse("Failed to decode ResourceList: \(error)")
                }
            } catch let error as PEError {
                lastError = error
                
                // Only retry on timeout or chunk assembly timeout
                switch error {
                case .timeout:
                    if attempt < maxRetries {
                        logger.notice("ResourceList timeout, retrying (\(attempt)/\(maxRetries))...", category: Self.logCategory)
                        // Brief delay before retry
                        try? await Task.sleep(for: .milliseconds(200))
                        continue
                    }
                case .invalidResponse(let reason) where reason.contains("decode"):
                    // JSON decode error might be from chunk loss, retry
                    if attempt < maxRetries {
                        logger.notice("ResourceList decode error, retrying (\(attempt)/\(maxRetries))...", category: Self.logCategory)
                        try? await Task.sleep(for: .milliseconds(200))
                        continue
                    }
                default:
                    // Don't retry other errors
                    throw error
                }
            }
        }
        
        throw lastError ?? PEError.timeout(resource: "ResourceList")
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
    
    // MARK: - Typed API (JSON Codable)
    
    /// Get a resource and decode as JSON
    ///
    /// Automatically handles:
    /// - Mcoded7 decoding
    /// - JSON deserialization
    /// - Error status checking
    ///
    /// ## Example
    /// ```swift
    /// struct ProgramInfo: Decodable {
    ///     let name: String
    ///     let bankMSB: Int
    /// }
    /// let program: ProgramInfo = try await peManager.getJSON("ProgramInfo", from: device)
    /// ```
    public func getJSON<T: Decodable>(
        _ resource: String,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let response = try await get(resource, from: device, timeout: timeout)
        return try decodeResponse(response, resource: resource)
    }
    
    /// Get a channel-specific resource and decode as JSON
    public func getJSON<T: Decodable>(
        _ resource: String,
        channel: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let response = try await get(resource, channel: channel, from: device, timeout: timeout)
        return try decodeResponse(response, resource: resource)
    }
    
    /// Get a paginated resource and decode as JSON
    public func getJSON<T: Decodable>(
        _ resource: String,
        offset: Int,
        limit: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let response = try await get(resource, offset: offset, limit: limit, from: device, timeout: timeout)
        return try decodeResponse(response, resource: resource)
    }
    
    /// Get a resource and decode as JSON (MUID-only)
    public func getJSON<T: Decodable>(
        _ resource: String,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let device = try await resolveDevice(muid)
        return try await getJSON(resource, from: device, timeout: timeout)
    }
    
    /// Get a channel-specific resource and decode as JSON (MUID-only)
    public func getJSON<T: Decodable>(
        _ resource: String,
        channel: Int,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let device = try await resolveDevice(muid)
        return try await getJSON(resource, channel: channel, from: device, timeout: timeout)
    }
    
    /// Set a resource with JSON-encoded value
    ///
    /// Automatically handles:
    /// - JSON serialization
    /// - Error status checking
    ///
    /// ## Example
    /// ```swift
    /// struct ProgramSettings: Encodable {
    ///     let name: String
    ///     let volume: Int
    /// }
    /// let settings = ProgramSettings(name: "My Sound", volume: 100)
    /// try await peManager.setJSON("ProgramSettings", value: settings, to: device)
    /// ```
    public func setJSON<T: Encodable>(
        _ resource: String,
        value: T,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let data = try encodeValue(value, resource: resource)
        return try await set(resource, data: data, to: device, timeout: timeout)
    }
    
    /// Set a channel-specific resource with JSON-encoded value
    public func setJSON<T: Encodable>(
        _ resource: String,
        value: T,
        channel: Int,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let data = try encodeValue(value, resource: resource)
        return try await set(resource, data: data, channel: channel, to: device, timeout: timeout)
    }
    
    /// Set a resource with JSON-encoded value (MUID-only)
    public func setJSON<T: Encodable>(
        _ resource: String,
        value: T,
        to muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let device = try await resolveDevice(muid)
        return try await setJSON(resource, value: value, to: device, timeout: timeout)
    }
    
    /// Set a channel-specific resource with JSON-encoded value (MUID-only)
    public func setJSON<T: Encodable>(
        _ resource: String,
        value: T,
        channel: Int,
        to muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let device = try await resolveDevice(muid)
        return try await setJSON(resource, value: value, channel: channel, to: device, timeout: timeout)
    }
    
    // MARK: - Private: JSON Helpers
    
    /// Decode a PE response as JSON
    private func decodeResponse<T: Decodable>(_ response: PEResponse, resource: String) throws -> T {
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode \(resource): \(error)")
        }
    }
    
    /// Encode a value as JSON
    private func encodeValue<T: Encodable>(_ value: T, resource: String) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw PEError.invalidResponse("Failed to encode \(resource): \(error)")
        }
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
            scheduleSendForRequest(requestID: requestID, message: message, destination: destination)
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
            scheduleSendForSubscribe(requestID: requestID, message: message, destination: destination)
        }
    }

    
    // MARK: - Private: Send Task Tracking

    private func scheduleSendForRequest(
        requestID: UInt8,
        message: [UInt8],
        destination: MIDIDestinationID
    ) {
        cancelSendTask(requestID: requestID)
        
        // DEBUG: Log send attempt with hex dump
        let hexMsg = message.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[PE-SEND] Sending request [\(requestID)] to destination \(destination), message len=\(message.count)")
        print("[PE-SEND] Message: \(hexMsg)")

        let transport = self.transport
        sendTasks[requestID] = Task { [weak self] in
            if Task.isCancelled { return }
            do {
                // WORKAROUND: Broadcast to all destinations for KORG compatibility
                // KORG devices may not respond when sent to specific destinations,
                // but will respond when the message reaches them via broadcast.
                // This mimics the behavior of SimpleMidiController which works with KORG.
                print("[PE-SEND] Broadcasting request [\(requestID)] to all destinations")
                try await transport.broadcast(message)
                print("[PE-SEND] Request [\(requestID)] broadcast completed")
            } catch {
                print("[PE-SEND] Request [\(requestID)] broadcast FAILED: \(error)")
                guard let self else { return }
                await self.handleSendError(requestID: requestID, error: error)
            }
            await self?.clearSendTask(requestID: requestID)
        }
    }

    private func scheduleSendForSubscribe(
        requestID: UInt8,
        message: [UInt8],
        destination: MIDIDestinationID
    ) {
        cancelSendTask(requestID: requestID)

        let transport = self.transport
        sendTasks[requestID] = Task { [weak self] in
            if Task.isCancelled { return }
            do {
                try await transport.send(message, to: destination)
            } catch {
                guard let self else { return }
                await self.handleSubscribeSendError(requestID: requestID, error: error)
            }
            await self?.clearSendTask(requestID: requestID)
        }
    }

    private func cancelSendTask(requestID: UInt8) {
        if let task = sendTasks.removeValue(forKey: requestID) {
            task.cancel()
        }
    }

    private func clearSendTask(requestID: UInt8) {
        sendTasks.removeValue(forKey: requestID)
    }

    // MARK: - Private: Timeout Handling
    
    private func handleTimeout(requestID: UInt8, resource: String) {
        clearSendTask(requestID: requestID)
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
        clearSendTask(requestID: requestID)
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
        clearSendTask(requestID: requestID)
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        await transactionManager.cancel(requestID: requestID)
        
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: PEError.transportError(error))
        }
    }
    
    private func handleSubscribeSendError(requestID: UInt8, error: Error) async {
        clearSendTask(requestID: requestID)
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        await transactionManager.cancel(requestID: requestID)
        
        if let continuation = pendingSubscribeContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: PEError.transportError(error))
        }
    }
    
    // MARK: - Public: External Receive Handling
    
    /// Handle received data from external dispatcher
    ///
    /// Use this when you need to manually dispatch messages to PEManager
    /// instead of having PEManager consume the transport stream directly.
    /// This is useful when multiple managers need to receive the same data.
    public func handleReceivedExternal(_ data: [UInt8]) async {
        // Detailed debug logging for PE messages
        if data.count > 10 && data[0] == 0xF0 && data.count > 4 {
            let subID2 = data[4]
            // PE Reply messages
            if subID2 == 0x35 || subID2 == 0x36 {
                let hexDump = data.prefix(50).map { String(format: "%02X", $0) }.joined(separator: " ")
                print("[PEManager] Received PE Reply (0x\(String(format: "%02X", subID2))) len=\(data.count)")
                print("[PEManager]   Raw: \(hexDump)\(data.count > 50 ? "..." : "")")
                
                // Try to parse and log
                if let parsed = CIMessageParser.parse(data) {
                    print("[PEManager]   Parsed: src=\(parsed.sourceMUID) dst=\(parsed.destinationMUID)")
                    print("[PEManager]   Our MUID: \(sourceMUID)")
                    print("[PEManager]   MUID match: \(parsed.destinationMUID == sourceMUID)")
                } else {
                    print("[PEManager]   PARSE FAILED!")
                }
            }
        }
        await handleReceived(data)
    }
    
    // MARK: - Private: Receive Handling
    
    private func handleReceived(_ data: [UInt8]) async {
        // Try NAK first (device rejection)
        if let nak = CIMessageParser.parseFullNAK(data) {
            if nak.destinationMUID == sourceMUID {
                handleNAK(nak)
            }
            return
        }
        
        // Try Subscribe Reply
        if let subscribeReply = CIMessageParser.parseFullSubscribeReply(data) {
            if subscribeReply.destinationMUID == sourceMUID {
                handleSubscribeReply(subscribeReply)
            }
            return
        }
        
        // Try Notify
        if let notify = CIMessageParser.parseFullNotify(data) {
            if notify.destinationMUID == sourceMUID {
                // Notify may be multi-chunk. For multi-chunk, the subscribeId/resource
                // may only exist in chunk 1, so we must assemble before dispatch.
                if notify.numChunks <= 1 {
                    handleNotify(notify)
                } else {
                    let result = await notifyAssemblyManager.processChunk(
                        sourceMUID: notify.sourceMUID,
                        requestID: notify.requestID,
                        thisChunk: notify.thisChunk,
                        numChunks: notify.numChunks,
                        headerData: notify.headerData,
                        propertyData: notify.propertyData
                    )

                    switch result {
                    case .complete(let header, let body):
                        let info = parseNotifyHeaderInfo(header)
                        handleNotifyParts(
                            sourceMUID: notify.sourceMUID,
                            subscribeId: info.subscribeId,
                            resource: info.resource,
                            headerData: header,
                            propertyData: body
                        )
                    case .incomplete:
                        break
                    case .timeout(let id, let received, let expected, _):
                        logger.warning(
                            "Notify chunk timeout [\(id)]: \(received)/\(expected) chunks",
                            category: Self.logCategory
                        )
                    case .unknownRequestID(let id):
                        logger.debug(
                            "Ignoring notify for unknown [\(id)]",
                            category: Self.logCategory
                        )
                    }
                }
            }
            return
        }
        
        // Try PE Reply (GET/SET response)
        guard let reply = CIMessageParser.parseFullPEReply(data) else {
            // Debug: log why parsing failed for PE-like messages
            if data.count > 4 && data[4] == 0x35 {
                // Dump payload bytes for debugging
                let payloadStart = min(14, data.count - 1)
                let payloadPreview = data.count > payloadStart ? Array(data[payloadStart..<min(payloadStart + 20, data.count)]) : []
                let hexPreview = payloadPreview.map { String(format: "%02X", $0) }.joined(separator: " ")
                logger.debug(
                    "parseFullPEReply failed for 0x35: len=\(data.count), payload[14..]: \(hexPreview)",
                    category: Self.logCategory
                )
            }
            return
        }
        
        // Debug: log MUID mismatch
        if reply.destinationMUID != sourceMUID {
            logger.debug(
                "PE Reply MUID mismatch: dest=\(reply.destinationMUID) ours=\(sourceMUID)",
                category: Self.logCategory
            )
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
        
        logger.debug(
            "processChunk result for [\(requestID)]: \(String(describing: result))",
            category: Self.logCategory
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

        clearSendTask(requestID: requestID)
        
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

        clearSendTask(requestID: requestID)
        
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

        clearSendTask(requestID: requestID)
        
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
    
    private func handleNAK(_ nak: CIMessageParser.FullNAK) {
        let details = PENAKDetails(from: nak)
        
        logger.warning(
            "Received NAK: \(details)",
            category: Self.logCategory
        )
        
        // NAK doesn't include requestID, so we can't directly map it to a pending request.
        // For PE operations, the device typically returns a PE Reply with error status instead of NAK.
        // NAK is used for protocol-level rejections (unsupported message type, version mismatch, etc.)
        //
        // If there's only one pending request, we can reasonably assume it's for that request.
        // Otherwise, we log the NAK for debugging purposes.
        
        if pendingContinuations.count == 1,
           let (requestID, continuation) = pendingContinuations.first {
            // Single pending request - assume NAK is for this request
            timeoutTasks[requestID]?.cancel()
            timeoutTasks.removeValue(forKey: requestID)
            clearSendTask(requestID: requestID)
            pendingContinuations.removeValue(forKey: requestID)
            
            Task {
                await transactionManager.cancel(requestID: requestID)
            }
            
            continuation.resume(throwing: PEError.nak(details))
            
            logger.notice(
                "NAK matched to request [\(requestID)]",
                category: Self.logCategory
            )
        } else if pendingSubscribeContinuations.count == 1,
                  let (requestID, continuation) = pendingSubscribeContinuations.first {
            // Single pending subscribe request
            timeoutTasks[requestID]?.cancel()
            timeoutTasks.removeValue(forKey: requestID)
            clearSendTask(requestID: requestID)
            pendingSubscribeContinuations.removeValue(forKey: requestID)
            
            Task {
                await transactionManager.cancel(requestID: requestID)
            }
            
            continuation.resume(throwing: PEError.nak(details))
            
            logger.notice(
                "NAK matched to subscribe request [\(requestID)]",
                category: Self.logCategory
            )
        }
        // If multiple requests are pending, we can't determine which one the NAK is for.
        // The request will eventually timeout.
    }
    
    private func handleNotify(_ notify: CIMessageParser.FullNotify) {
        handleNotifyParts(
            sourceMUID: notify.sourceMUID,
            subscribeId: notify.subscribeId,
            resource: notify.resource,
            headerData: notify.headerData,
            propertyData: notify.propertyData
        )
    }

    private func handleNotifyParts(
        sourceMUID: MUID,
        subscribeId: String?,
        resource: String?,
        headerData: Data,
        propertyData: Data
    ) {
        guard let subscribeId = subscribeId else {
            logger.warning("Notify without subscribeId", category: Self.logCategory)
            return
        }

        guard let subscription = activeSubscriptions[subscribeId] else {
            logger.debug("Notify for unknown subscription: \(subscribeId)", category: Self.logCategory)
            return
        }

        let parsedHeader: PEHeader?
        if !headerData.isEmpty {
            parsedHeader = try? JSONDecoder().decode(PEHeader.self, from: headerData)
        } else {
            parsedHeader = nil
        }

        let decodedData: Data
        if parsedHeader?.isMcoded7 == true {
            decodedData = Mcoded7.decode(propertyData) ?? propertyData
        } else {
            decodedData = propertyData
        }

        let notification = PENotification(
            resource: resource ?? subscription.resource,
            subscribeId: subscribeId,
            header: parsedHeader,
            data: decodedData,
            sourceMUID: sourceMUID
        )

        logger.debug(
            "Notify \(notification.resource) [\(subscribeId)] \(decodedData.count)B",
            category: Self.logCategory
        )

        notificationContinuation?.yield(notification)
    }

    private func parseNotifyHeaderInfo(_ headerData: Data) -> (subscribeId: String?, resource: String?) {
        guard !headerData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            return (nil, nil)
        }
        return (
            json["subscribeId"] as? String,
            json["resource"] as? String
        )
    }

    // MARK: - Testing Hooks (internal)

    internal func pollNotifyTimeoutsForTesting() async -> [PENotifyTimeout] {
        await notifyAssemblyManager.pollTimeouts()
    }

    internal func notifyPendingCountForTesting() async -> Int {
        await notifyAssemblyManager.pendingCount
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
