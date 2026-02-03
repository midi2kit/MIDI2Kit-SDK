//
//  UMPTranslator.swift
//  MIDI2Kit
//
//  Bidirectional translation between UMP and MIDI 1.0 byte streams
//

import Foundation

/// Bidirectional translator between UMP messages and MIDI 1.0 byte streams
///
/// MIDI 2.0 uses Universal MIDI Packet (UMP) format internally, but many devices
/// and DAWs still use traditional MIDI 1.0 byte streams. This translator enables
/// interoperability between the two formats.
///
/// ## UMP to MIDI 1.0
///
/// ```swift
/// // Convert UMP message to MIDI 1.0 bytes
/// let ump = UMPMIDI1ChannelVoice.noteOn(group: 0, channel: 0, note: 60, velocity: 100)
/// if let midi1 = UMPTranslator.toMIDI1(ump) {
///     // midi1 = [0x90, 0x3C, 0x64]
///     sendToLegacyDevice(midi1)
/// }
///
/// // Convert MIDI 2.0 message (with downscaling)
/// let ump2 = UMPMIDI2ChannelVoice.noteOn(group: 0, channel: 0, note: 60, velocity: 0x8000, ...)
/// if let midi1 = UMPTranslator.toMIDI1(ump2) {
///     // velocity 0x8000 (16-bit) -> 64 (7-bit)
/// }
/// ```
///
/// ## MIDI 1.0 to UMP
///
/// ```swift
/// // Parse MIDI 1.0 bytes to UMP
/// let noteOn: [UInt8] = [0x90, 0x3C, 0x64]  // Note On, C4, velocity 100
/// if let ump = UMPTranslator.fromMIDI1(noteOn, group: 0) {
///     // Returns UMPMIDI1ChannelVoice.noteOn
/// }
///
/// // Upgrade to MIDI 2.0 with value expansion
/// if let ump2 = UMPTranslator.fromMIDI1ToMIDI2(noteOn, group: 0) {
///     // velocity 100 (7-bit) -> 0xC800 (16-bit, scaled)
/// }
/// ```
///
/// ## Scaling Rules
///
/// When converting between MIDI 1.0 (7-bit) and MIDI 2.0 (16/32-bit) values:
/// - **Upscaling**: 7-bit value is shifted and replicated (100 -> 0xC8C8)
/// - **Downscaling**: High bits are extracted (0x8000 -> 64)
///
/// Reference: MIDI 2.0 Specification, Section 4.2 "Value Scaling"
public enum UMPTranslator {

    // MARK: - UMP to MIDI 1.0

    /// Convert UMP message to MIDI 1.0 byte array
    ///
    /// - Parameter message: UMP message to convert
    /// - Returns: MIDI 1.0 bytes, or nil if message type is not convertible
    ///
    /// Supported message types:
    /// - MIDI 1.0 Channel Voice (direct extraction)
    /// - MIDI 2.0 Channel Voice (with downscaling)
    /// - System Real-Time (direct extraction)
    /// - System Common (direct extraction)
    public static func toMIDI1(_ message: any UMPMessage) -> [UInt8]? {
        switch message.messageType {
        case .midi1ChannelVoice:
            return midi1ChannelVoiceToMIDI1(message)

        case .midi2ChannelVoice:
            return midi2ChannelVoiceToMIDI1(message)

        case .system:
            return systemMessageToMIDI1(message)

        case .utility, .data64, .data128, .flexData, .umpStream:
            // These message types don't have MIDI 1.0 equivalents
            return nil
        }
    }

