//
//  UMPBuilder.swift
//  MIDI2Kit
//
//  MIDI 2.0 Universal MIDI Packet message builder
//

import Foundation

// MARK: - UMP Message Builder

/// Builder for constructing MIDI 2.0 Universal MIDI Packet (UMP) messages
///
/// This struct provides static methods for building various UMP message types,
/// returning them as arrays of 32-bit words that can be sent via CoreMIDI's
/// `MIDIEventList` API.
///
/// ## Usage Example
///
/// ```swift
/// // Build a MIDI 2.0 Control Change message
/// let words = UMPBuilder.midi2ControlChange(
///     group: 0,
///     channel: 0,
///     controller: 74,  // Filter cutoff
///     value: 0x80000000  // 32-bit value
/// )
///
/// // Build a MIDI 2.0 Note On with 16-bit velocity
/// let noteWords = UMPBuilder.midi2NoteOn(
///     group: 0,
///     channel: 0,
///     note: 60,
///     velocity: 0xC000
/// )
/// ```
///
/// ## Thread Safety
///
/// All methods are pure functions with no shared state, making them safe to call
/// from any thread or actor context.
public enum UMPBuilder {
    
    // MARK: - MIDI 2.0 Channel Voice Messages
    
    /// Build a MIDI 2.0 Control Change message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - controller: CC index (0-127)
    ///   - value: 32-bit value
    /// - Returns: Array of 2 UInt32 words
    public static func midi2ControlChange(
        group: UInt8,
        channel: UInt8,
        controller: UInt8,
        value: UInt32
    ) -> [UInt32] {
        let word0 = buildMIDI2Word0(
            group: group,
            status: .controlChange,
            channel: channel,
            index: controller
        )
        return [word0, value]
    }
    
    /// Build a MIDI 2.0 Control Change message with normalized value
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - controller: CC index (0-127)
    ///   - normalizedValue: Value from 0.0 to 1.0
    /// - Returns: Array of 2 UInt32 words
    public static func midi2ControlChangeNormalized(
        group: UInt8,
        channel: UInt8,
        controller: UInt8,
        normalizedValue: Double
    ) -> [UInt32] {
        let value = UMPValueScaling.normalizedTo32(normalizedValue)
        return midi2ControlChange(group: group, channel: channel, controller: controller, value: value)
    }
    
    /// Build a MIDI 2.0 Program Change message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - program: Program number (0-127)
    ///   - bank: Optional bank selection
    /// - Returns: Array of 2 UInt32 words
    public static func midi2ProgramChange(
        group: UInt8,
        channel: UInt8,
        program: UInt8,
        bank: ProgramBank? = nil
    ) -> [UInt32] {
        let word0 = buildMIDI2Word0(
            group: group,
            status: .programChange,
            channel: channel,
            index: 0
        )
        
        var word1: UInt32 = 0
        if let bank = bank {
            // Set bank valid flag (bit 31) and bank values
            word1 = (1 << 31) |
                    (UInt32(program & 0x7F) << 24) |
                    (UInt32(bank.msb) << 8) |
                    UInt32(bank.lsb)
        } else {
            // No bank, just program
            word1 = UInt32(program & 0x7F) << 24
        }
        
        return [word0, word1]
    }
    
    /// Build a MIDI 2.0 Note On message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - velocity: 16-bit velocity (0x0000 = Note Off equivalent)
    ///   - attributeType: Note attribute type
    ///   - attributeData: Note attribute data
    /// - Returns: Array of 2 UInt32 words
    public static func midi2NoteOn(
        group: UInt8,
        channel: UInt8,
        note: UInt8,
        velocity: UInt16,
        attributeType: NoteAttributeType = .none,
        attributeData: UInt16 = 0
    ) -> [UInt32] {
        let word0 = buildMIDI2Word0(
            group: group,
            status: .noteOn,
            channel: channel,
            index: note,
            extra: attributeType.rawValue
        )
        let word1 = (UInt32(velocity) << 16) | UInt32(attributeData)
        return [word0, word1]
    }
    
    /// Build a MIDI 2.0 Note Off message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - velocity: 16-bit release velocity
    ///   - attributeType: Note attribute type
    ///   - attributeData: Note attribute data
    /// - Returns: Array of 2 UInt32 words
    public static func midi2NoteOff(
        group: UInt8,
        channel: UInt8,
        note: UInt8,
        velocity: UInt16 = 0,
        attributeType: NoteAttributeType = .none,
        attributeData: UInt16 = 0
    ) -> [UInt32] {
        let word0 = buildMIDI2Word0(
            group: group,
            status: .noteOff,
            channel: channel,
            index: note,
            extra: attributeType.rawValue
        )
        let word1 = (UInt32(velocity) << 16) | UInt32(attributeData)
        return [word0, word1]
    }
    
