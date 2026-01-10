//
//  PEChunkAssembler.swift
//  MIDI2Kit
//
//  Assembles multi-chunk Property Exchange responses
//

import Foundation

/// Result of chunk assembly operation
public enum PEChunkResult: Sendable {
    /// Waiting for more chunks
    case incomplete(received: Int, total: Int)
    
    /// All chunks received, assembly complete
    case complete(header: Data, body: Data)
    
    /// Timed out waiting for chunks
    case timeout(requestID: UInt8, received: Int, total: Int, partial: Data?)
    
    /// Request ID not found in active transactions
    ///
    /// This is distinct from timeout - indicates one of:
    /// - Duplicate/late response for already-completed transaction
    /// - Response for cancelled transaction
    /// - Misrouted message (ID collision)
    /// - Message received before transaction started
    case unknownRequestID(requestID: UInt8)
}

extension PEChunkResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .incomplete(let received, let total):
            return "incomplete(\(received)/\(total))"
        case .complete(let header, let body):
            return "complete(header: \(header.count)B, body: \(body.count)B)"
        case .timeout(let requestID, let received, let total, let partial):
            let partialInfo = partial.map { "\($0.count)B partial" } ?? "no partial"
            return "timeout(id: \(requestID), \(received)/\(total), \(partialInfo))"
        case .unknownRequestID(let requestID):
            return "unknownRequestID(\(requestID))"
        }
    }
}

/// Pending chunk assembly state
public struct PendingChunkState: Sendable {
    public let requestID: UInt8
    public let numChunks: Int
    public var chunks: [Int: Data]
    public let resource: String
    public let startTime: Date
    public var headerData: Data
    
    public var receivedCount: Int { chunks.count }
    public var isComplete: Bool { chunks.count == numChunks }
    
    public var missingChunks: [Int] {
        (1...numChunks).filter { !chunks.keys.contains($0) }
    }
}

/// Assembles multi-chunk Property Exchange responses
///
/// PE responses can be split across multiple SysEx messages.
/// This assembler collects chunks and reassembles the complete response.
///
/// Key features:
/// - Preserves headerData from first non-empty chunk (some devices only send header in chunk 1)
/// - Tracks timeout per request
/// - Thread-safe via Sendable conformance
public struct PEChunkAssembler: Sendable {
    
    /// Default timeout for chunk assembly (seconds)
    public static let defaultTimeout: TimeInterval = 3.0
    
    /// Timeout duration
    public let timeout: TimeInterval
    
    /// Pending chunk assemblies by requestID
    private var pending: [UInt8: PendingChunkState]
    
    // MARK: - Initialization
    
    public init(timeout: TimeInterval = PEChunkAssembler.defaultTimeout) {
        self.timeout = timeout
        self.pending = [:]
    }
    
    // MARK: - Chunk Processing
    
    /// Add a received chunk
    /// - Parameters:
    ///   - requestID: Request ID (7-bit, 0-127)
    ///   - thisChunk: Chunk number (1-based)
    ///   - numChunks: Total number of chunks
    ///   - headerData: Header data from this chunk
    ///   - propertyData: Property data from this chunk
    ///   - resource: Resource name (for new assemblies)
    /// - Returns: Result indicating completion status
    public mutating func addChunk(
        requestID: UInt8,
        thisChunk: Int,
        numChunks: Int,
        headerData: Data,
        propertyData: Data,
        resource: String = ""
    ) -> PEChunkResult {
        // Single-chunk response - return immediately
        if numChunks == 1 {
            return .complete(header: headerData, body: propertyData)
        }
        
        // Initialize or get existing state
        if pending[requestID] == nil {
            pending[requestID] = PendingChunkState(
                requestID: requestID,
                numChunks: numChunks,
                chunks: [:],
                resource: resource,
                startTime: Date(),
                headerData: Data()
            )
        }
        
        // Capture header from first non-empty chunk
        if !headerData.isEmpty && pending[requestID]?.headerData.isEmpty == true {
            pending[requestID]?.headerData = headerData
        }
        
        // Store chunk
        pending[requestID]?.chunks[thisChunk] = propertyData
        
        // Check completion
        guard let state = pending[requestID] else {
            return .incomplete(received: 0, total: numChunks)
        }
        
        if state.isComplete {
            // Assemble complete response
            let assembled = assembleChunks(state)
            pending.removeValue(forKey: requestID)
            return .complete(header: state.headerData, body: assembled)
        }
        
        return .incomplete(received: state.receivedCount, total: numChunks)
    }
    
    /// Check for timed-out assemblies
    /// - Returns: Array of timed-out results
    public mutating func checkTimeouts() -> [PEChunkResult] {
        let now = Date()
        var timedOut: [PEChunkResult] = []
        var toRemove: [UInt8] = []
        
        for (requestID, state) in pending {
            if now.timeIntervalSince(state.startTime) > timeout {
                let partial = state.chunks[1] != nil ? assembleChunks(state) : nil
                timedOut.append(.timeout(
                    requestID: requestID,
                    received: state.receivedCount,
                    total: state.numChunks,
                    partial: partial
                ))
                toRemove.append(requestID)
            }
        }
        
        for requestID in toRemove {
            pending.removeValue(forKey: requestID)
        }
        
        return timedOut
    }
    
    /// Cancel a pending assembly
    public mutating func cancel(requestID: UInt8) {
        pending.removeValue(forKey: requestID)
    }
    
    /// Cancel all pending assemblies
    public mutating func cancelAll() {
        pending.removeAll()
    }
    
    /// Check if there are any pending assemblies
    public var hasPending: Bool {
        !pending.isEmpty
    }
    
    /// Number of pending assemblies
    public var pendingCount: Int {
        pending.count
    }
    
    // MARK: - Private
    
    private func assembleChunks(_ state: PendingChunkState) -> Data {
        var assembled = Data()
        for i in 1...state.numChunks {
            if let chunk = state.chunks[i] {
                assembled.append(chunk)
            }
        }
        return assembled
    }
}
