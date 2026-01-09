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
public actor SysExAssembler {
    
    /// Assembly buffer for incomplete SysEx
    private var buffer: [UInt8] = []
    
    /// SysEx start byte
    private static let sysExStart: UInt8 = 0xF0
    
    /// SysEx end byte
    private static let sysExEnd: UInt8 = 0xF7
    
    // MARK: - Initialization
    
    public init() {}
    
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
                    buffer = Array(remaining)
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
                    // Continue buffering
                    buffer.append(contentsOf: remaining)
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
}