    /// Build a MIDI 2.0 Pitch Bend message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - value: 32-bit pitch bend value (0x80000000 = center)
    /// - Returns: Array of 2 UInt32 words
    public static func midi2PitchBend(
        group: UInt8,
        channel: UInt8,
        value: UInt32
    ) -> [UInt32] {
        let word0 = buildMIDI2Word0(
            group: group,
            status: .pitchBend,
            channel: channel,
            index: 0
        )
        return [word0, value]
    }
    
    /// Build a MIDI 2.0 Channel Pressure message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - pressure: 32-bit pressure value
    /// - Returns: Array of 2 UInt32 words
    public static func midi2ChannelPressure(
        group: UInt8,
        channel: UInt8,
        pressure: UInt32
    ) -> [UInt32] {
        let word0 = buildMIDI2Word0(
            group: group,
            status: .channelPressure,
            channel: channel,
            index: 0
        )
        return [word0, pressure]
    }
    
    /// Build a MIDI 2.0 Poly Pressure message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - pressure: 32-bit pressure value
    /// - Returns: Array of 2 UInt32 words
    public static func midi2PolyPressure(
        group: UInt8,
        channel: UInt8,
        note: UInt8,
        pressure: UInt32
    ) -> [UInt32] {
        let word0 = buildMIDI2Word0(
            group: group,
            status: .polyPressure,
            channel: channel,
            index: note
        )
        return [word0, pressure]
    }
    
    /// Build a MIDI 2.0 Per-Note Pitch Bend message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - value: 32-bit pitch bend value
    /// - Returns: Array of 2 UInt32 words
    public static func midi2PerNotePitchBend(
        group: UInt8,
        channel: UInt8,
        note: UInt8,
        value: UInt32
    ) -> [UInt32] {
        let word0 = buildMIDI2Word0(
            group: group,
            status: .perNotePitchBend,
            channel: channel,
            index: note
        )
        return [word0, value]
    }
    
    /// Build a MIDI 2.0 Registered Controller (RPN) message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - address: Controller bank and index
    ///   - value: 32-bit value
    /// - Returns: Array of 2 UInt32 words
    public static func midi2RegisteredController(
        group: UInt8,
        channel: UInt8,
        address: ControllerAddress,
        value: UInt32
    ) -> [UInt32] {
        let word0 = UInt32(UMPMessageType.midi2ChannelVoice.rawValue) << 28 |
                    UInt32(group & 0x0F) << 24 |
                    UInt32(MIDI2ChannelVoiceStatus.registeredController.rawValue) << 20 |
                    UInt32(channel & 0x0F) << 16 |
                    UInt32(address.bank) << 8 |
                    UInt32(address.index)
        return [word0, value]
    }
    
    /// Build a MIDI 2.0 Assignable Controller (NRPN) message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - address: Controller bank and index
    ///   - value: 32-bit value
    /// - Returns: Array of 2 UInt32 words
    public static func midi2AssignableController(
        group: UInt8,
        channel: UInt8,
        address: ControllerAddress,
        value: UInt32
    ) -> [UInt32] {
        let word0 = UInt32(UMPMessageType.midi2ChannelVoice.rawValue) << 28 |
                    UInt32(group & 0x0F) << 24 |
                    UInt32(MIDI2ChannelVoiceStatus.assignableController.rawValue) << 20 |
                    UInt32(channel & 0x0F) << 16 |
                    UInt32(address.bank) << 8 |
                    UInt32(address.index)
        return [word0, value]
    }
    
    /// Build a MIDI 2.0 Per-Note Management message (64-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - detach: Detach per-note controllers
    ///   - reset: Reset per-note controllers
    /// - Returns: Array of 2 UInt32 words
    public static func midi2PerNoteManagement(
        group: UInt8,
        channel: UInt8,
        note: UInt8,
        detach: Bool = false,
        reset: Bool = false
    ) -> [UInt32] {
        var flags: UInt8 = 0
        if detach { flags |= 0x02 }
        if reset { flags |= 0x01 }
        
        let word0 = buildMIDI2Word0(
            group: group,
            status: .perNoteManagement,
            channel: channel,
            index: note,
            extra: flags
        )
        return [word0, 0]
    }
    
