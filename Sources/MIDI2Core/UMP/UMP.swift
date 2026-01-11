//
//  UMP.swift
//  MIDI2Kit
//
//  Convenient UMP message factory
//

import Foundation

/// Convenient factory for creating UMP messages
///
/// ## Example Usage
///
/// ```swift
/// // MIDI 2.0 messages (64-bit, high resolution)
/// let noteOn = UMP.noteOn(channel: 0, note: 60, velocity: 0x8000)
/// let cc = UMP.controlChange(channel: 0, controller: 74, value: 0x80000000)
///
/// // MIDI 1.0 messages (32-bit, compatible)
/// let noteOn1 = UMP.midi1.noteOn(channel: 0, note: 60, velocity: 100)
/// let cc1 = UMP.midi1.volume(channel: 0, value: 100)
///
/// // Send via transport
/// try await transport.send(noteOn)
/// ```
public enum UMP {
    
    // MARK: - MIDI 2.0 Channel Voice (64-bit, high resolution)
    
    /// Note On (MIDI 2.0)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15, default 0)
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - velocity: 16-bit velocity (0-65535)
    public static func noteOn(
        group: UMPGroup = 0,
        channel: UMPChannel,
        note: UInt8,
        velocity: UInt16
    ) -> UMPMIDI2ChannelVoice {
        .noteOn(group: group, channel: channel, note: note, velocity: velocity)
    }
    
    /// Note Off (MIDI 2.0)
    public static func noteOff(
        group: UMPGroup = 0,
        channel: UMPChannel,
        note: UInt8,
        velocity: UInt16 = 0
    ) -> UMPMIDI2ChannelVoice {
        .noteOff(group: group, channel: channel, note: note, velocity: velocity)
    }
    
    /// Control Change (MIDI 2.0, 32-bit resolution)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15, default 0)
    ///   - channel: MIDI channel (0-15)
    ///   - controller: CC number (0-127)
    ///   - value: 32-bit value (0-4294967295)
    public static func controlChange(
        group: UMPGroup = 0,
        channel: UMPChannel,
        controller: UInt8,
        value: UInt32
    ) -> UMPMIDI2ChannelVoice {
        .controlChange(group: group, channel: channel, controller: controller, value: value)
    }
    
    /// Pitch Bend (MIDI 2.0, 32-bit resolution)
    ///
    /// - Parameters:
    ///   - group: UMP group (0-15, default 0)
    ///   - channel: MIDI channel (0-15)
    ///   - value: 32-bit value (center = 0x80000000)
    public static func pitchBend(
        group: UMPGroup = 0,
        channel: UMPChannel,
        value: UInt32
    ) -> UMPMIDI2ChannelVoice {
        .pitchBend(group: group, channel: channel, value: value)
    }
    
    /// Program Change (MIDI 2.0)
    public static func programChange(
        group: UMPGroup = 0,
        channel: UMPChannel,
        program: UInt8,
        bankMSB: UInt8? = nil,
        bankLSB: UInt8? = nil
    ) -> UMPMIDI2ChannelVoice {
        let bankValid = bankMSB != nil || bankLSB != nil
        return .programChange(
            group: group,
            channel: channel,
            program: program,
            bankValid: bankValid,
            bankMSB: bankMSB ?? 0,
            bankLSB: bankLSB ?? 0
        )
    }
    
    /// Channel Pressure / Aftertouch (MIDI 2.0)
    public static func channelPressure(
        group: UMPGroup = 0,
        channel: UMPChannel,
        pressure: UInt32
    ) -> UMPMIDI2ChannelVoice {
        .channelPressure(group: group, channel: channel, pressure: pressure)
    }
    
    /// Poly Pressure / Aftertouch (MIDI 2.0)
    public static func polyPressure(
        group: UMPGroup = 0,
        channel: UMPChannel,
        note: UInt8,
        pressure: UInt32
    ) -> UMPMIDI2ChannelVoice {
        .polyPressure(group: group, channel: channel, note: note, pressure: pressure)
    }
    
    /// Registered Controller (RPN, MIDI 2.0)
    public static func rpn(
        group: UMPGroup = 0,
        channel: UMPChannel,
        bank: UInt8,
        index: UInt8,
        value: UInt32
    ) -> UMPMIDI2ChannelVoice {
        .registeredController(group: group, channel: channel, bank: bank, index: index, value: value)
    }
    
    /// Assignable Controller (NRPN, MIDI 2.0)
    public static func nrpn(
        group: UMPGroup = 0,
        channel: UMPChannel,
        bank: UInt8,
        index: UInt8,
        value: UInt32
    ) -> UMPMIDI2ChannelVoice {
        .assignableController(group: group, channel: channel, bank: bank, index: index, value: value)
    }
    
    // MARK: - MIDI 1.0 Messages
    
    /// MIDI 1.0 message factory
    public enum midi1 {
        
        /// Note On (MIDI 1.0)
        public static func noteOn(
            group: UMPGroup = 0,
            channel: UMPChannel,
            note: UInt8,
            velocity: UInt8
        ) -> UMPMIDI1ChannelVoice {
            .noteOn(group: group, channel: channel, note: note, velocity: velocity)
        }
        
        /// Note Off (MIDI 1.0)
        public static func noteOff(
            group: UMPGroup = 0,
            channel: UMPChannel,
            note: UInt8,
            velocity: UInt8 = 0
        ) -> UMPMIDI1ChannelVoice {
            .noteOff(group: group, channel: channel, note: note, velocity: velocity)
        }
        