    /// Convert MIDI 1.0 UMP Channel Voice to MIDI 1.0 bytes
    private static func midi1ChannelVoiceToMIDI1(_ message: any UMPMessage) -> [UInt8]? {
        guard let midi1 = message as? UMPMIDI1ChannelVoice else { return nil }

        switch midi1 {
        case .noteOff(_, let channel, let note, let velocity):
            return [0x80 | channel.value, note & 0x7F, velocity & 0x7F]

        case .noteOn(_, let channel, let note, let velocity):
            return [0x90 | channel.value, note & 0x7F, velocity & 0x7F]

        case .polyPressure(_, let channel, let note, let pressure):
            return [0xA0 | channel.value, note & 0x7F, pressure & 0x7F]

        case .controlChange(_, let channel, let controller, let value):
            return [0xB0 | channel.value, controller & 0x7F, value & 0x7F]

        case .programChange(_, let channel, let program):
            return [0xC0 | channel.value, program & 0x7F]

        case .channelPressure(_, let channel, let pressure):
            return [0xD0 | channel.value, pressure & 0x7F]

        case .pitchBend(_, let channel, let value):
            let lsb = UInt8(value & 0x7F)
            let msb = UInt8((value >> 7) & 0x7F)
            return [0xE0 | channel.value, lsb, msb]
        }
    }

    /// Convert MIDI 2.0 UMP Channel Voice to MIDI 1.0 bytes (with downscaling)
    private static func midi2ChannelVoiceToMIDI1(_ message: any UMPMessage) -> [UInt8]? {
        guard let midi2 = message as? UMPMIDI2ChannelVoice else { return nil }

        switch midi2 {
        case .noteOff(_, let channel, let note, let velocity, _, _):
            let velocity7 = downscale16to7(velocity)
            return [0x80 | channel.value, note & 0x7F, velocity7]

        case .noteOn(_, let channel, let note, let velocity, _, _):
            let velocity7 = downscale16to7(velocity)
            return [0x90 | channel.value, note & 0x7F, velocity7]

        case .polyPressure(_, let channel, let note, let pressure):
            let pressure7 = downscale32to7(pressure)
            return [0xA0 | channel.value, note & 0x7F, pressure7]

        case .controlChange(_, let channel, let controller, let value):
            let value7 = downscale32to7(value)
            return [0xB0 | channel.value, controller & 0x7F, value7]

        case .programChange(_, let channel, let program, _, _, _):
            return [0xC0 | channel.value, program & 0x7F]

        case .channelPressure(_, let channel, let pressure):
            let pressure7 = downscale32to7(pressure)
            return [0xD0 | channel.value, pressure7]

        case .pitchBend(_, let channel, let value):
            // MIDI 2.0 pitch bend is 32-bit, center at 0x80000000
            // MIDI 1.0 pitch bend is 14-bit, center at 8192
            let value14 = downscale32to14(value)
            let lsb = UInt8(value14 & 0x7F)
            let msb = UInt8((value14 >> 7) & 0x7F)
            return [0xE0 | channel.value, lsb, msb]

        case .perNotePitchBend, .registeredPerNoteController, .assignablePerNoteController,
             .perNoteManagement, .registeredController, .assignableController,
             .relativeRegisteredController, .relativeAssignableController:
            // These MIDI 2.0 specific messages don't have direct MIDI 1.0 equivalents
            return nil
        }
    }

    /// Convert System messages to MIDI 1.0 bytes
    private static func systemMessageToMIDI1(_ message: any UMPMessage) -> [UInt8]? {
        if let realTime = message as? UMPSystemRealTime {
            switch realTime {
            case .timingClock: return [0xF8]
            case .start: return [0xFA]
            case .continue: return [0xFB]
            case .stop: return [0xFC]
            case .activeSensing: return [0xFE]
            case .systemReset: return [0xFF]
            }
        }

        if let common = message as? UMPSystemCommon {
            switch common {
            case .mtcQuarterFrame(_, let data):
                return [0xF1, data & 0x7F]
            case .songPosition(_, let position):
                let lsb = UInt8(position & 0x7F)
                let msb = UInt8((position >> 7) & 0x7F)
                return [0xF2, lsb, msb]
            case .songSelect(_, let song):
                return [0xF3, song & 0x7F]
            case .tuneRequest:
                return [0xF6]
            }
        }

        return nil
    }

    // MARK: - MIDI 1.0 to UMP