    // MARK: - Data 64-bit Messages (SysEx7)

    /// Build a Data 64-bit (SysEx7) UMP message
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - status: SysEx7 status (complete/start/continue/end)
    ///   - numBytes: Number of valid data bytes (0-6)
    ///   - data: Data bytes (up to 6; excess bytes are ignored, missing bytes are zero-filled)
    /// - Returns: Array of 2 UInt32 words
    public static func data64(
        group: UInt8,
        status: UInt8,
        numBytes: UInt8,
        data: [UInt8]
    ) -> [UInt32] {
        let clampedNum = min(numBytes, 6)

        // Pad data to 6 bytes
        var d = [UInt8](repeating: 0, count: 6)
        for i in 0..<min(Int(clampedNum), data.count) {
            d[i] = data[i]
        }

        let word0 = UInt32(UMPMessageType.data64.rawValue) << 28 |
                     UInt32(group & 0x0F) << 24 |
                     UInt32(status & 0x0F) << 20 |
                     UInt32(clampedNum) << 16 |
                     UInt32(d[0]) << 8 |
                     UInt32(d[1])

        let word1 = UInt32(d[2]) << 24 |
                     UInt32(d[3]) << 16 |
                     UInt32(d[4]) << 8 |
                     UInt32(d[5])

        return [word0, word1]
    }

    // MARK: - MIDI 1.0 over UMP (32-bit)
    
    /// Build a MIDI 1.0 Control Change wrapped in UMP (32-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - controller: CC number (0-127)
    ///   - value: 7-bit value (0-127)
    /// - Returns: Array of 1 UInt32 word
    public static func midi1ControlChange(
        group: UInt8,
        channel: UInt8,
        controller: UInt8,
        value: UInt8
    ) -> [UInt32] {
        let statusByte: UInt8 = 0xB0 | (channel & 0x0F)
        return midi1ChannelVoice(group: group, statusByte: statusByte, data1: controller, data2: value)
    }
    
    /// Build a MIDI 1.0 Program Change wrapped in UMP (32-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - program: Program number (0-127)
    /// - Returns: Array of 1 UInt32 word
    public static func midi1ProgramChange(
        group: UInt8,
        channel: UInt8,
        program: UInt8
    ) -> [UInt32] {
        let statusByte: UInt8 = 0xC0 | (channel & 0x0F)
        return midi1ChannelVoice(group: group, statusByte: statusByte, data1: program, data2: nil)
    }
    
    /// Build a MIDI 1.0 Note On wrapped in UMP (32-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - velocity: 7-bit velocity (0-127)
    /// - Returns: Array of 1 UInt32 word
    public static func midi1NoteOn(
        group: UInt8,
        channel: UInt8,
        note: UInt8,
        velocity: UInt8
    ) -> [UInt32] {
        let statusByte: UInt8 = 0x90 | (channel & 0x0F)
        return midi1ChannelVoice(group: group, statusByte: statusByte, data1: note, data2: velocity)
    }
    
    /// Build a MIDI 1.0 Note Off wrapped in UMP (32-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - velocity: 7-bit release velocity (0-127)
    /// - Returns: Array of 1 UInt32 word
    public static func midi1NoteOff(
        group: UInt8,
        channel: UInt8,
        note: UInt8,
        velocity: UInt8 = 0
    ) -> [UInt32] {
        let statusByte: UInt8 = 0x80 | (channel & 0x0F)
        return midi1ChannelVoice(group: group, statusByte: statusByte, data1: note, data2: velocity)
    }
    
    /// Build a MIDI 1.0 Pitch Bend wrapped in UMP (32-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - value: 14-bit pitch bend value (0-16383, center = 8192)
    /// - Returns: Array of 1 UInt32 word
    public static func midi1PitchBend(
        group: UInt8,
        channel: UInt8,
        value: UInt16
    ) -> [UInt32] {
        let statusByte: UInt8 = 0xE0 | (channel & 0x0F)
        let lsb = UInt8(value & 0x7F)
        let msb = UInt8((value >> 7) & 0x7F)
        return midi1ChannelVoice(group: group, statusByte: statusByte, data1: lsb, data2: msb)
    }
    
