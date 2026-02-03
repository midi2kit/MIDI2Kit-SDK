//
//  SysExAssembler.swift
//  MIDI2Kit
//
//  Assembles SysEx messages from MIDI packet fragments
//

import Foundation

/// Assembles complete SysEx messages from potentially fragmented MIDI packets
///
/// CoreMIDI may split SysEx messages across multiple packets.
/// This assembler buffers incomplete messages and emits complete ones.
///
/// Key features:
/// - Handles fragmented SysEx across packets
/// - Handles multiple SysEx messages in single packet
/// - Detects and discards corrupted/incomplete messages
/// - **Buffer size limit** to prevent memory exhaustion (DoS protection)
///
/// ## Security
///
/// The `maxBufferSize` parameter limits how much data can be buffered for
/// incomplete SysEx messages. This prevents malicious or buggy devices from
/// exhausting memory by sending endless SysEx data without termination.
public actor SysExAssembler {

    /// Default maximum buffer size (1 MB)
    ///
    /// MIDI-CI Property Exchange typically uses messages under 64KB.
    /// 1 MB provides ample headroom while preventing excessive memory use.
    public static let defaultMaxBufferSize: Int = 1_048_576

    /// Maximum allowed buffer size for incomplete SysEx
    public let maxBufferSize: Int

    /// Assembly buffer for incomplete SysEx
    private var buffer: [UInt8] = []

    /// Number of times buffer overflow occurred (for diagnostics)
    private var overflowCount: Int = 0

    /// SysEx start byte
    private static let sysExStart: UInt8 = 0xF0

    /// SysEx end byte
    private static let sysExEnd: UInt8 = 0xF7

    // MARK: - Initialization

    /// Initialize with optional buffer size limit
    /// - Parameter maxBufferSize: Maximum bytes to buffer (default: 1 MB)
    public init(maxBufferSize: Int = defaultMaxBufferSize) {
        self.maxBufferSize = max(1024, maxBufferSize) // Minimum 1KB
    }
    
    // MARK: - Assembly
    
    /// Process incoming MIDI packet data
    /// - Parameter data: Raw MIDI packet bytes
    /// - Returns: Array of complete SysEx messages
    public func process(_ data: [UInt8]) -> [[UInt8]] {
        guard !data.isEmpty else { return [] }
        
        var completedMessages: [[UInt8]] = []
        var remaining = ArraySlice(data)
        
        while !remaining.isEmpty {
            // Case 1: New SysEx starting
            if remaining.first == Self.sysExStart {
                // Discard incomplete buffer
                if !buffer.isEmpty {
                    buffer = []
                }
                
                // Find F7 end marker
                if let endIdx = remaining.firstIndex(of: Self.sysExEnd) {
                    // Complete message in this packet
                    let message = Array(remaining[remaining.startIndex...endIdx])
                    completedMessages.append(message)
                    
                    // Continue with remaining data
                    let nextIdx = remaining.index(after: endIdx)
                    if nextIdx < remaining.endIndex {
                        remaining = remaining[nextIdx...]
                        continue
                    } else {
                        break
                    }
                } else {
                    // No end marker - buffer for continuation
                    // Check buffer size limit to prevent DoS
                    if remaining.count <= maxBufferSize {
                        buffer = Array(remaining)
                    } else {
                        // Exceeds limit - discard and count overflow
                        overflowCount += 1
                    }
                    break
                }
            }
            // Case 2: Continuation of buffered SysEx
            else if !buffer.isEmpty {
                // Check for corruption (new F0 before F7)
                let endIdx = remaining.firstIndex(of: Self.sysExEnd)
                let startIdx = remaining.firstIndex(of: Self.sysExStart)
                
                if let f0Idx = startIdx {
                    if endIdx == nil || f0Idx < endIdx! {
                        // Corrupted - discard buffer and start fresh
                        buffer = []
                        remaining = remaining[f0Idx...]
                        continue
                    }
                }
                
                if let endIdx = endIdx {
                    // Complete the message
                    buffer.append(contentsOf: remaining[remaining.startIndex...endIdx])
                    completedMessages.append(buffer)
                    buffer = []
                    
                    // Continue with remaining data
                    let nextIdx = remaining.index(after: endIdx)
                    if nextIdx < remaining.endIndex {
                        remaining = remaining[nextIdx...]
                        continue
                    } else {
                        break
                    }
                } else {
                    // Continue buffering - check size limit
                    let newSize = buffer.count + remaining.count
                    if newSize <= maxBufferSize {
                        buffer.append(contentsOf: remaining)
                    } else {
                        // Would exceed limit - discard buffer and count overflow
                        buffer = []
                        overflowCount += 1
                    }
                    break
                }
            }
            // Case 3: Non-SysEx data without active buffer
            else {
                // Look for SysEx start
                if let startIdx = remaining.firstIndex(of: Self.sysExStart) {
                    remaining = remaining[startIdx...]
                    continue
                } else {
                    break
                }
            }
        }
        
        return completedMessages
    }
    
    /// Reset the assembler, discarding any incomplete data
    public func reset() {
        buffer = []
    }
    
    /// Check if there's an incomplete SysEx being buffered
    public var hasIncomplete: Bool {
        !buffer.isEmpty
    }
    
    /// Size of currently buffered incomplete data
    public var bufferSize: Int {
        buffer.count
    }

    /// Number of times buffer overflow protection was triggered
    ///
    /// This counter increments when incoming data would exceed `maxBufferSize`.
    /// A non-zero value may indicate:
    /// - Malicious device sending oversized SysEx
    /// - Buggy device not terminating SysEx properly
    /// - `maxBufferSize` set too low for legitimate use
    public var bufferOverflowCount: Int {
        overflowCount
    }

    /// Reset the overflow counter
    public func resetOverflowCount() {
        overflowCount = 0
    }
}
