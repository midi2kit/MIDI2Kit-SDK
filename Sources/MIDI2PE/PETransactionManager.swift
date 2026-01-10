//
//  PETransactionManager.swift
//  MIDI2Kit
//
//  Manages PE transaction lifecycle to prevent Request ID leaks
//

import Foundation
import MIDI2Core

/// PE Transaction state
public struct PETransaction: Sendable, Identifiable {
    public let id: UInt8  // Request ID
    public let resource: String
    public let destinationMUID: MUID
    public let startTime: Date
    public let timeout: TimeInterval
    
    /// Check if transaction has timed out
    public func isTimedOut(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(startTime) > timeout
    }
}

/// Transaction completion result
public enum PETransactionResult: Sendable {
    case success(header: Data, body: Data)
    case error(status: Int, message: String?)
    case timeout
    case cancelled
}

/// Configuration for timeout monitoring
public struct PEMonitoringConfiguration: Sendable {
    /// Interval between timeout checks (seconds)
    public let checkInterval: TimeInterval
    
    /// If true, monitoring starts automatically on first `begin()` call
    ///
    /// When enabled, you don't need to manually call `startMonitoring()` or hold a handle.
    /// The manager keeps an internal strong reference to the monitoring task.
    ///
    /// Default: `false` (explicit `startMonitoring()` required)
    public let autoStart: Bool
    
    public init(checkInterval: TimeInterval = 1.0, autoStart: Bool = false) {
        self.checkInterval = checkInterval
        self.autoStart = autoStart
    }
    
    public static let `default` = PEMonitoringConfiguration()
    
    /// Configuration with auto-start enabled
    public static let autoStartEnabled = PEMonitoringConfiguration(autoStart: true)
}

/// Shared running state between Task and Handle
private final class MonitorRunningState: @unchecked Sendable {
    private let lock = NSLock()
    private var _isRunning: Bool = true
    
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }
    
    func markStopped() {
        lock.lock()
        defer { lock.unlock() }
        _isRunning = false
    }
}

/// Handle for timeout monitoring
///
/// The monitoring task runs while this handle is held.
/// When the handle is deallocated, monitoring stops automatically.
///
/// ## Usage
/// ```swift
/// class MyMIDIManager {
///     let transactionManager = PETransactionManager()
///     var monitorHandle: PEMonitorHandle?  // Hold this!
///
///     func start() {
///         monitorHandle = transactionManager.startMonitoring()
///     }
///
///     func stop() {
///         monitorHandle = nil  // Monitoring stops
///     }
/// }
/// ```
public final class PEMonitorHandle: Sendable {
    private let task: Task<Void, Never>
    private let stopCallback: @Sendable () async -> Void
    private let runningState: MonitorRunningState
    
    fileprivate init(task: Task<Void, Never>, runningState: MonitorRunningState, stopCallback: @escaping @Sendable () async -> Void) {
        self.task = task
        self.runningState = runningState
        self.stopCallback = stopCallback
    }
    
    deinit {
        task.cancel()
        runningState.markStopped()
        // Note: Can't await in deinit, but cancel() is enough
    }
    
    /// Explicitly stop monitoring
    public func stop() async {
        task.cancel()
        runningState.markStopped()
        await stopCallback()
    }
    
    /// Check if monitoring is still active
    public var isActive: Bool {
        runningState.isRunning && !task.isCancelled
    }
}

