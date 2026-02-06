//
//  UMPTypes.swift
//  MIDI2Kit
//
//  MIDI 2.0 Universal MIDI Packet (UMP) type definitions
//

import Foundation

// MARK: - UMP Message Types

/// MIDI 2.0 Universal MIDI Packet message types
///
/// The message type is encoded in the upper 4 bits of the first word (bits 31-28).
/// It determines the packet size and interpretation of the remaining bits.
///
/// ## Packet Sizes
/// - Types 0x0, 0x1, 0x2: 32-bit (1 word)
/// - Types 0x3, 0x4: 64-bit (2 words)
/// - Type 0x5: 128-bit (4 words)
///
/// Reference: MIDI 2.0 UMP Specification, Section 2.1
public enum UMPMessageType: UInt8, Sendable, CaseIterable {
    /// Utility messages: NOOP, JR Clock, JR Timestamp, Delta Clockstamp
    case utility = 0x0
    
    /// System Real Time and System Common messages (excluding SysEx)
    case system = 0x1
    
    /// MIDI 1.0 Channel Voice messages wrapped in UMP (32-bit)
    case midi1ChannelVoice = 0x2
    
    /// 64-bit Data messages: SysEx7
    case data64 = 0x3
    
    /// MIDI 2.0 Channel Voice messages (64-bit, high resolution)
    case midi2ChannelVoice = 0x4
    
    /// 128-bit Data messages: SysEx8, Mixed Data Set
    case data128 = 0x5
    
    /// Flex Data messages (128-bit)
    case flexData = 0xD
    
    /// UMP Stream messages (128-bit)
    case umpStream = 0xF
    
    /// Number of 32-bit words in this message type
    public var wordCount: Int {
        switch self {
        case .utility, .system, .midi1ChannelVoice:
            return 1
        case .data64, .midi2ChannelVoice:
            return 2
        case .data128, .flexData, .umpStream:
            return 4
        }
    }
}

// MARK: - MIDI 2.0 Channel Voice Status

/// MIDI 2.0 Channel Voice message status codes
///
/// These are the status nibble values (bits 23-20) for MIDI 2.0 Channel Voice messages
/// (message type 0x4).
///
/// Reference: MIDI 2.0 UMP Specification, Section 4.2
public enum MIDI2ChannelVoiceStatus: UInt8, Sendable, CaseIterable {
    /// Registered Per-Note Controller (RPN per note)
    case registeredPerNoteController = 0x0
    
    /// Assignable Per-Note Controller (NRPN per note)
    case assignablePerNoteController = 0x1
    
    /// Registered Controller (RPN, 32-bit value)
    case registeredController = 0x2
    
    /// Assignable Controller (NRPN, 32-bit value)
    case assignableController = 0x3
    
    /// Relative Registered Controller
    case relativeRegisteredController = 0x4
    
    /// Relative Assignable Controller
    case relativeAssignableController = 0x5
    
    /// Per-Note Pitch Bend
    case perNotePitchBend = 0x6
    
    /// Note Off
    case noteOff = 0x8
    
    /// Note On
    case noteOn = 0x9
    
    /// Poly Pressure (Polyphonic Aftertouch)
    case polyPressure = 0xA
    
    /// Control Change (32-bit value)
    case controlChange = 0xB
    
    /// Program Change (with optional bank)
    case programChange = 0xC
    
    /// Channel Pressure (Aftertouch, 32-bit value)
    case channelPressure = 0xD
    
    /// Pitch Bend (32-bit value)
    case pitchBend = 0xE
    
    /// Per-Note Management
    case perNoteManagement = 0xF
}

// MARK: - SysEx7 Status (Data 64)

/// SysEx7 (Data 64) message status codes
///
/// Used in the status field of Data 64 (Type 0x3) UMP messages to indicate
/// whether the packet is a complete message or part of a multi-packet sequence.
///
/// Reference: MIDI 2.0 UMP Specification, Section 3.1
public enum SysEx7Status: UInt8, Sendable, CaseIterable {
    /// Complete SysEx message in one packet (payload <= 6 bytes)
    case complete = 0x0

    /// First packet of a multi-packet SysEx message
    case start = 0x1

    /// Continuation packet of a multi-packet SysEx message
    case `continue` = 0x2

