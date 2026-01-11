//
//  PETransactionManager.swift
//  MIDI2Kit
//
//  Manages PE transaction lifecycle: Request ID allocation, chunk assembly, and transaction tracking.
//
//  ## Responsibility Separation
//
//  - **PETransactionManager**: Request ID lifecycle, chunk assembly, transaction state tracking
//  - **PEManager**: Timeout management, continuation handling, response delivery
//
//  This separation ensures:
//  1. Single source of truth for Request ID allocation/release
//  2. Single source of truth for timeout-to-continuation mapping
//  3. No duplicate monitoring or completion handling logic
//

import Foundation
import MIDI2Core

// MARK: - PE Transaction

/// PE Transaction state
///
/// Tracks an in-flight Property Exchange request.
public struct PETransaction: Sendable, Identifiable {
    /// Request ID (0-127)
    public let id: UInt8
    
    /// Resource being requested
    public let resource: String
    
    /// Target device MUID
    public let destinationMUID: MUID
    
    /// When the transaction started
    public let startTime: Date
    
    /// Transaction timeout (for diagnostics only - actual timeout enforced by PEManager)
    public let timeout: TimeInterval
    
    /// Calculate elapsed time
    public func elapsed(at now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(startTime)
    }
}

// MARK: - Device Inflight State

/// Per-device in-flight request tracking
private struct DeviceInflightState {
    /// Current number of in-flight requests to this device
    var currentInflight: Int = 0
    
    /// Waiters queued when inflight limit is reached
    var waiters: [CheckedContinuation<Void, Never>] = []
}

// MARK: - PETransactionManager