    /// Convert MIDI 1.0 bytes to UMP message (MIDI 1.0 protocol)
    ///
    /// - Parameters:
    ///   - bytes: MIDI 1.0 message bytes (1-3 bytes)
    ///   - group: UMP group to assign (default: 0)
    /// - Returns: UMPMIDI1ChannelVoice or system message, or nil if invalid
    public static func fromMIDI1(_ bytes: [UInt8], group: UMPGroup = 0) -> (any UMPMessage)? {
        guard !bytes.isEmpty else { return nil }

        let status = bytes[0]

        // System Real-Time (single byte, 0xF8-0xFF)
        if status >= 0xF8 {
            return parseSystemRealTime(status, group: group)
        }

        // System Common (0xF0-0xF7)
        if status >= 0xF0 {
            return parseSystemCommon(bytes, group: group)
        }

        // Channel Voice (0x80-0xEF)
        if status >= 0x80 {
            return parseChannelVoice(bytes, group: group)
        }

        return nil
    }

    /// Convert MIDI 1.0 bytes to MIDI 2.0 UMP message (with upscaling)
    ///
    /// - Parameters:
    ///   - bytes: MIDI 1.0 message bytes
    ///   - group: UMP group to assign (default: 0)
    /// - Returns: UMPMIDI2ChannelVoice, or nil if not a channel voice message
    ///
    /// This method converts MIDI 1.0 values to their MIDI 2.0 equivalents
    /// with proper value scaling (7-bit -> 16/32-bit).
    public static func fromMIDI1ToMIDI2(_ bytes: [UInt8], group: UMPGroup = 0) -> UMPMIDI2ChannelVoice? {
        guard bytes.count >= 2 else { return nil }

        let status = bytes[0]
        guard status >= 0x80 && status < 0xF0 else { return nil }

        let channel = UMPChannel(status & 0x0F)
        let messageType = status & 0xF0

        switch messageType {
        case 0x80: // Note Off
            guard bytes.count >= 3 else { return nil }
            let note = bytes[1] & 0x7F
            let velocity = upscale7to16(bytes[2] & 0x7F)
            return .noteOff(group: group, channel: channel, note: note, velocity: velocity)

        case 0x90: // Note On
            guard bytes.count >= 3 else { return nil }
            let note = bytes[1] & 0x7F
            let velocity = upscale7to16(bytes[2] & 0x7F)
            // Note: velocity 0 in MIDI 1.0 means Note Off
            if bytes[2] == 0 {
                return .noteOff(group: group, channel: channel, note: note, velocity: 0)
            }
            return .noteOn(group: group, channel: channel, note: note, velocity: velocity)

        case 0xA0: // Poly Pressure
            guard bytes.count >= 3 else { return nil }
            let note = bytes[1] & 0x7F
            let pressure = upscale7to32(bytes[2] & 0x7F)
            return .polyPressure(group: group, channel: channel, note: note, pressure: pressure)

        case 0xB0: // Control Change
            guard bytes.count >= 3 else { return nil }
            let controller = bytes[1] & 0x7F
            let value = upscale7to32(bytes[2] & 0x7F)
            return .controlChange(group: group, channel: channel, controller: controller, value: value)

        case 0xC0: // Program Change
            let program = bytes[1] & 0x7F
            return .programChange(group: group, channel: channel, program: program)

        case 0xD0: // Channel Pressure
            let pressure = upscale7to32(bytes[1] & 0x7F)
            return .channelPressure(group: group, channel: channel, pressure: pressure)

        case 0xE0: // Pitch Bend
            guard bytes.count >= 3 else { return nil }
            let lsb = UInt16(bytes[1] & 0x7F)
            let msb = UInt16(bytes[2] & 0x7F)
            let value14 = (msb << 7) | lsb
            let value32 = upscale14to32(value14)
            return .pitchBend(group: group, channel: channel, value: value32)

        default:
            return nil
        }
    }

    // MARK: - Private Parsing Helpers

