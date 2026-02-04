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
    @available(*, deprecated, message: "Use MIDI2Client (destination resolver integrated)")
    public var destinationResolver: (@Sendable (MUID) async -> MIDIDestinationID?)?
    
    // MARK: - Send Strategy
    
    /// PE send strategy (controls broadcast vs single destination behavior)
    ///
    /// Default is `.broadcast` for backward compatibility.
    /// Set to `.fallback` for smarter behavior that learns successful destinations.
    public var sendStrategy: PESendStrategy = .broadcast
    
    /// Destination cache for learned successful destinations
    ///
    /// Used by `.fallback` and `.learned` strategies.
    public let destinationCache: DestinationCache
    
    // MARK: - Receive State
    
    /// Task that processes incoming MIDI data
    private var receiveTask: Task<Void, Never>?
    
    // MARK: - GET/SET Request State
    
    /// Continuations waiting for GET/SET responses (keyed by Request ID)
    ///
    /// Single source of truth for request completion.
    /// When a response arrives or timeout fires, the continuation is resumed and removed.
    private var pendingContinuations: [UInt8: CheckedContinuation<PEResponse, Error>] = [:]

    /// Last decoding diagnostics (for debugging failed PE responses)
    ///
    /// Contains detailed information about the most recent decoding attempt,
    /// including raw data, preprocessing results, and error details.
    /// Useful for debugging parsing issues with embedded MIDI devices.
    ///
    /// ## Usage
    /// ```swift
    /// do {
    ///     let deviceInfo = try await peManager.getDeviceInfo(from: device)
    /// } catch let error as PEError {
    ///     if let diag = await peManager.lastDecodingDiagnostics {
    ///         print("Decoding failed: \(diag)")
    ///     }
    /// }
    /// ```
    ///
    /// Note: This property uses nonisolated(unsafe) storage for diagnostics to allow
    /// synchronous access from throwing decode methods. Since PEDecodingDiagnostics
    /// is Sendable and writes only occur from decode paths, this is safe for diagnostic purposes.
    nonisolated(unsafe) internal var _lastDecodingDiagnostics: PEDecodingDiagnostics?

    /// Public accessor for last decoding diagnostics
    public var lastDecodingDiagnostics: PEDecodingDiagnostics? {
        _lastDecodingDiagnostics
    }
    
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
    
    /// Pending request metadata for cache update (keyed by Request ID)
    ///
    /// When a successful response arrives, we use this to update the destination cache.
    /// Format: [requestID: (targetMUID, sentDestination)]
    private var pendingRequestMetadata: [UInt8: (muid: MUID, destination: MIDIDestinationID)] = [:]
    
    // MARK: - Subscribe State

    /// Subscription handler for managing Subscribe/Unsubscribe/Notify operations
    /// Introduced in Phase 5-1 for better modularity
    private var subscriptionHandler: PESubscriptionHandler?
    
    // MARK: - Initialization
    
    /// Initialize PEManager
    /// - Parameters:
    ///   - transport: MIDI transport for sending/receiving
    ///   - sourceMUID: Our MUID (for message filtering)
    ///   - maxInflightPerDevice: Maximum concurrent requests per device (default: 2)
    ///   - requestIDCooldownPeriod: Cooldown period in seconds before reusing released Request IDs (default: 2.0).
    ///     Set to `0` in tests to allow immediate ID reuse.
    ///   - notifyAssemblyTimeout: Timeout for assembling multi-chunk notify messages (default: 2.0 seconds)
    ///   - destinationCacheTTL: Time-to-live for destination cache entries (default: 30 minutes)
    ///   - sendStrategy: PE send strategy (default: .broadcast for backward compatibility)
    ///   - logger: Optional logger (default: silent)
    public init(
        transport: any MIDITransport,
        sourceMUID: MUID,
        maxInflightPerDevice: Int = 2,
        requestIDCooldownPeriod: TimeInterval = 2.0,
        notifyAssemblyTimeout: TimeInterval = 2.0,
        destinationCacheTTL: TimeInterval = 1800,
        sendStrategy: PESendStrategy = .broadcast,
        logger: any MIDI2Logger = NullMIDI2Logger()
    ) {
        self.transport = transport
        self.sourceMUID = sourceMUID
        self.sendStrategy = sendStrategy
        self.logger = logger
        self.destinationCache = DestinationCache(ttl: destinationCacheTTL)
        self.notifyAssemblyManager = PENotifyAssemblyManager(timeout: notifyAssemblyTimeout, logger: logger)
        self.transactionManager = PETransactionManager(
            maxInflightPerDevice: maxInflightPerDevice,
            requestIDCooldownPeriod: requestIDCooldownPeriod,
            logger: logger
        )

        // subscriptionHandler is initialized in startReceiving() or resetForExternalDispatch()
        // to allow proper callback binding after self is fully initialized (Phase 5-1)
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

        // Note: pendingContinuations will be dropped without resuming.
        // subscriptionHandler cleanup is handled by its own deinit.
        // Callers should ensure stopReceiving() is called before releasing PEManager.
    }
    
    // MARK: - Lifecycle
    /// Initialize subscription handler with proper callbacks (Phase 5-1)
    ///
    /// Called from startReceiving() or resetForExternalDispatch() after self is fully initialized.
    private func initializeSubscriptionHandler() {
        // Only initialize once
        guard subscriptionHandler == nil else { return }

        subscriptionHandler = PESubscriptionHandler(
            sourceMUID: sourceMUID,
            transactionManager: transactionManager,
            notifyAssemblyManager: notifyAssemblyManager,
            logger: logger,
            scheduleTimeout: { [weak self] requestID, duration, action in
                Task { [weak self] in
                    await self?.scheduleSubscribeTimeout(requestID: requestID, duration: duration, action: action)
                }
            },
            cancelTimeout: { [weak self] requestID in
                Task { [weak self] in
                    await self?.cancelSubscribeTimeout(requestID: requestID)
                }
            },
            scheduleSend: { [weak self] requestID, message, destination in
                Task { [weak self] in
                    await self?.scheduleSubscribeSend(requestID: requestID, message: message, destination: destination)
                }
            },
            cancelSend: { [weak self] requestID in
                Task { [weak self] in
                    await self?.cancelSubscribeSend(requestID: requestID)
                }
            }
        )
    }

    /// Schedule a timeout for subscription handler (Phase 5-1)
    private func scheduleSubscribeTimeout(requestID: UInt8, duration: Duration, action: @escaping @Sendable () async -> Void) {
        let task = Task {
            do {
                try await Task.sleep(for: duration)
                await action()
            } catch {
                // Cancelled - normal completion path
            }
        }
        timeoutTasks[requestID] = task
    }

    /// Cancel a timeout for subscription handler (Phase 5-1)
    private func cancelSubscribeTimeout(requestID: UInt8) {
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
    }

    /// Schedule a send for subscription handler (Phase 5-1)
    private func scheduleSubscribeSend(requestID: UInt8, message: [UInt8], destination: MIDIDestinationID) {
        let transport = self.transport
        let logger = self.logger
        let task = Task {
            do {
                try await transport.send(message, to: destination)
            } catch {
                logger.error("Send failed [\(requestID)]: \(error)", category: Self.logCategory)
            }
        }
        sendTasks[requestID] = task
    }

    /// Cancel a send for subscription handler (Phase 5-1)
    private func cancelSubscribeSend(requestID: UInt8) {
        sendTasks[requestID]?.cancel()
        sendTasks.removeValue(forKey: requestID)
    }

    /// Start receiving MIDI data
    @available(*, deprecated, message: "Use MIDI2Client.start() instead")
    public func startReceiving() async {
        guard receiveTask == nil else { return }

        // Initialize subscription handler with proper callbacks (Phase 5-1)
        initializeSubscriptionHandler()

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
        // Initialize subscription handler with proper callbacks (Phase 5-1)
        initializeSubscriptionHandler()

        // Reset transaction manager state (clear isStopped flag)
        await transactionManager.reset()
        await notifyAssemblyManager.cancelAll()
        
        logger.info("Reset for external dispatch", category: Self.logCategory)
    }
    
    /// Stop receiving and cancel all pending requests
    @available(*, deprecated, message: "Use MIDI2Client.stop() instead")
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
        
        // Clear pending request metadata
        pendingRequestMetadata.removeAll()
        
        // Cancel all subscription-related state (Phase 5-1)
        await subscriptionHandler?.cancelAll()

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
        pendingRequestMetadata.removeValue(forKey: requestID)
        
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
    internal func resolveDevice(_ muid: MUID) async throws -> PEDeviceHandle {
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
    public func getResourceList(
        from muid: MUID,
        timeout: Duration = defaultTimeout,
        maxRetries: Int = 5
    ) async throws -> [PEResourceEntry] {
        let device = try await resolveDevice(muid)
        return try await getResourceList(from: device, timeout: timeout, maxRetries: maxRetries)
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

    // MARK: - Subscribe

    /// Subscribe to notifications for a resource
    ///
    /// Note: Must be called after `startReceiving()` or `resetForExternalDispatch()`.
    public func subscribe(
        to resource: String,
        on device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PESubscribeResponse {
        guard let handler = subscriptionHandler else {
            logger.warning("subscribe called before startReceiving", category: Self.logCategory)
            throw PEError.invalidResponse("PEManager not initialized - call startReceiving first")
        }
        return try await handler.subscribe(to: resource, on: device, timeout: timeout)
    }

    /// Unsubscribe from a resource
    ///
    /// Note: Must be called after `startReceiving()` or `resetForExternalDispatch()`.
    public func unsubscribe(
        subscribeId: String,
        timeout: Duration = defaultTimeout
    ) async throws -> PESubscribeResponse {
        guard let handler = subscriptionHandler else {
            logger.warning("unsubscribe called before startReceiving", category: Self.logCategory)
            throw PEError.invalidResponse("PEManager not initialized - call startReceiving first")
        }
        return try await handler.unsubscribe(subscribeId: subscribeId, timeout: timeout)
    }
    
    /// Get stream of notifications from all subscriptions
    ///
    /// Only one listener is supported at a time. Calling this method
    /// again will finish the previous stream.
    ///
    /// Note: Must be called after `startReceiving()` or `resetForExternalDispatch()`.
    ///
    /// - Returns: AsyncStream of notifications
    public func startNotificationStream() async -> AsyncStream<PENotification> {
        // Delegate to subscriptionHandler (Phase 5-1)
        guard let handler = subscriptionHandler else {
            logger.warning("startNotificationStream called before startReceiving", category: Self.logCategory)
            // Return empty stream if handler not initialized
            return AsyncStream { $0.finish() }
        }
        return await handler.startNotificationStream()
    }
    
    /// Get list of active subscriptions
    public var subscriptions: [PESubscription] {
        get async {
            await subscriptionHandler?.subscriptions ?? []
        }
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

        return try decodeDeviceInfo(from: response)
    }

    /// Get ResourceList from a device
    ///
    /// Includes automatic retry on timeout (up to 5 attempts) to handle
    /// BLE MIDI chunk loss issues observed with some devices (e.g., KORG Module).
    /// BLE MIDI is unreliable and packet loss is common - retrying is more effective than waiting.
    public func getResourceList(
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout,
        maxRetries: Int = 5
    ) async throws -> [PEResourceEntry] {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                let response = try await get("ResourceList", from: device, timeout: timeout)
                
                guard response.isSuccess else {
                    throw PEError.deviceError(status: response.status, message: response.header?.message)
                }
                
                let result = try decodeResourceList(from: response)
                if attempt > 1 {
                    logger.info("ResourceList succeeded on attempt \(attempt)", category: Self.logCategory)
                }
                return result
            } catch let error as PEError {
                lastError = error
                
                // Only retry on timeout or chunk assembly timeout
                switch error {
                case .timeout:
                    if attempt < maxRetries {
                        logger.notice("ResourceList timeout, retrying (\(attempt)/\(maxRetries))...", category: Self.logCategory)
                        // Brief delay before retry (100ms for faster iteration)
                        try? await Task.sleep(for: .milliseconds(100))
                        continue
                    }
                case .invalidResponse(let reason) where reason.contains("decode"):
                    // JSON decode error might be from chunk loss, retry
                    if attempt < maxRetries {
                        logger.notice("ResourceList decode error, retrying (\(attempt)/\(maxRetries))...", category: Self.logCategory)
                        try? await Task.sleep(for: .milliseconds(100))
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

    // MARK: - Internal: JSON Helpers

    /// Decode a PE response as JSON
    internal func decodeResponse<T: Decodable>(_ response: PEResponse, resource: String) throws -> T {
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }

        return try self.decodeResponse(T.self, from: response, resource: resource).value
    }
    
    /// Encode a value as JSON
    internal func encodeValue<T: Encodable>(_ value: T, resource: String) throws -> Data {
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

    
    // MARK: - Private: Send Task Tracking

    private func scheduleSendForRequest(
        requestID: UInt8,
        message: [UInt8],
        destination: MIDIDestinationID
    ) {
        cancelSendTask(requestID: requestID)
        
        let transport = self.transport
        let strategy = self.sendStrategy
        let cache = self.destinationCache
        let logger = self.logger
        
        // Extract MUID from message for cache lookup (bytes 9-12 are destination MUID)
        let targetMUID: MUID? = message.count >= 13 ? MUID(rawValue:
            UInt32(message[9]) |
            (UInt32(message[10]) << 7) |
            (UInt32(message[11]) << 14) |
            (UInt32(message[12]) << 21)
        ) : nil
        
        // Record metadata for cache update on success
        if let muid = targetMUID {
            pendingRequestMetadata[requestID] = (muid: muid, destination: destination)
        }
        
        sendTasks[requestID] = Task { [weak self] in
            if Task.isCancelled { return }
            
            do {
                switch strategy {
                case .single:
                    // Send to resolved destination only
                    logger.debug("[PE-SEND] Single send [\(requestID)] to \(destination)", category: "PEManager")
                    try await transport.send(message, to: destination)
                    
                case .broadcast:
                    // Broadcast to all destinations (legacy behavior)
                    logger.debug("[PE-SEND] Broadcast [\(requestID)] to all destinations", category: "PEManager")
                    try await transport.broadcast(message)
                    
                case .learned:
                    // Use cached destination only, fail if not cached
                    if let muid = targetMUID,
                       let cachedDest = await cache.getCachedDestination(for: muid) {
                        logger.debug("[PE-SEND] Learned send [\(requestID)] to cached \(cachedDest)", category: "PEManager")
                        try await transport.send(message, to: cachedDest)
                    } else {
                        logger.warning("[PE-SEND] No cached destination for [\(requestID)], failing", category: "PEManager")
                        throw PEError.noDestination
                    }
                    
                case .fallback:
                    // Try cached first, then resolved, then broadcast
                    var sent = false
                    
                    // Step 1: Try cached destination
                    if let muid = targetMUID,
                       let cachedDest = await cache.getCachedDestination(for: muid) {
                        logger.debug("[PE-SEND] Fallback step 1: cached \(cachedDest) [\(requestID)]", category: "PEManager")
                        try await transport.send(message, to: cachedDest)
                        sent = true
                    }
                    
                    // Step 2: Try resolved destination (if different from cached)
                    if !sent {
                        logger.debug("[PE-SEND] Fallback step 2: resolved \(destination) [\(requestID)]", category: "PEManager")
                        try await transport.send(message, to: destination)
                        sent = true
                    }
                    
                    // Note: Step 3 (broadcast on timeout) is handled by retry logic at higher level
                    // For now, we just send to the resolved destination
                    
                case .custom(let resolver):
                    // Get destinations from custom resolver
                    let destinations = await transport.destinations.map { $0.destinationID }
                    let selectedDests = await resolver(destinations)
                    
                    if selectedDests.isEmpty {
                        logger.warning("[PE-SEND] Custom resolver returned no destinations [\(requestID)]", category: "PEManager")
                        throw PEError.noDestination
                    }
                    
                    // Send to all selected destinations
                    for dest in selectedDests {
                        logger.debug("[PE-SEND] Custom send [\(requestID)] to \(dest)", category: "PEManager")
                        try await transport.send(message, to: dest)
                    }
                }
            } catch {
                logger.error("[PE-SEND] Request [\(requestID)] send FAILED: \(error)", category: "PEManager")
                guard let self else { return }
                await self.handleSendError(requestID: requestID, error: error)
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
        pendingRequestMetadata.removeValue(forKey: requestID)
        
        guard let continuation = pendingContinuations.removeValue(forKey: requestID) else {
            return
        }
        
        logger.notice("Timeout [\(requestID)] \(resource)", category: Self.logCategory)
        
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
        pendingRequestMetadata.removeValue(forKey: requestID)
        
        await transactionManager.cancel(requestID: requestID)
        
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
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
                logger.debug(
                    "PE Reply (0x\(String(format: "%02X", subID2))) len=\(data.count) raw=\(data.logPreview(limit: 50))",
                    category: Self.logCategory
                )

                // Try to parse and log
                if let parsed = CIMessageParser.parse(data) {
                    logger.debug(
                        "Parsed: src=\(MIDI2LogUtils.formatMUID(parsed.sourceMUID.value)) dst=\(MIDI2LogUtils.formatMUID(parsed.destinationMUID.value)) (ours=\(MIDI2LogUtils.formatMUID(sourceMUID.value))) match=\(parsed.destinationMUID == sourceMUID)",
                        category: Self.logCategory
                    )
                } else {
                    logger.warning("PE Reply parse failed", category: Self.logCategory)
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
                await subscriptionHandler?.handleSubscribeReply(subscribeReply)
            }
            return
        }

        // Try Notify
        if let notify = CIMessageParser.parseFullNotify(data) {
            if notify.destinationMUID == sourceMUID {
                await handleNotify(notify)
            }
            return
        }

        // Try PE Reply (GET/SET response)
        if let reply = CIMessageParser.parseFullPEReply(data) {
            await handlePEReply(reply, rawData: data)
        } else {
            logPEReplyParseFailure(data)
        }
    }

    // MARK: - Private: Message Handlers

    /// Handle multi-chunk Notify messages
    private func handleNotify(_ notify: CIMessageParser.FullNotify) async {
        // Notify may be multi-chunk. For multi-chunk, the subscribeId/resource
        // may only exist in chunk 1, so we must assemble before dispatch.
        if notify.numChunks <= 1 {
            await subscriptionHandler?.handleNotify(notify)
            return
        }

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
            await subscriptionHandler?.handleNotifyParts(
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

    /// Handle PE Reply (GET/SET response)
    private func handlePEReply(_ reply: CIMessageParser.FullPEReply, rawData: [UInt8]) async {
        // Verify MUID
        guard reply.destinationMUID == sourceMUID else {
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

        handleChunkResult(result, requestID: requestID)
    }

    /// Handle chunk processing result
    private func handleChunkResult(_ result: PEChunkResult, requestID: UInt8) {
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

    /// Log PE Reply parse failure for debugging
    private func logPEReplyParseFailure(_ data: [UInt8]) {
        guard data.count > 4 && data[4] == 0x35 else { return }

        let payloadStart = min(14, data.count - 1)
        let payloadPreview = data.count > payloadStart
            ? Array(data[payloadStart..<min(payloadStart + 20, data.count)])
            : []
        let hexPreview = payloadPreview.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug(
            "parseFullPEReply failed for 0x35: len=\(data.count), payload[14..]: \(hexPreview)",
            category: Self.logCategory
        )
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
        
        // Update destination cache on success (status 200-299)
        if response.isSuccess,
           let metadata = pendingRequestMetadata.removeValue(forKey: requestID) {
            Task {
                await destinationCache.recordSuccess(muid: metadata.muid, destination: metadata.destination)
                logger.debug(
                    "[PE-CACHE] Recorded success: MUID=\(metadata.muid) -> Dest=\(metadata.destination)",
                    category: Self.logCategory
                )
            }
        } else {
            // Remove metadata on failure too
            pendingRequestMetadata.removeValue(forKey: requestID)
        }
        
        logger.debug(
            "Complete [\(requestID)] status=\(status) body=\(body.count)B",
            category: Self.logCategory
        )
        
        continuation.resume(returning: response)
    }
    
    private func handleChunkTimeout(requestID: UInt8) {
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        pendingRequestMetadata.removeValue(forKey: requestID)

        clearSendTask(requestID: requestID)
        
        Task {
            await transactionManager.cancel(requestID: requestID)
        }
        
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: PEError.timeout(resource: "chunk assembly"))
        }
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
        // If there's only one pending GET/SET request, we can reasonably assume it's for that request.
        // Subscribe requests are handled by subscriptionHandler and will timeout if NAK'd.
        // Otherwise, we log the NAK for debugging purposes and let the request timeout.

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
        }
        // If multiple requests are pending or it's a subscribe request,
        // we can't determine which one the NAK is for. The request will eventually timeout.
    }
    
    // MARK: - Private: Notify Header Parsing

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

            // Subscription info from subscriptionHandler
            let pendingSubCount = await subscriptionHandler?.pendingSubscribeCount ?? 0
            let subs = await subscriptionHandler?.subscriptions ?? []
            lines.append("Pending subscribe requests: \(pendingSubCount)")
            lines.append("Active subscriptions: \(subs.count)")

            if !subs.isEmpty {
                for sub in subs {
                    lines.append("  - \(sub.resource) [\(sub.subscribeId)]")
                }
            }

            lines.append("")
            lines.append(await transactionManager.diagnostics)
            return lines.joined(separator: "\n")
        }
    }
}