/// Manages PE transactions with automatic cleanup to prevent Request ID leaks
///
/// Key features:
/// - **Automatic timeout monitoring** via `startMonitoring()` returning a handle
/// - **Auto-start option** for convenience (no handle management needed)
/// - Guaranteed Request ID release on completion/error/timeout
/// - Transaction state monitoring
/// - Leak detection and warnings
///
/// ## Usage (Explicit Monitoring - Recommended)
/// ```swift
/// let manager = PETransactionManager()
///
/// // Start monitoring - HOLD the handle!
/// let handle = await manager.startMonitoring()
///
/// let requestID = await manager.begin(resource: "DeviceInfo", destinationMUID: device)
/// // ... use requestID ...
///
/// // When done, release handle or call stop()
/// await handle.stop()
/// ```
///
/// ## Usage (Auto-Start - Convenient but less control)
/// ```swift
/// let manager = PETransactionManager(
///     monitoringConfig: .autoStartEnabled
/// )
///
/// // No need to call startMonitoring() - starts automatically on first begin()
/// let requestID = await manager.begin(resource: "DeviceInfo", destinationMUID: device)
/// ```
public actor PETransactionManager {
    
    // MARK: - Configuration
    
    /// Default transaction timeout (seconds)
    public static let defaultTimeout: TimeInterval = 5.0
    
    /// Warning threshold for active transactions
    public static let warningThreshold: Int = 100
    
    /// Log category
    private static let logCategory = "PETransaction"
    
    // MARK: - State
    
    private var requestIDManager = PERequestIDManager()
    private var activeTransactions: [UInt8: PETransaction] = [:]
    private var chunkAssemblers: [UInt8: PEChunkAssembler] = [:]
    
    /// Logger instance
    private let logger: any MIDI2Logger
    
    /// Monitoring configuration
    private let monitoringConfig: PEMonitoringConfiguration
    
    /// Continuations waiting for transaction completion
    private var completionHandlers: [UInt8: CheckedContinuation<PETransactionResult, Never>] = [:]
    
    // MARK: - Monitoring State
    
    /// Weak reference to current monitor handle (for idempotency check)
    private weak var currentMonitorHandle: PEMonitorHandle?
    
    /// Strong reference for auto-started monitoring (keeps monitoring alive)
    private var autoStartedMonitorHandle: PEMonitorHandle?
    
    // MARK: - Public Properties
    
    /// Number of active transactions
    public var activeCount: Int {
        activeTransactions.count
    }
    
    /// Available Request IDs
    public var availableIDs: Int {
        requestIDManager.availableCount
    }
    
    /// Check if approaching ID exhaustion
    public var isNearExhaustion: Bool {
        availableIDs < 10
    }
    
    /// Whether monitoring is currently active
    public var isMonitoring: Bool {
        currentMonitorHandle?.isActive ?? false
    }
    
    // MARK: - Initialization
    
    /// Initialize with optional logger and monitoring configuration
    /// - Parameters:
    ///   - logger: Logger instance (default: NullMIDI2Logger - silent)
    ///   - monitoringConfig: Monitoring configuration (use `.autoStartEnabled` for auto-start)
    public init(
        logger: any MIDI2Logger = NullMIDI2Logger(),
        monitoringConfig: PEMonitoringConfiguration = .default
    ) {
        self.logger = logger
        self.monitoringConfig = monitoringConfig
    }
    
    // MARK: - Monitoring Control
    
    /// Start automatic timeout monitoring
    ///
    /// Returns a handle that controls the monitoring lifecycle.
    /// **You must hold this handle** - monitoring stops when the handle is deallocated.
    ///
    /// Safe to call multiple times - returns existing handle if already monitoring.
    ///
    /// - Returns: Monitor handle (hold this to keep monitoring active)
    @discardableResult
    public func startMonitoring() -> PEMonitorHandle {
        // Idempotent: return existing handle if still active
        if let existing = currentMonitorHandle, existing.isActive {
            logger.debug("Monitoring already active, returning existing handle", category: Self.logCategory)
            return existing
        }
        
        logger.info("Starting timeout monitoring (interval: \(monitoringConfig.checkInterval)s)", category: Self.logCategory)
        
        let interval = monitoringConfig.checkInterval
        
        // Shared state between Task and Handle
        let runningState = MonitorRunningState()
        
        // Create task with weak self to avoid retain cycle
        let task = Task { [weak self, runningState] in
            defer { runningState.markStopped() }  // Mark stopped when loop exits
            
            while !Task.isCancelled {
                // Check if self still exists
                guard let self = self else {
                    break
                }
                
                // Perform timeout check (actor-isolated)
                let timedOut = await self.checkTimeouts()
                
                if !timedOut.isEmpty {
                    self.logger.debug(
                        "Monitoring: cleaned up \(timedOut.count) timed-out transaction(s)",
                        category: Self.logCategory
                    )
                }
                
                // Sleep until next check
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
        
        let handle = PEMonitorHandle(task: task, runningState: runningState) { [weak self] in
            await self?.onMonitoringStopped()
        }
        
        currentMonitorHandle = handle
        return handle
    }
    
    /// Stop monitoring (for auto-started monitoring)
    ///
    /// If monitoring was auto-started, this stops it.
    /// If monitoring was started manually via `startMonitoring()`, 
    /// you should use the handle's `stop()` method instead.
    public func stopMonitoring() async {
        if let handle = autoStartedMonitorHandle {
            await handle.stop()
            autoStartedMonitorHandle = nil
        }
    }
    
    /// Called when monitoring stops (handle deallocated or stop() called)
    private func onMonitoringStopped() {
        logger.info("Timeout monitoring stopped", category: Self.logCategory)
        currentMonitorHandle = nil
        autoStartedMonitorHandle = nil
    }
    
    // MARK: - Transaction Lifecycle
    
    /// Begin a new PE transaction
    ///
    /// If `autoStart` is enabled in the monitoring configuration,
    /// this method will automatically start monitoring on the first call.
    ///
    /// - Parameters:
    ///   - resource: Resource being requested
    ///   - destinationMUID: Target device MUID
    ///   - timeout: Transaction timeout (default: 5s)
    /// - Returns: Request ID, or nil if exhausted
    public func begin(
        resource: String,
        destinationMUID: MUID,
        timeout: TimeInterval = defaultTimeout
    ) -> UInt8? {
        // Auto-start monitoring if configured and not already running
        if monitoringConfig.autoStart && !isMonitoring {
            logger.info("Auto-starting timeout monitoring", category: Self.logCategory)
            autoStartedMonitorHandle = startMonitoring()
        }
        
        // Check for exhaustion
        if isNearExhaustion {
            logger.warning(
                "Only \(availableIDs) Request IDs remaining",
                category: Self.logCategory
            )
        }
        
        // Acquire ID
        guard let requestID = requestIDManager.acquire() else {
            logger.error(
                "All 128 Request IDs in use!",
                category: Self.logCategory
            )
            return nil
        }
        
        // Create transaction
        let transaction = PETransaction(
            id: requestID,
            resource: resource,
            destinationMUID: destinationMUID,
            startTime: Date(),
            timeout: timeout
        )
        
        activeTransactions[requestID] = transaction
        chunkAssemblers[requestID] = PEChunkAssembler(timeout: timeout)
        
        // Warn if too many active
        if activeCount > Self.warningThreshold {
            logger.warning(
                "\(activeCount) active transactions (possible leak)",
                category: Self.logCategory
            )
        }
        
        logger.debug(
            "Begin transaction \(requestID): \(resource) -> \(destinationMUID)",
            category: Self.logCategory
        )
        
        return requestID
    }
    
    /// Complete a transaction successfully
    /// - Parameters:
    ///   - requestID: Request ID
    ///   - header: Response header
    ///   - body: Response body
    public func complete(requestID: UInt8, header: Data, body: Data) {
        guard let transaction = activeTransactions[requestID] else {
            logger.warning(
                "No transaction found for request ID \(requestID)",
                category: Self.logCategory
            )
            return
        }
        
        logger.debug(
            "Complete transaction \(requestID): \(transaction.resource) (\(body.count) bytes)",
            category: Self.logCategory
        )
        
        let result = PETransactionResult.success(header: header, body: body)
        finalizeTransaction(requestID: requestID, result: result)
    }
    
    /// Complete a transaction with error
    /// - Parameters:
    ///   - requestID: Request ID
    ///   - status: HTTP-style status code
    ///   - message: Error message
    public func completeWithError(requestID: UInt8, status: Int, message: String? = nil) {
        guard activeTransactions[requestID] != nil else {
            logger.warning(
                "No transaction found for request ID \(requestID)",
                category: Self.logCategory
            )
            return
        }
        
        logger.notice(
            "Transaction \(requestID) error: \(status) \(message ?? "")",
            category: Self.logCategory
        )
        
        let result = PETransactionResult.error(status: status, message: message)
        finalizeTransaction(requestID: requestID, result: result)
    }
    
    /// Cancel a transaction
    /// - Parameter requestID: Request ID
    public func cancel(requestID: UInt8) {
        guard activeTransactions[requestID] != nil else { return }
        
        logger.debug(
            "Cancel transaction \(requestID)",
            category: Self.logCategory
        )
        
        finalizeTransaction(requestID: requestID, result: .cancelled)
    }
    
    /// Cancel all transactions for a device (e.g., device disconnected)
    /// - Parameter muid: Device MUID
    public func cancelAll(for muid: MUID) {
        let toCancel = activeTransactions.values
            .filter { $0.destinationMUID == muid }
            .map { $0.id }
        
        if !toCancel.isEmpty {
            logger.notice(
                "Cancel \(toCancel.count) transactions for device \(muid)",
                category: Self.logCategory
            )
        }
        
        for requestID in toCancel {
            cancel(requestID: requestID)
        }
    }
    
    /// Cancel all transactions
    public func cancelAll() {
        let allIDs = Array(activeTransactions.keys)
        
        if !allIDs.isEmpty {
            logger.notice(
                "Cancel all \(allIDs.count) transactions",
                category: Self.logCategory
            )
        }
        
        for requestID in allIDs {
            cancel(requestID: requestID)
        }
    }
    
    // MARK: - Chunk Handling
    
    /// Process a received chunk
    /// - Parameters:
    ///   - requestID: Request ID
    ///   - thisChunk: Chunk number (1-based)
    ///   - numChunks: Total chunks
    ///   - headerData: Header data
    ///   - propertyData: Property data
    /// - Returns: Assembly result
    public func processChunk(
        requestID: UInt8,
        thisChunk: Int,
        numChunks: Int,
        headerData: Data,
        propertyData: Data
    ) -> PEChunkResult {
        guard var assembler = chunkAssemblers[requestID],
              let transaction = activeTransactions[requestID] else {
            // Distinct from timeout: transaction doesn't exist
            // Could be: late response, cancelled, misrouted, or ID collision
            logger.warning(
                "Chunk for unknown requestID \(requestID) (possible late/duplicate response)",
                category: Self.logCategory
            )
            return .unknownRequestID(requestID: requestID)
        }
        
        logger.debug(
            "Chunk \(thisChunk)/\(numChunks) for transaction \(requestID)",
            category: Self.logCategory
        )
        
        let result = assembler.addChunk(
            requestID: requestID,
            thisChunk: thisChunk,
            numChunks: numChunks,
            headerData: headerData,
            propertyData: propertyData,
            resource: transaction.resource
        )
        
        chunkAssemblers[requestID] = assembler
        
        // Auto-complete on chunk assembly complete
        if case .complete(let header, let body) = result {
            complete(requestID: requestID, header: header, body: body)
        }
        
        return result
    }
    
    // MARK: - Timeout Management
    
    /// Check and cleanup timed-out transactions
    ///
    /// This is called automatically when monitoring is active.
    /// You can also call it manually if needed.
    ///
    /// - Returns: Array of timed-out Request IDs
    @discardableResult
    public func checkTimeouts() -> [UInt8] {
        let now = Date()
        var timedOut: [UInt8] = []
        
        for (requestID, transaction) in activeTransactions {
            if transaction.isTimedOut(at: now) {
                timedOut.append(requestID)
            }
        }
        
        for requestID in timedOut {
            let resource = activeTransactions[requestID]?.resource ?? "?"
            logger.notice(
                "Transaction \(requestID) timed out (resource: \(resource))",
                category: Self.logCategory
            )
            finalizeTransaction(requestID: requestID, result: .timeout)
        }
        
        return timedOut
    }
    
    // MARK: - Async/Await Support
    
    /// Wait for transaction completion
    /// - Parameter requestID: Request ID
    /// - Returns: Transaction result
    public func waitForCompletion(requestID: UInt8) async -> PETransactionResult {
        guard activeTransactions[requestID] != nil else {
            return .cancelled
        }
        
        return await withCheckedContinuation { continuation in
            completionHandlers[requestID] = continuation
        }
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information
    public var diagnostics: String {
        var lines: [String] = []
        lines.append("=== PETransactionManager Diagnostics ===")
        lines.append("Monitoring: \(isMonitoring ? "active" : "stopped")")
        lines.append("Auto-start: \(monitoringConfig.autoStart ? "enabled" : "disabled")")
        lines.append("Active transactions: \(activeCount)")
        lines.append("Available IDs: \(availableIDs)")
        lines.append("Near exhaustion: \(isNearExhaustion)")
        
        if !activeTransactions.isEmpty {
            lines.append("Active:")
            for (id, tx) in activeTransactions.sorted(by: { $0.key < $1.key }) {
                let age = Date().timeIntervalSince(tx.startTime)
                lines.append("  [\(id)] \(tx.resource) -> \(tx.destinationMUID) (age: \(String(format: "%.1f", age))s)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Private
    
    private func finalizeTransaction(requestID: UInt8, result: PETransactionResult) {
        // Remove from tracking
        activeTransactions.removeValue(forKey: requestID)
        chunkAssemblers.removeValue(forKey: requestID)
        
        // Release Request ID (CRITICAL - prevents leak)
        requestIDManager.release(requestID)
        
        // Resume waiting continuation
        if let continuation = completionHandlers.removeValue(forKey: requestID) {
            continuation.resume(returning: result)
        }
    }
}