/// Manages PE transaction lifecycle
///
/// This actor handles:
/// - **Request ID allocation/release** via PERequestIDManager
/// - **Chunk assembly** via PEChunkAssembler
/// - **Transaction state tracking** for diagnostics
/// - **Per-device inflight limiting** to prevent overwhelming slow devices
///
/// It does NOT handle:
/// - Timeout scheduling (handled by PEManager)
/// - Continuation management (handled by PEManager)
/// - Response delivery (handled by PEManager)
///
/// ## Per-Device Inflight Limiting
///
/// Some MIDI devices cannot handle many concurrent requests. The `maxInflightPerDevice`
/// parameter limits how many requests can be in-flight to any single device at once.
/// Excess requests wait in a FIFO queue until earlier requests complete.
///
/// ## Usage
///
/// ```swift
/// let manager = PETransactionManager(maxInflightPerDevice: 2)
///
/// // Begin transaction - allocates Request ID (may wait if device is busy)
/// guard let requestID = await manager.begin(
///     resource: "DeviceInfo",
///     destinationMUID: device,
///     timeout: 5.0
/// ) else {
///     throw PEError.requestIDExhausted
/// }
///
/// // Process incoming chunks
/// let result = await manager.processChunk(
///     requestID: requestID,
///     thisChunk: 1,
///     numChunks: 3,
///     headerData: headerData,
///     propertyData: propertyData
/// )
///
/// // On completion/error/timeout, cancel to release Request ID
/// await manager.cancel(requestID: requestID)
/// ```
public actor PETransactionManager {
    
    // MARK: - Configuration
    
    /// Maximum concurrent in-flight requests per device
    ///
    /// Setting this to a low value (1-4) improves stability with devices
    /// that have weak MIDI-CI implementations.
    public nonisolated let maxInflightPerDevice: Int
    
    /// Warning threshold for active transactions (possible leak indicator)
    public static let warningThreshold: Int = 100
    
    /// Log category
    private static let logCategory = "PETransaction"
    
    // MARK: - Dependencies
    
    private let logger: any MIDI2Logger
    
    // MARK: - State
    
    /// Flag indicating manager has been stopped (cancelAll was called)
    /// When true, begin() returns nil immediately to prevent new transactions
    private var isStopped = false
    
    /// Generation counter to detect stale waiters after cancelAll()
    /// Incremented on each cancelAll() call. Waiters check if generation changed
    /// while they were waiting to detect if they should abort.
    private var generation: UInt64 = 0
    
    /// Request ID manager
    private var requestIDManager = PERequestIDManager()
    
    /// Active transactions by Request ID
    private var activeTransactions: [UInt8: PETransaction] = [:]
    
    /// Chunk assemblers by Request ID
    private var chunkAssemblers: [UInt8: PEChunkAssembler] = [:]
    
    /// Per-device inflight state
    private var deviceInflightState: [MUID: DeviceInflightState] = [:]
    
    // MARK: - Public Properties
    
    /// Number of active transactions
    public var activeCount: Int {
        activeTransactions.count
    }
    
    /// Number of available Request IDs
    public var availableIDs: Int {
        requestIDManager.availableCount
    }
    
    /// Check if approaching ID exhaustion (< 10 available)
    public var isNearExhaustion: Bool {
        availableIDs < 10
    }
    
    // MARK: - Initialization
    
    /// Initialize with optional logger and inflight limit
    /// - Parameters:
    ///   - maxInflightPerDevice: Maximum concurrent requests per device (default: 2)
    ///   - logger: Logger instance (default: NullMIDI2Logger - silent)
    public init(
        maxInflightPerDevice: Int = 2,
        logger: any MIDI2Logger = NullMIDI2Logger()
    ) {
        self.maxInflightPerDevice = max(1, maxInflightPerDevice)
        self.logger = logger
    }
    
    // MARK: - Transaction Lifecycle
    
    /// Begin a new PE transaction
    ///
    /// Allocates a Request ID and creates transaction tracking state.
    /// If the device already has `maxInflightPerDevice` requests in flight,
    /// this method will suspend until a slot becomes available.
    ///
    /// - Parameters:
    ///   - resource: Resource being requested
    ///   - destinationMUID: Target device MUID
    ///   - timeout: Transaction timeout (for chunk assembler inter-chunk timeout)
    /// - Returns: Allocated Request ID, or nil if all 128 IDs are in use
    public func begin(
        resource: String,
        destinationMUID: MUID,
        timeout: TimeInterval = 5.0
    ) async -> UInt8? {
        // Record current generation before waiting
        let startGeneration = generation
        
        // Wait for device slot if at capacity
        await waitForDeviceSlot(destinationMUID)
        
        // Check if manager was stopped while waiting (either by flag or generation change)
        if isStopped || generation != startGeneration {
            // Don't release slot - cancelAll() will clear deviceInflightState
            return nil
        }
        
        // Warn if near exhaustion
        if isNearExhaustion {
            logger.warning(
                "Request ID near exhaustion: only \(availableIDs) remaining",
                category: Self.logCategory
            )
        }
        
        // Acquire Request ID
        guard let requestID = requestIDManager.acquire() else {
            logger.error(
                "Request ID exhausted: all 128 IDs in use",
                category: Self.logCategory
            )
            // Release the device slot we just acquired
            releaseDeviceSlot(destinationMUID)
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
        
        // Warn if too many active (possible leak)
        if activeCount > Self.warningThreshold {
            logger.warning(
                "High transaction count: \(activeCount) active (possible leak)",
                category: Self.logCategory
            )
        }
        
        let currentInflight = deviceInflightState[destinationMUID]?.currentInflight ?? 0
        logger.debug(
            "Begin [\(requestID)] \(resource) -> \(destinationMUID) (inflight: \(currentInflight)/\(maxInflightPerDevice))",
            category: Self.logCategory
        )
        
        return requestID
    }
    
    /// Wait for a device slot to become available
    private func waitForDeviceSlot(_ muid: MUID) async {
        var state = deviceInflightState[muid] ?? DeviceInflightState()
        
        // If under limit, increment and proceed
        if state.currentInflight < maxInflightPerDevice {
            state.currentInflight += 1
            deviceInflightState[muid] = state
            return
        }
        
        // At capacity - wait in queue
        logger.debug(
            "Device \(muid) at capacity (\(state.currentInflight)/\(maxInflightPerDevice)), queueing...",
            category: Self.logCategory
        )
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var state = deviceInflightState[muid] ?? DeviceInflightState()
            state.waiters.append(continuation)
            deviceInflightState[muid] = state
        }
        
        // When we're resumed, our slot is already accounted for
    }
    
    /// Release a device slot and resume next waiter if any
    private func releaseDeviceSlot(_ muid: MUID) {
        guard var state = deviceInflightState[muid] else { return }
        
        if !state.waiters.isEmpty {
            // Resume next waiter (they take our slot)
            let next = state.waiters.removeFirst()
            deviceInflightState[muid] = state
            next.resume()
        } else {
            // No waiters - decrement count
            state.currentInflight = max(0, state.currentInflight - 1)
            if state.currentInflight == 0 {
                deviceInflightState.removeValue(forKey: muid)
            } else {
                deviceInflightState[muid] = state
            }
        }
    }
    
    /// Cancel a transaction and release its Request ID
    ///
    /// Safe to call multiple times or with unknown Request ID.
    ///
    /// - Parameter requestID: Request ID to cancel
    public func cancel(requestID: UInt8) {
        guard let transaction = activeTransactions.removeValue(forKey: requestID) else {
            // Already cancelled or never existed - this is fine
            return
        }
        
        chunkAssemblers.removeValue(forKey: requestID)
        requestIDManager.release(requestID)
        
        // Release device slot
        releaseDeviceSlot(transaction.destinationMUID)
        
        logger.debug(
            "Cancel [\(requestID)]",
            category: Self.logCategory
        )
    }
    
    /// Cancel all transactions for a specific device
    ///
    /// Useful when a device disconnects.
    ///
    /// - Parameter muid: Device MUID
    /// - Returns: Number of cancelled transactions
    @discardableResult
    public func cancelAll(for muid: MUID) -> Int {
        let toCancel = activeTransactions.values
            .filter { $0.destinationMUID == muid }
            .map { $0.id }
        
        for requestID in toCancel {
            cancel(requestID: requestID)
        }
        
        // Also cancel any waiters for this device
        if var state = deviceInflightState[muid] {
            for waiter in state.waiters {
                waiter.resume()  // Resume them so they can fail gracefully
            }
            state.waiters.removeAll()
            state.currentInflight = 0
            deviceInflightState.removeValue(forKey: muid)
        }
        
        if !toCancel.isEmpty {
            logger.notice(
                "Cancelled \(toCancel.count) transactions for device \(muid)",
                category: Self.logCategory
            )
        }
        
        return toCancel.count
    }
    
    /// Cancel all active transactions
    ///
    /// Useful when stopping the manager.
    ///
    /// - Returns: Number of cancelled transactions
    @discardableResult
    public func cancelAll() -> Int {
        // Set flag before resuming waiters to prevent them from starting new transactions
        isStopped = true
        
        // Increment generation to invalidate any waiters that resume after reset()
        generation &+= 1
        
        let count = activeTransactions.count
        let allIDs = Array(activeTransactions.keys)
        
        for requestID in allIDs {
            cancel(requestID: requestID)
        }
        
        // Resume all waiters
        for (_, state) in deviceInflightState {
            for waiter in state.waiters {
                waiter.resume()
            }
        }
        deviceInflightState.removeAll()
        
        if count > 0 {
            logger.notice(
                "Cancelled all \(count) transactions",
                category: Self.logCategory
            )
        }
        
        return count
    }
    
    /// Reset the stopped state
    ///
    /// Call this when starting to receive again after a stop.
    public func reset() {
        isStopped = false
    }
    
    // MARK: - Chunk Processing
    
    /// Process a received chunk
    ///
    /// Assembles multi-chunk responses. Returns `.complete` when all chunks are received.
    ///
    /// - Parameters:
    ///   - requestID: Request ID from the response
    ///   - thisChunk: Current chunk number (1-based)
    ///   - numChunks: Total number of chunks
    ///   - headerData: Header data from this chunk
    ///   - propertyData: Property data from this chunk
    /// - Returns: Assembly result
    public func processChunk(
        requestID: UInt8,
        thisChunk: Int,
        numChunks: Int,
        headerData: Data,
        propertyData: Data
    ) -> PEChunkResult {
        // Check if transaction exists
        guard var assembler = chunkAssemblers[requestID],
              let transaction = activeTransactions[requestID] else {
            logger.debug(
                "Chunk for unknown [\(requestID)] (late/cancelled response)",
                category: Self.logCategory
            )
            return .unknownRequestID(requestID: requestID)
        }
        
        logger.debug(
            "Chunk [\(requestID)] \(thisChunk)/\(numChunks)",
            category: Self.logCategory
        )
        
        // Process chunk through assembler
        let result = assembler.addChunk(
            requestID: requestID,
            thisChunk: thisChunk,
            numChunks: numChunks,
            headerData: headerData,
            propertyData: propertyData,
            resource: transaction.resource
        )
        
        // Update assembler state
        chunkAssemblers[requestID] = assembler
        
        // On complete, clean up transaction state
        // Note: Request ID release is handled by caller (PEManager) after processing the response
        if case .complete = result {
            logger.debug(
                "Complete [\(requestID)] \(transaction.resource)",
                category: Self.logCategory
            )
        }
        
        return result
    }
    
    // MARK: - Query
    
    /// Get transaction info for a Request ID
    /// - Parameter requestID: Request ID
    /// - Returns: Transaction info if exists
    public func transaction(for requestID: UInt8) -> PETransaction? {
        activeTransactions[requestID]
    }
    
    /// Check if a Request ID has an active transaction
    /// - Parameter requestID: Request ID
    /// - Returns: true if transaction exists
    public func hasTransaction(for requestID: UInt8) -> Bool {
        activeTransactions[requestID] != nil
    }
    
    /// Get current inflight count for a device
    /// - Parameter muid: Device MUID
    /// - Returns: Number of in-flight requests
    public func inflightCount(for muid: MUID) -> Int {
        deviceInflightState[muid]?.currentInflight ?? 0
    }
    
    /// Get number of waiters for a device
    /// - Parameter muid: Device MUID
    /// - Returns: Number of queued requests waiting
    public func waiterCount(for muid: MUID) -> Int {
        deviceInflightState[muid]?.waiters.count ?? 0
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information
    public var diagnostics: String {
        var lines: [String] = []
        lines.append("=== PETransactionManager ===")
        lines.append("Max inflight per device: \(maxInflightPerDevice)")
        lines.append("Active transactions: \(activeCount)")
        lines.append("Available IDs: \(availableIDs)")
        
        if isNearExhaustion {
            lines.append("⚠️ Near ID exhaustion!")
        }
        
        if !deviceInflightState.isEmpty {
            lines.append("Device states:")
            for (muid, state) in deviceInflightState {
                lines.append("  \(muid): inflight=\(state.currentInflight), waiting=\(state.waiters.count)")
            }
        }
        
        if !activeTransactions.isEmpty {
            lines.append("Transactions:")
            for (id, tx) in activeTransactions.sorted(by: { $0.key < $1.key }) {
                let elapsed = tx.elapsed()
                lines.append("  [\(id)] \(tx.resource) -> \(tx.destinationMUID) (\(String(format: "%.1f", elapsed))s)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}
