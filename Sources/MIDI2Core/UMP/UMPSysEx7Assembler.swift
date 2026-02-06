//
//  UMPSysEx7Assembler.swift
//  MIDI2Kit
//
//  Reassembles multi-packet UMP Data 64 (SysEx7) into complete MIDI 1.0 SysEx messages
//

import Foundation

/// Reassembles multi-packet UMP Data 64 (SysEx7) messages into complete MIDI 1.0 SysEx
///
/// UMP SysEx7 messages longer than 6 bytes are split across multiple Data 64 packets
/// using Start/Continue/End status codes. This actor collects the fragments per UMP group
/// and returns a complete `[F0, data..., F7]` message when the End packet arrives.
///
/// ## Usage
///
/// ```swift
/// let assembler = UMPSysEx7Assembler()
///
/// for packet in incomingPackets {
///     if case .data64(let group, let status, let bytes) = UMPParser.parse(packet) {
///         if let complete = await assembler.process(group: group, status: status, bytes: bytes) {
///             // complete is [F0, data..., F7]
///             handleSysEx(complete)
///         }
///     }
/// }
/// ```
public actor UMPSysEx7Assembler {

    /// Maximum buffer size per group (default: 65536 bytes)
    public let maxBufferSize: Int

    /// Per-group accumulation buffers
    private var buffers: [UInt8: [UInt8]] = [:]

    /// Initialize with optional maximum buffer size
    ///
    /// - Parameter maxBufferSize: Maximum accumulated bytes per group before overflow (default: 65536)
    public init(maxBufferSize: Int = 65536) {
        self.maxBufferSize = maxBufferSize
    }

    /// Process an incoming Data 64 (SysEx7) packet
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - status: SysEx7 status raw value (0=Complete, 1=Start, 2=Continue, 3=End)
    ///   - bytes: Data bytes from the packet (already trimmed by numBytes)
    /// - Returns: Complete MIDI 1.0 SysEx `[F0, data..., F7]` when a message is complete, nil otherwise
    public func process(group: UInt8, status: UInt8, bytes: [UInt8]) -> [UInt8]? {
        guard let sysExStatus = SysEx7Status(rawValue: status) else {
            return nil
        }

        switch sysExStatus {
        case .complete:
            // Single-packet message
            var result: [UInt8] = [0xF0]
            result.append(contentsOf: bytes)
            result.append(0xF7)
            return result

        case .start:
            // Begin new accumulation (discard any previous incomplete)
            buffers[group] = Array(bytes)
            return nil

        case .continue:
            // Append to existing buffer
            guard buffers[group] != nil else {
                // Continue without Start — discard
                return nil
            }
            let newSize = buffers[group]!.count + bytes.count
            guard newSize <= maxBufferSize else {
                // Buffer overflow — discard
                buffers[group] = nil
                return nil
            }
            buffers[group]!.append(contentsOf: bytes)
            return nil

        case .end:
            // Finalize the message
            guard var accumulated = buffers[group] else {
                // End without Start — discard
                return nil
            }
            accumulated.append(contentsOf: bytes)
            buffers[group] = nil

            var result: [UInt8] = [0xF0]
            result.append(contentsOf: accumulated)
            result.append(0xF7)
            return result
        }
    }

    /// Reset all buffers
    public func reset() {
        buffers.removeAll()
    }

    /// Reset buffer for a specific group
    public func reset(group: UInt8) {
        buffers[group] = nil
    }
}