    /// Last packet of a multi-packet SysEx message
    case end = 0x3
}

// MARK: - MIDI 1.0 Channel Voice Status (for UMP wrapping)

/// MIDI 1.0 Channel Voice message status codes
///
/// Used when wrapping MIDI 1.0 messages in UMP format (message type 0x2).
public enum MIDI1ChannelVoiceStatus: UInt8, Sendable {
    case noteOff = 0x8
    case noteOn = 0x9
    case polyPressure = 0xA
    case controlChange = 0xB
    case programChange = 0xC
    case channelPressure = 0xD
    case pitchBend = 0xE
}

// MARK: - Note Attribute Types

/// MIDI 2.0 Note Attribute types
///
/// Used with Note On/Off messages to provide additional information about the note.
public enum NoteAttributeType: UInt8, Sendable {
    /// No attribute data
    case none = 0x0
    
    /// Manufacturer-specific attribute
    case manufacturerSpecific = 0x1
    
    /// Profile-specific attribute
    case profileSpecific = 0x2
    
    /// Pitch 7.9 (fixed-point pitch in semitones)
    case pitch7_9 = 0x3
}

// MARK: - UMP Group

/// Represents a UMP Group (0-15)
///
/// MIDI 2.0 supports 16 groups, each with 16 channels, for a total of 256 channels.
public struct UMPGroup: RawRepresentable, Sendable, Hashable, ExpressibleByIntegerLiteral {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue & 0x0F
    }
    
    public init(integerLiteral value: UInt8) {
        self.rawValue = value & 0x0F
    }
    
    /// Group 0 (default)
    public static let group0 = UMPGroup(rawValue: 0)
    
    /// Valid range check
    public static func isValid(_ value: UInt8) -> Bool {
        value <= 15
    }
}

// MARK: - MIDI Channel

/// Represents a MIDI Channel (0-15)
public struct MIDIChannel: RawRepresentable, Sendable, Hashable, ExpressibleByIntegerLiteral {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue & 0x0F
    }
    
    public init(integerLiteral value: UInt8) {
        self.rawValue = value & 0x0F
    }
    
    /// Display value (1-16)
    public var displayValue: Int {
        Int(rawValue) + 1
    }
    
    /// Channel 1 (internal value 0)
    public static let channel1 = MIDIChannel(rawValue: 0)
}

// MARK: - Value Scaling Utilities

/// Utilities for scaling values between MIDI 1.0 and MIDI 2.0 resolutions
public enum UMPValueScaling {
    
    /// Scale 7-bit value (0-127) to 32-bit value
    ///
    /// Maps to the upper 7 bits of the 32-bit range.
    /// - Parameter value7: 7-bit value (0-127)
    /// - Returns: 32-bit scaled value
    public static func scale7To32(_ value7: UInt8) -> UInt32 {
        // Upper 7 bits of 32-bit value
        UInt32(value7 & 0x7F) << 25
    }
    
    /// Scale 14-bit value (0-16383) to 32-bit value
    ///
    /// Maps to the upper 14 bits of the 32-bit range.
    /// - Parameter value14: 14-bit value (0-16383)
    /// - Returns: 32-bit scaled value
    public static func scale14To32(_ value14: UInt16) -> UInt32 {
        UInt32(value14 & 0x3FFF) << 18
    }
    
    /// Scale 32-bit value to 7-bit value (0-127)
    ///
    /// - Parameter value32: 32-bit value
    /// - Returns: 7-bit scaled value
    public static func scale32To7(_ value32: UInt32) -> UInt8 {
        UInt8((value32 >> 25) & 0x7F)
    }
    
    /// Scale 32-bit value to 14-bit value (0-16383)
    ///
    /// - Parameter value32: 32-bit value
    /// - Returns: 14-bit scaled value
    public static func scale32To14(_ value32: UInt32) -> UInt16 {
        UInt16((value32 >> 18) & 0x3FFF)
    }
    
    /// Scale normalized value (0.0-1.0) to 32-bit value
    ///
    /// - Parameter normalized: Normalized value between 0.0 and 1.0
    /// - Returns: 32-bit scaled value
    public static func normalizedTo32(_ normalized: Double) -> UInt32 {
        let clamped = max(0.0, min(1.0, normalized))
        return UInt32(clamped * Double(UInt32.max))
    }
    