        /// Control Change (MIDI 1.0)
        public static func controlChange(
            group: UMPGroup = 0,
            channel: UMPChannel,
            controller: UInt8,
            value: UInt8
        ) -> UMPMIDI1ChannelVoice {
            .controlChange(group: group, channel: channel, controller: controller, value: value)
        }
        
        /// Volume (CC 7)
        public static func volume(
            group: UMPGroup = 0,
            channel: UMPChannel,
            value: UInt8
        ) -> UMPMIDI1ChannelVoice {
            .volume(group: group, channel: channel, value: value)
        }
        
        /// Pan (CC 10)
        public static func pan(
            group: UMPGroup = 0,
            channel: UMPChannel,
            value: UInt8
        ) -> UMPMIDI1ChannelVoice {
            .pan(group: group, channel: channel, value: value)
        }
        
        /// Modulation (CC 1)
        public static func modulation(
            group: UMPGroup = 0,
            channel: UMPChannel,
            value: UInt8
        ) -> UMPMIDI1ChannelVoice {
            .modulation(group: group, channel: channel, value: value)
        }
        
        /// Sustain Pedal (CC 64)
        public static func sustain(
            group: UMPGroup = 0,
            channel: UMPChannel,
            on: Bool
        ) -> UMPMIDI1ChannelVoice {
            .sustain(group: group, channel: channel, on: on)
        }
        
        /// Program Change (MIDI 1.0)
        public static func programChange(
            group: UMPGroup = 0,
            channel: UMPChannel,
            program: UInt8
        ) -> UMPMIDI1ChannelVoice {
            .programChange(group: group, channel: channel, program: program)
        }
        
        /// Pitch Bend (MIDI 1.0, 14-bit)
        ///
        /// - Parameter value: 0-16383, center = 8192
        public static func pitchBend(
            group: UMPGroup = 0,
            channel: UMPChannel,
            value: UInt16
        ) -> UMPMIDI1ChannelVoice {
            .pitchBend(group: group, channel: channel, value: value)
        }
        
        /// All Notes Off
        public static func allNotesOff(
            group: UMPGroup = 0,
            channel: UMPChannel
        ) -> UMPMIDI1ChannelVoice {
            .allNotesOff(group: group, channel: channel)
        }
        
        /// All Sound Off
        public static func allSoundOff(
            group: UMPGroup = 0,
            channel: UMPChannel
        ) -> UMPMIDI1ChannelVoice {
            .allSoundOff(group: group, channel: channel)
        }
    }
    
    // MARK: - System Messages
    
    /// System message factory
    public enum system {
        /// Timing Clock
        public static func timingClock(group: UMPGroup = 0) -> UMPSystemRealTime {
            .timingClock(group: group)
        }
        
        /// Start
        public static func start(group: UMPGroup = 0) -> UMPSystemRealTime {
            .start(group: group)
        }
        
        /// Continue
        public static func `continue`(group: UMPGroup = 0) -> UMPSystemRealTime {
            .continue(group: group)
        }
        
        /// Stop
        public static func stop(group: UMPGroup = 0) -> UMPSystemRealTime {
            .stop(group: group)
        }
        
        /// Song Position Pointer
        public static func songPosition(group: UMPGroup = 0, position: UInt16) -> UMPSystemCommon {
            .songPosition(group: group, position: position)
        }
        
        /// Song Select
        public static func songSelect(group: UMPGroup = 0, song: UInt8) -> UMPSystemCommon {
            .songSelect(group: group, song: song)
        }
    }
}

// MARK: - Value Conversion Helpers

extension UMP {
    
    /// Convert 7-bit MIDI 1.0 velocity to 16-bit MIDI 2.0 velocity
    public static func velocity7to16(_ velocity7: UInt8) -> UInt16 {
        // Scale 0-127 to 0-65535
        let v = UInt16(velocity7 & 0x7F)
        return v == 0 ? 0 : (v << 9) | (v << 2) | (v >> 5)
    }
    
    /// Convert 16-bit MIDI 2.0 velocity to 7-bit MIDI 1.0 velocity
    public static func velocity16to7(_ velocity16: UInt16) -> UInt8 {
        UInt8(velocity16 >> 9)
    }
    
    /// Convert 7-bit MIDI 1.0 CC value to 32-bit MIDI 2.0 value
    public static func cc7to32(_ value7: UInt8) -> UInt32 {
        let v = UInt32(value7 & 0x7F)
        return v == 0 ? 0 : (v << 25) | (v << 18) | (v << 11) | (v << 4) | (v >> 3)
    }
    
    /// Convert 32-bit MIDI 2.0 CC value to 7-bit MIDI 1.0 value
    public static func cc32to7(_ value32: UInt32) -> UInt8 {
        UInt8(value32 >> 25)
    }
    
    /// Convert 14-bit MIDI 1.0 pitch bend to 32-bit MIDI 2.0 value
    public static func pitchBend14to32(_ value14: UInt16) -> UInt32 {
        let v = UInt32(value14 & 0x3FFF)
        return (v << 18) | (v << 4) | (v >> 10)
    }
    
    /// Convert 32-bit MIDI 2.0 pitch bend to 14-bit MIDI 1.0 value
    public static func pitchBend32to14(_ value32: UInt32) -> UInt16 {
        UInt16(value32 >> 18)
    }
    
    /// MIDI 2.0 pitch bend center value (no bend)
    public static let pitchBendCenter: UInt32 = 0x80000000
    
    /// MIDI 1.0 pitch bend center value (no bend)
    public static let pitchBendCenter14: UInt16 = 8192
}
