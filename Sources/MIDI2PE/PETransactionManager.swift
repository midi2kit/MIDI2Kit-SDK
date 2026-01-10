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

// MARK: - PETransactionManager

/// Manages PE transaction lifecycle
///
/// This actor handles:
/// - **Request ID allocation/release** via PERequestIDManager
/// - **Chunk assembly** via PEChunkAssembler
/// - **Transaction state tracking** for diagnostics
///
/// It does NOT handle:
/// - Timeout scheduling (handled by PEManager)
/// - Continuation management (handled by PEManager)
/// - Response delivery (handled by PEManager)
///
/// ## Usage
///
/// ```swift
/// let manager = PETransactionManager()
///
/// // Begin transaction - allocates Request ID
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
    
    /// Warning threshold for active transactions (possible leak indicator)
    public static let warningThreshold: Int = 100
    
    /// Log category
    private static let logCategory = "PETransaction"
    
    // MARK: - Dependencies
    
    private let logger: any MIDI2Logger
    
    // MARK: - State
    
    /// Request ID manager
    private var requestIDManager = PERequestIDManager()
    
    /// Active transactions by Request ID
    private var activeTransactions: [UInt8: PETransaction] = [:]
    
    /// Chunk assemblers by Request ID
    private var chunkAssemblers: [UInt8: PEChunkAssembler] = [:]
    
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
    
    /// Initialize with optional logger
    /// - Parameter logger: Logger instance (default: NullMIDI2Logger - silent)
    public init(logger: any MIDI2Logger = NullMIDI2Logger()) {
        self.logger = logger
    }
    
    // MARK: - Transaction Lifecycle
    
    /// Begin a new PE transaction
    ///
    /// Allocates a Request ID and creates transaction tracking state.
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
    ) -> UInt8? {
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
        
        logger.debug(
            "Begin [\(requestID)] \(resource) -> \(destinationMUID)",
            category: Self.logCategory
        )
        
        return requestID
    }
    
    /// Cancel a transaction and release its Request ID
    ///
    /// Safe to call multiple times or with unknown Request ID.
    ///
    /// - Parameter requestID: Request ID to cancel
    public func cancel(requestID: UInt8) {
        guard activeTransactions.removeValue(forKey: requestID) != nil else {
            // Already cancelled or never existed - this is fine
            return
        }
        
        chunkAssemblers.removeValue(forKey: requestID)
        requestIDManager.release(requestID)
        
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
        let count = activeTransactions.count
        let allIDs = Array(activeTransactions.keys)
        
        for requestID in allIDs {
            cancel(requestID: requestID)
        }
        
        if count > 0 {
            logger.notice(
                "Cancelled all \(count) transactions",
                category: Self.logCategory
            )
        }
        
        return count
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
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information
    public var diagnostics: String {
        var lines: [String] = []
        lines.append("=== PETransactionManager ===")
        lines.append("Active transactions: \(activeCount)")
        lines.append("Available IDs: \(availableIDs)")
        
        if isNearExhaustion {
            lines.append("⚠️ Near ID exhaustion!")
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