    /// Build a generic MIDI 1.0 Channel Voice message wrapped in UMP (32-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - statusByte: MIDI 1.0 status byte (includes channel)
    ///   - data1: First data byte
    ///   - data2: Second data byte (optional)
    /// - Returns: Array of 1 UInt32 word
    public static func midi1ChannelVoice(
        group: UInt8,
        statusByte: UInt8,
        data1: UInt8,
        data2: UInt8?
    ) -> [UInt32] {
        var word = UInt32(UMPMessageType.midi1ChannelVoice.rawValue) << 28 |
                   UInt32(group & 0x0F) << 24 |
                   UInt32(statusByte) << 16 |
                   UInt32(data1 & 0x7F) << 8
        
        if let d2 = data2 {
            word |= UInt32(d2 & 0x7F)
        }
        
        return [word]
    }
    
    // MARK: - Utility Messages (32-bit)
    
    /// Build a NOOP (No Operation) message
    ///
    /// - Parameter group: UMP group (0-15)
    /// - Returns: Array of 1 UInt32 word
    public static func noop(group: UInt8) -> [UInt32] {
        let word = UInt32(UMPMessageType.utility.rawValue) << 28 |
                   UInt32(group & 0x0F) << 24
        return [word]
    }
    
    /// Build a JR Clock message
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - senderClockTime: 16-bit sender clock time
    /// - Returns: Array of 1 UInt32 word
    public static func jrClock(group: UInt8, senderClockTime: UInt16) -> [UInt32] {
        let word = UInt32(UMPMessageType.utility.rawValue) << 28 |
                   UInt32(group & 0x0F) << 24 |
                   UInt32(0x1) << 20 |  // JR Clock status
                   UInt32(senderClockTime)
        return [word]
    }
    
    /// Build a JR Timestamp message
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - timestamp: 16-bit timestamp
    /// - Returns: Array of 1 UInt32 word
    public static func jrTimestamp(group: UInt8, timestamp: UInt16) -> [UInt32] {
        let word = UInt32(UMPMessageType.utility.rawValue) << 28 |
                   UInt32(group & 0x0F) << 24 |
                   UInt32(0x2) << 20 |  // JR Timestamp status
                   UInt32(timestamp)
        return [word]
    }
    
    // MARK: - Private Helpers
    
    /// Build the first word of a MIDI 2.0 Channel Voice message
    private static func buildMIDI2Word0(
        group: UInt8,
        status: MIDI2ChannelVoiceStatus,
        channel: UInt8,
        index: UInt8,
        extra: UInt8 = 0
    ) -> UInt32 {
        UInt32(UMPMessageType.midi2ChannelVoice.rawValue) << 28 |
        UInt32(group & 0x0F) << 24 |
        UInt32(status.rawValue) << 20 |
        UInt32(channel & 0x0F) << 16 |
        UInt32(index) << 8 |
        UInt32(extra)
    }
}

// MARK: - Convenience Extensions

extension UMPBuilder {
    
    /// Build a MIDI 2.0 Note On with 7-bit velocity (auto-scaled to 16-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - velocity7: 7-bit velocity (0-127)
    /// - Returns: Array of 2 UInt32 words
    public static func midi2NoteOn7(
        group: UInt8,
        channel: UInt8,
        note: UInt8,
        velocity7: UInt8
    ) -> [UInt32] {
        let velocity16 = UMPValueScaling.scaleVelocity7To16(velocity7)
        return midi2NoteOn(group: group, channel: channel, note: note, velocity: velocity16)
    }
    
    /// Build a MIDI 2.0 Control Change with 7-bit value (auto-scaled to 32-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - controller: CC index (0-127)
    ///   - value7: 7-bit value (0-127)
    /// - Returns: Array of 2 UInt32 words
    public static func midi2ControlChange7(
        group: UInt8,
        channel: UInt8,
        controller: UInt8,
        value7: UInt8
    ) -> [UInt32] {
        let value32 = UMPValueScaling.scale7To32(value7)
        return midi2ControlChange(group: group, channel: channel, controller: controller, value: value32)
    }
    
    /// Build a MIDI 2.0 Pitch Bend with 14-bit value (auto-scaled to 32-bit)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15)
    ///   - channel: MIDI channel (0-15)
    ///   - value14: 14-bit pitch bend value (0-16383)
    /// - Returns: Array of 2 UInt32 words
    public static func midi2PitchBend14(
        group: UInt8,
        channel: UInt8,
        value14: UInt16
    ) -> [UInt32] {
        let value32 = UMPValueScaling.scale14To32(value14)
        return midi2PitchBend(group: group, channel: channel, value: value32)
    }
}