    private static func parseChannelVoice(_ bytes: [UInt8], group: UMPGroup) -> UMPMIDI1ChannelVoice? {
        guard bytes.count >= 2 else { return nil }

        let status = bytes[0]
        let channel = UMPChannel(status & 0x0F)
        let messageType = status & 0xF0

        switch messageType {
        case 0x80: // Note Off
            guard bytes.count >= 3 else { return nil }
            return .noteOff(group: group, channel: channel, note: bytes[1] & 0x7F, velocity: bytes[2] & 0x7F)

        case 0x90: // Note On
            guard bytes.count >= 3 else { return nil }
            // Note: velocity 0 means Note Off in MIDI 1.0
            if bytes[2] == 0 {
                return .noteOff(group: group, channel: channel, note: bytes[1] & 0x7F, velocity: 0)
            }
            return .noteOn(group: group, channel: channel, note: bytes[1] & 0x7F, velocity: bytes[2] & 0x7F)

        case 0xA0: // Poly Pressure
            guard bytes.count >= 3 else { return nil }
            return .polyPressure(group: group, channel: channel, note: bytes[1] & 0x7F, pressure: bytes[2] & 0x7F)

        case 0xB0: // Control Change
            guard bytes.count >= 3 else { return nil }
            return .controlChange(group: group, channel: channel, controller: bytes[1] & 0x7F, value: bytes[2] & 0x7F)

        case 0xC0: // Program Change
            return .programChange(group: group, channel: channel, program: bytes[1] & 0x7F)

        case 0xD0: // Channel Pressure
            return .channelPressure(group: group, channel: channel, pressure: bytes[1] & 0x7F)

        case 0xE0: // Pitch Bend
            guard bytes.count >= 3 else { return nil }
            let lsb = UInt16(bytes[1] & 0x7F)
            let msb = UInt16(bytes[2] & 0x7F)
            let value = (msb << 7) | lsb
            return .pitchBend(group: group, channel: channel, value: value)

        default:
            return nil
        }
    }

    private static func parseSystemRealTime(_ status: UInt8, group: UMPGroup) -> UMPSystemRealTime? {
        switch status {
        case 0xF8: return .timingClock(group: group)
        case 0xFA: return .start(group: group)
        case 0xFB: return .continue(group: group)
        case 0xFC: return .stop(group: group)
        case 0xFE: return .activeSensing(group: group)
        case 0xFF: return .systemReset(group: group)
        default: return nil
        }
    }

    private static func parseSystemCommon(_ bytes: [UInt8], group: UMPGroup) -> UMPSystemCommon? {
        guard !bytes.isEmpty else { return nil }

        switch bytes[0] {
        case 0xF1: // Time Code Quarter Frame
            guard bytes.count >= 2 else { return nil }
            return .mtcQuarterFrame(group: group, data: bytes[1] & 0x7F)

        case 0xF2: // Song Position Pointer
            guard bytes.count >= 3 else { return nil }
            let lsb = UInt16(bytes[1] & 0x7F)
            let msb = UInt16(bytes[2] & 0x7F)
            return .songPosition(group: group, position: (msb << 7) | lsb)

        case 0xF3: // Song Select
            guard bytes.count >= 2 else { return nil }
            return .songSelect(group: group, song: bytes[1] & 0x7F)

        case 0xF6: // Tune Request
            return .tuneRequest(group: group)

        default:
            return nil
        }
    }

    // MARK: - Value Scaling

    /// Downscale 16-bit value to 7-bit (MIDI 2.0 velocity -> MIDI 1.0 velocity)
    public static func downscale16to7(_ value: UInt16) -> UInt8 {
        // Extract high 7 bits
        UInt8((value >> 9) & 0x7F)
    }

    /// Downscale 32-bit value to 7-bit (MIDI 2.0 CC -> MIDI 1.0 CC)
    public static func downscale32to7(_ value: UInt32) -> UInt8 {
        // Extract high 7 bits
        UInt8((value >> 25) & 0x7F)
    }

    /// Downscale 32-bit value to 14-bit (MIDI 2.0 pitch bend -> MIDI 1.0 pitch bend)
    public static func downscale32to14(_ value: UInt32) -> UInt16 {
        // Extract high 14 bits
        UInt16((value >> 18) & 0x3FFF)
    }

    /// Upscale 7-bit value to 16-bit (MIDI 1.0 velocity -> MIDI 2.0 velocity)
    public static func upscale7to16(_ value: UInt8) -> UInt16 {
        // Shift to high bits and replicate
        let v = UInt16(value & 0x7F)
        return (v << 9) | (v << 2) | (v >> 5)
    }