    /// Scale 32-bit value to normalized value (0.0-1.0)
    ///
    /// - Parameter value32: 32-bit value
    /// - Returns: Normalized value between 0.0 and 1.0
    public static func to32Normalized(_ value32: UInt32) -> Double {
        Double(value32) / Double(UInt32.max)
    }
    
    /// Scale 7-bit velocity to 16-bit velocity
    ///
    /// - Parameter velocity7: 7-bit velocity (0-127)
    /// - Returns: 16-bit velocity
    public static func scaleVelocity7To16(_ velocity7: UInt8) -> UInt16 {
        // Upper 7 bits of 16-bit value
        UInt16(velocity7 & 0x7F) << 9
    }
    
    /// Scale 16-bit velocity to 7-bit velocity
    ///
    /// - Parameter velocity16: 16-bit velocity
    /// - Returns: 7-bit velocity (0-127)
    public static func scaleVelocity16To7(_ velocity16: UInt16) -> UInt8 {
        UInt8((velocity16 >> 9) & 0x7F)
    }
}

// MARK: - Pitch Bend Constants

/// MIDI 2.0 Pitch Bend constants
public enum PitchBendValue {
    /// Minimum (full down) - 32-bit
    public static let minimum: UInt32 = 0x00000000
    
    /// Center (no bend) - 32-bit
    public static let center: UInt32 = 0x80000000
    
    /// Maximum (full up) - 32-bit
    public static let maximum: UInt32 = 0xFFFFFFFF
    
    /// Minimum (full down) - 14-bit MIDI 1.0
    public static let minimum14: UInt16 = 0x0000
    
    /// Center (no bend) - 14-bit MIDI 1.0
    public static let center14: UInt16 = 0x2000
    
    /// Maximum (full up) - 14-bit MIDI 1.0
    public static let maximum14: UInt16 = 0x3FFF
}

// MARK: - Program Change Bank

/// Bank selection for MIDI 2.0 Program Change
public struct ProgramBank: Sendable, Hashable {
    /// Bank MSB (CC 0)
    public let msb: UInt8
    
    /// Bank LSB (CC 32)
    public let lsb: UInt8
    
    public init(msb: UInt8, lsb: UInt8) {
        self.msb = msb & 0x7F
        self.lsb = lsb & 0x7F
    }
    
    /// Combined bank number (MSB * 128 + LSB)
    public var combined: UInt16 {
        UInt16(msb) * 128 + UInt16(lsb)
    }
    
    /// Create from combined bank number
    public init(combined: UInt16) {
        self.msb = UInt8((combined / 128) & 0x7F)
        self.lsb = UInt8((combined % 128) & 0x7F)
    }
}

// MARK: - Registered/Assignable Controller

/// Controller bank and index for RPN/NRPN
public struct ControllerAddress: Sendable, Hashable {
    /// Bank number (0-127)
    public let bank: UInt8
    
    /// Index within bank (0-127)
    public let index: UInt8
    
    public init(bank: UInt8, index: UInt8) {
        self.bank = bank & 0x7F
        self.index = index & 0x7F
    }
}

// MARK: - Common RPN Addresses

/// Well-known RPN (Registered Parameter Number) addresses
public enum RegisteredController {
    /// Pitch Bend Sensitivity (Bank 0, Index 0)
    public static let pitchBendSensitivity = ControllerAddress(bank: 0, index: 0)
    
    /// Channel Fine Tuning (Bank 0, Index 1)
    public static let channelFineTuning = ControllerAddress(bank: 0, index: 1)
    
    /// Channel Coarse Tuning (Bank 0, Index 2)
    public static let channelCoarseTuning = ControllerAddress(bank: 0, index: 2)
    
    /// Tuning Program Change (Bank 0, Index 3)
    public static let tuningProgramChange = ControllerAddress(bank: 0, index: 3)
    
    /// Tuning Bank Select (Bank 0, Index 4)
    public static let tuningBankSelect = ControllerAddress(bank: 0, index: 4)
    
    /// Modulation Depth Range (Bank 0, Index 5)
    public static let modulationDepthRange = ControllerAddress(bank: 0, index: 5)
    
    /// MPE Configuration (Bank 0, Index 6)
    public static let mpeConfiguration = ControllerAddress(bank: 0, index: 6)
}
