//
//  PEManager.swift
//  MIDI2Kit
//
//  High-level Property Exchange API
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
}

// MARK: - PE Notification

/// Property Exchange subscription notification
public struct PENotification: Sendable {
    /// Resource that changed
    public let resource: String
    
    /// Change header
    public let header: PEHeader?
    
    /// Change data
    public let data: Data
    
    /// Source device MUID
    public let sourceMUID: MUID
}

// MARK: - PEManager

/// High-level Property Exchange manager
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
    
    // MARK: - State
    
    /// Receiving task
    private var receiveTask: Task<Void, Never>?
    
    /// Monitor handle for transaction timeouts
    private var monitorHandle: PEMonitorHandle?
    
    /// Pending transactions waiting for response
    private var pendingContinuations: [UInt8: CheckedContinuation<PEResponse, Error>] = [:]
    
    /// Timeout tasks for pending requests
    private var timeoutTasks: [UInt8: Task<Void, Never>] = [:]
    
    /// Subscription streams
    private var subscriptions: [String: AsyncStream<PENotification>.Continuation] = [:]
    
    // MARK: - Initialization
    
    /// Initialize PEManager
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
        
        // Start transaction timeout monitoring
        monitorHandle = await transactionManager.startMonitoring()
        
        // Start receive loop
        receiveTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await received in transport.received {
                await self.handleReceived(received.data)
            }
        }
        
        logger.info("PEManager started", category: Self.logCategory)
    }
    
    /// Stop receiving
    public func stopReceiving() async {
        receiveTask?.cancel()
        receiveTask = nil
        
        await monitorHandle?.stop()
        monitorHandle = nil
        
        // Cancel all timeout tasks
        for (_, task) in timeoutTasks {
            task.cancel()
        }
        timeoutTasks.removeAll()
        
        // Cancel all pending transactions
        for (requestID, continuation) in pendingContinuations {
            continuation.resume(throwing: PEError.cancelled)
            pendingContinuations.removeValue(forKey: requestID)
        }
        
        logger.info("PEManager stopped", category: Self.logCategory)
    }
    
    // MARK: - GET
    
    /// Get a resource from a device
    public func get(
        resource: String,
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        logger.debug("GET \(resource) from \(device)", category: Self.logCategory)
        
        // Begin transaction
        guard let requestID = await transactionManager.begin(
            resource: resource,
            destinationMUID: device,
            timeout: timeout.timeInterval
        ) else {
            throw PEError.requestIDExhausted
        }
        
        // Build message
        let headerData = CIMessageBuilder.resourceRequestHeader(resource: resource)
        let message = CIMessageBuilder.peGetInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: device,
            requestID: requestID,
            headerData: headerData
        )
        
        return try await performRequest(
            requestID: requestID,
            resource: resource,
            message: message,
            destination: destination,
            timeout: timeout
        )
    }
    
    /// Get a channel-specific resource
    public func get(
        resource: String,
        channel: Int,
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        logger.debug("GET \(resource) channel=\(channel) from \(device)", category: Self.logCategory)
        
        guard let requestID = await transactionManager.begin(
            resource: resource,
            destinationMUID: device,
            timeout: timeout.timeInterval
        ) else {
            throw PEError.requestIDExhausted
        }
        
        let headerData = CIMessageBuilder.channelResourceHeader(resource: resource, channel: channel)
        let message = CIMessageBuilder.peGetInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: device,
            requestID: requestID,
            headerData: headerData
        )
        
        return try await performRequest(
            requestID: requestID,
            resource: resource,
            message: message,
            destination: destination,
            timeout: timeout
        )
    }
    
    /// Get a paginated resource
    public func get(
        resource: String,
        offset: Int,
        limit: Int,
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        logger.debug("GET \(resource) offset=\(offset) limit=\(limit) from \(device)", category: Self.logCategory)
        
        guard let requestID = await transactionManager.begin(
            resource: resource,
            destinationMUID: device,
            timeout: timeout.timeInterval
        ) else {
            throw PEError.requestIDExhausted
        }
        
        let headerData = CIMessageBuilder.paginatedRequestHeader(
            resource: resource,
            offset: offset,
            limit: limit
        )
        let message = CIMessageBuilder.peGetInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: device,
            requestID: requestID,
            headerData: headerData
        )
        
        return try await performRequest(
            requestID: requestID,
            resource: resource,
            message: message,
            destination: destination,
            timeout: timeout
        )
    }
    
    // MARK: - SET
    
    /// Set a resource value
    public func set(
        resource: String,
        data: Data,
        to device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        logger.debug("SET \(resource) to \(device) (\(data.count) bytes)", category: Self.logCategory)
        
        guard let requestID = await transactionManager.begin(
            resource: resource,
            destinationMUID: device,
            timeout: timeout.timeInterval
        ) else {
            throw PEError.requestIDExhausted
        }
        
        let headerData = CIMessageBuilder.resourceRequestHeader(resource: resource)
        let encodedData = Mcoded7.encode(data)
        
        let message = CIMessageBuilder.peSetInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: device,
            requestID: requestID,
            headerData: headerData,
            propertyData: encodedData
        )
        
        return try await performRequest(
            requestID: requestID,
            resource: resource,
            message: message,
            destination: destination,
            timeout: timeout
        )
    }
    
    // MARK: - Private: Request Execution
    
    /// Perform a PE request with timeout
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
                await self?.handleTimeoutFired(requestID: requestID, resource: resource)
            } catch {
                // Task was cancelled - normal completion path
            }
        }
        timeoutTasks[requestID] = timeoutTask
        
        // Wait for response via continuation
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations[requestID] = continuation
            
            // Send message
            Task { [weak self] in
                do {
                    try await self?.transport.send(message, to: destination)
                } catch {
                    await self?.handleSendError(requestID: requestID, error: error)
                }
            }
        }
    }
    
    /// Handle timeout firing
    private func handleTimeoutFired(requestID: UInt8, resource: String) {
        // Cancel and remove timeout task
        timeoutTasks.removeValue(forKey: requestID)
        
        // Resume continuation with timeout error
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
            logger.notice("Timeout: requestID=\(requestID) resource=\(resource)", category: Self.logCategory)
            continuation.resume(throwing: PEError.timeout(resource: resource))
        }
        
        // Cancel transaction in manager
        Task {
            await transactionManager.cancel(requestID: requestID)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Get DeviceInfo from a device
    public func getDeviceInfo(
        from device: MUID,
        via destination: MIDIDestinationID
    ) async throws -> PEDeviceInfo {
        let response = try await get(resource: "DeviceInfo", from: device, via: destination)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(PEDeviceInfo.self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode DeviceInfo: \(error)")
        }
    }
    
    /// Get ResourceList from a device
    public func getResourceList(
        from device: MUID,
        via destination: MIDIDestinationID
    ) async throws -> [PEResourceEntry] {
        let response = try await get(resource: "ResourceList", from: device, via: destination)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([PEResourceEntry].self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode ResourceList: \(error)")
        }
    }
    
    // MARK: - Private: Receive Handling
    
    private func handleReceived(_ data: [UInt8]) async {
        // Parse as PE Reply
        guard let reply = CIMessageParser.parseFullPEReply(data) else {
            return
        }
        
        // Check if this is addressed to us
        guard reply.destinationMUID == sourceMUID else {
            return
        }
        
        let requestID = reply.requestID
        
        logger.debug(
            "Received PE Reply: requestID=\(requestID) chunk \(reply.thisChunk)/\(reply.numChunks)",
            category: Self.logCategory
        )
        
        // Process chunk
        let result = await transactionManager.processChunk(
            requestID: requestID,
            thisChunk: reply.thisChunk,
            numChunks: reply.numChunks,
            headerData: reply.headerData,
            propertyData: reply.propertyData
        )
        
        // Handle result
        switch result {
        case .complete(let header, let body):
            handleComplete(requestID: requestID, header: header, body: body)
            
        case .incomplete:
            // Still waiting for more chunks
            break
            
        case .timeout(let id, _, _, _):
            handleTimeout(requestID: id)
            
        case .unknownRequestID(let id):
            // Request ID not found - late/duplicate response, already completed or cancelled
            logger.debug(
                "Ignoring reply for unknown requestID \(id) (late/duplicate response)",
                category: Self.logCategory
            )
        }
    }
    
    private func handleComplete(requestID: UInt8, header: Data, body: Data) {
        // Cancel timeout task
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        guard let continuation = pendingContinuations.removeValue(forKey: requestID) else {
            logger.warning("No continuation for completed request \(requestID)", category: Self.logCategory)
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
            "Complete: requestID=\(requestID) status=\(status) body=\(body.count) bytes",
            category: Self.logCategory
        )
        
        continuation.resume(returning: response)
    }
    
    private func handleTimeout(requestID: UInt8) {
        // Cancel timeout task
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        guard let continuation = pendingContinuations.removeValue(forKey: requestID) else {
            return
        }
        
        logger.notice("Timeout: requestID=\(requestID)", category: Self.logCategory)
        continuation.resume(throwing: PEError.timeout(resource: "unknown"))
    }
    
    private func handleSendError(requestID: UInt8, error: Error) async {
        // Cancel timeout task
        timeoutTasks[requestID]?.cancel()
        timeoutTasks.removeValue(forKey: requestID)
        
        // Cancel transaction
        await transactionManager.cancel(requestID: requestID)
        
        // Resume continuation with error
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: PEError.transportError(error))
        }
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information
    public var diagnostics: String {
        get async {
            var lines: [String] = []
            lines.append("=== PEManager Diagnostics ===")
            lines.append("Source MUID: \(sourceMUID)")
            lines.append("Receiving: \(receiveTask != nil)")
            lines.append("Pending requests: \(pendingContinuations.count)")
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
