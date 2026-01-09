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

/// Manages PE transactions with automatic cleanup to prevent Request ID leaks
///
/// Key features:
/// - Automatic timeout-based cleanup
/// - Guaranteed Request ID release on completion/error/timeout
/// - Transaction state monitoring
/// - Leak detection and warnings
public actor PETransactionManager {
    
    // MARK: - Configuration
    
    /// Default transaction timeout (seconds)
    public static let defaultTimeout: TimeInterval = 5.0
    
    /// Warning threshold for active transactions
    public static let warningThreshold: Int = 100
    
    // MARK: - State
    
    private var requestIDManager = PERequestIDManager()
    private var activeTransactions: [UInt8: PETransaction] = .init()
    private var chunkAssemblers: [UInt8: PEChunkAssembler] = .init()
    
    /// Continuations waiting for transaction completion
    private var completionHandlers: [UInt8: CheckedContinuation<PETransactionResult, Never>] = .init()
    
    // MARK: - Monitoring
    
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
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Transaction Lifecycle
    
    /// Begin a new PE transaction
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
        // Check for exhaustion
        if isNearExhaustion {
            print("⚠️ [PETransactionManager] Warning: Only \(availableIDs) Request IDs remaining")
        }
        
        // Acquire ID
        guard let requestID = requestIDManager.acquire() else {
            print("❌ [PETransactionManager] All 128 Request IDs in use!")
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
            print("⚠️ [PETransactionManager] Warning: \(activeCount) active transactions (possible leak)")
        }
        
        return requestID
    }
    
    /// Complete a transaction successfully
    /// - Parameters:
    ///   - requestID: Request ID
    ///   - header: Response header
    ///   - body: Response body
    public func complete(requestID: UInt8, header: Data, body: Data) {
        guard activeTransactions[requestID] != nil else {
            print("⚠️ [PETransactionManager] No transaction found for request ID \(requestID)")
            return
        }
        
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
            print("⚠️ [PETransactionManager] No transaction found for request ID \(requestID)")
            return
        }
        
        let result = PETransactionResult.error(status: status, message: message)
        finalizeTransaction(requestID: requestID, result: result)
    }
    
    /// Cancel a transaction
    /// - Parameter requestID: Request ID
    public func cancel(requestID: UInt8) {
        guard activeTransactions[requestID] != nil else { return }
        finalizeTransaction(requestID: requestID, result: .cancelled)
    }
    
    /// Cancel all transactions for a device (e.g., device disconnected)
    /// - Parameter muid: Device MUID
    public func cancelAll(for muid: MUID) {
        let toCancel = activeTransactions.values
            .filter { $0.destinationMUID == muid }
            .map { $0.id }
        
        for requestID in toCancel {
            cancel(requestID: requestID)
        }
    }
    
    /// Cancel all transactions
    public func cancelAll() {
        let allIDs = Array(activeTransactions.keys)
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
            return .timeout(requestID: requestID, received: 0, total: numChunks, partial: nil)
        }
        
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
            print("⏱️ [PETransactionManager] Transaction \(requestID) timed out (resource: \(activeTransactions[requestID]?.resource ?? "?"))")
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