    /// Upscale 7-bit value to 32-bit (MIDI 1.0 CC -> MIDI 2.0 CC)
    public static func upscale7to32(_ value: UInt8) -> UInt32 {
        // Shift to high bits and replicate
        let v = UInt32(value & 0x7F)
        return (v << 25) | (v << 18) | (v << 11) | (v << 4) | (v >> 3)
    }

    /// Upscale 14-bit value to 32-bit (MIDI 1.0 pitch bend -> MIDI 2.0 pitch bend)
    public static func upscale14to32(_ value: UInt16) -> UInt32 {
        // Shift to high bits and replicate
        let v = UInt32(value & 0x3FFF)
        return (v << 18) | (v << 4) | (v >> 10)
    }
}

// MARK: - Batch Conversion

extension UMPTranslator {

    /// Convert multiple UMP messages to MIDI 1.0 byte stream
    ///
    /// - Parameter messages: Array of UMP messages
    /// - Returns: Concatenated MIDI 1.0 bytes (non-convertible messages are skipped)
    public static func toMIDI1Stream(_ messages: [any UMPMessage]) -> [UInt8] {
        var result: [UInt8] = []
        for message in messages {
            if let bytes = toMIDI1(message) {
                result.append(contentsOf: bytes)
            }
        }
        return result
    }

    /// Parse MIDI 1.0 byte stream to UMP messages
    ///
    /// - Parameters:
    ///   - bytes: MIDI 1.0 byte stream
    ///   - group: UMP group to assign (default: 0)
    /// - Returns: Array of UMP messages
    ///
    /// This method handles running status and parses a continuous MIDI 1.0 stream.
    public static func fromMIDI1Stream(_ bytes: [UInt8], group: UMPGroup = 0) -> [any UMPMessage] {
        var result: [any UMPMessage] = []
        var index = 0
        var runningStatus: UInt8 = 0

        while index < bytes.count {
            let byte = bytes[index]

            // System Real-Time (can appear anywhere)
            if byte >= 0xF8 {
                if let message = parseSystemRealTime(byte, group: group) {
                    result.append(message)
                }
                index += 1
                continue
            }

            // Status byte
            if byte >= 0x80 {
                runningStatus = byte
                index += 1

                // System Common resets running status
                if byte >= 0xF0 {
                    runningStatus = 0
                    let messageBytes = extractSystemCommonBytes(from: bytes, startIndex: index - 1)
                    if let message = parseSystemCommon(messageBytes, group: group) {
                        result.append(message)
                    }
                    index = index - 1 + messageBytes.count
                    continue
                }
            }

            // Need a valid running status
            guard runningStatus >= 0x80 && runningStatus < 0xF0 else {
                index += 1
                continue
            }

            // Get message length
            let dataBytes = dataByteCount(for: runningStatus)
            guard index + dataBytes <= bytes.count else { break }

            // Build message bytes
            var messageBytes = [runningStatus]
            for i in 0..<dataBytes {
                messageBytes.append(bytes[index + i])
            }

            if let message = parseChannelVoice(messageBytes, group: group) {
                result.append(message)
            }

            index += dataBytes
        }

        return result
    }

    private static func dataByteCount(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0: return 1  // Program Change, Channel Pressure
        default: return 2          // Note On/Off, Poly Pressure, CC, Pitch Bend
        }
    }

    private static func extractSystemCommonBytes(from bytes: [UInt8], startIndex: Int) -> [UInt8] {
        guard startIndex < bytes.count else { return [] }

        let status = bytes[startIndex]
        switch status {
        case 0xF1: // Time Code Quarter Frame
            guard startIndex + 1 < bytes.count else { return [status] }
            return [status, bytes[startIndex + 1]]

        case 0xF2: // Song Position Pointer
            guard startIndex + 2 < bytes.count else { return [status] }
            return [status, bytes[startIndex + 1], bytes[startIndex + 2]]

        case 0xF3: // Song Select
            guard startIndex + 1 < bytes.count else { return [status] }
            return [status, bytes[startIndex + 1]]

        case 0xF6: // Tune Request
            return [status]

        default:
            return [status]
        }
    }
}
