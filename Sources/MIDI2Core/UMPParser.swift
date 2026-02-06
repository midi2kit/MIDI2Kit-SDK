//
//  UMPParser.swift
//  MIDI2Kit
//
//  MIDI 2.0 Universal MIDI Packet message parser
//

import Foundation

// MARK: - Parsed UMP Messages

/// Parsed MIDI 2.0 Channel Voice message
public struct ParsedMIDI2ChannelVoice: Sendable, Equatable {
    public let group: UInt8
    public let status: MIDI2ChannelVoiceStatus
    public let channel: UInt8
    public let index: UInt8
    public let extra: UInt8
    public let data: UInt32
    
    public init(
        group: UInt8,
        status: MIDI2ChannelVoiceStatus,
        channel: UInt8,
        index: UInt8,
        extra: UInt8,
        data: UInt32
    ) {
        self.group = group
        self.status = status
        self.channel = channel
        self.index = index
        self.extra = extra
        self.data = data
    }
}

/// Parsed MIDI 1.0 Channel Voice message (from UMP)
public struct ParsedMIDI1ChannelVoice: Sendable, Equatable {
    public let group: UInt8
    public let statusByte: UInt8
    public let channel: UInt8
    public let data1: UInt8
    public let data2: UInt8
    
    /// Status nibble (upper 4 bits of status byte)
    public var statusNibble: UInt8 {
        (statusByte >> 4) & 0x0F
    }
    
    public init(
        group: UInt8,
        statusByte: UInt8,
        channel: UInt8,
        data1: UInt8,
        data2: UInt8
    ) {
        self.group = group
        self.statusByte = statusByte
        self.channel = channel
        self.data1 = data1
        self.data2 = data2
    }
}

/// Parsed UMP message types
public enum ParsedUMPMessage: Sendable, Equatable {
    /// Utility message (NOOP, JR Clock, JR Timestamp)
    case utility(group: UInt8, status: UInt8, data: UInt16)
    
    /// System message (Real Time, Common)
    case system(group: UInt8, statusByte: UInt8, data1: UInt8, data2: UInt8)
    
    /// MIDI 1.0 Channel Voice (wrapped in UMP)
    case midi1ChannelVoice(ParsedMIDI1ChannelVoice)
    
    /// MIDI 2.0 Channel Voice
    case midi2ChannelVoice(ParsedMIDI2ChannelVoice)
    
    /// Data 64-bit message (SysEx7)
    case data64(group: UInt8, status: UInt8, bytes: [UInt8])
    
    /// Data 128-bit message (SysEx8, Mixed Data Set)
    case data128(group: UInt8, status: UInt8, bytes: [UInt8])
    
    /// Unknown or unsupported message type
    case unknown(words: [UInt32])
}

// MARK: - UMP Parser

/// Parser for MIDI 2.0 Universal MIDI Packet messages
///
/// Provides methods to parse UMP words into structured message types.
///
/// ## Usage Example
///
/// ```swift
/// let words: [UInt32] = [0x40903C00, 0xC0000000]
/// if let message = UMPParser.parse(words) {
///     switch message {
///     case .midi2ChannelVoice(let cv):
///         print("Note On: \(cv.index) velocity: \(cv.data >> 16)")
///     default:
///         break
///     }
/// }
/// ```
public enum UMPParser {
    
    // MARK: - Main Parser
    
    /// Parse UMP words into a structured message
    ///
    /// - Parameter words: Array of 32-bit UMP words
    /// - Returns: Parsed message, or nil if invalid
    public static func parse(_ words: [UInt32]) -> ParsedUMPMessage? {
        guard !words.isEmpty else { return nil }
        
        let word0 = words[0]
        let messageType = UInt8((word0 >> 28) & 0x0F)
        
        guard let mt = UMPMessageType(rawValue: messageType) else {
            return .unknown(words: words)
        }
        
        // Validate word count
        guard words.count >= mt.wordCount else {
            return nil
        }
        
        switch mt {
        case .utility:
            return parseUtility(word0)
            
        case .system:
            return parseSystem(word0)
            
        case .midi1ChannelVoice:
            return parseMIDI1ChannelVoice(word0)
            
        case .data64:
            return parseData64(words)
            
        case .midi2ChannelVoice:
            return parseMIDI2ChannelVoice(words)
            
        case .data128, .flexData, .umpStream:
            return parseData128(words)
        }
    }
    
    /// Extract message type from first word
    ///
    /// - Parameter word0: First UMP word
    /// - Returns: Message type, or nil if invalid
    public static func messageType(from word0: UInt32) -> UMPMessageType? {
        let mt = UInt8((word0 >> 28) & 0x0F)
        return UMPMessageType(rawValue: mt)
    }
    
    /// Extract group from first word
    ///
    /// - Parameter word0: First UMP word
    /// - Returns: UMP group (0-15)
    public static func group(from word0: UInt32) -> UInt8 {
        UInt8((word0 >> 24) & 0x0F)
    }
    
    // MARK: - Specific Parsers
    
    private static func parseUtility(_ word0: UInt32) -> ParsedUMPMessage {
        let group = UInt8((word0 >> 24) & 0x0F)
        let status = UInt8((word0 >> 20) & 0x0F)
        let data = UInt16(word0 & 0xFFFF)
        return .utility(group: group, status: status, data: data)
    }
    
    private static func parseSystem(_ word0: UInt32) -> ParsedUMPMessage {
        let group = UInt8((word0 >> 24) & 0x0F)
        let statusByte = UInt8((word0 >> 16) & 0xFF)
        let data1 = UInt8((word0 >> 8) & 0x7F)
        let data2 = UInt8(word0 & 0x7F)
        return .system(group: group, statusByte: statusByte, data1: data1, data2: data2)
    }
    
    private static func parseMIDI1ChannelVoice(_ word0: UInt32) -> ParsedUMPMessage {
        let group = UInt8((word0 >> 24) & 0x0F)
        let statusByte = UInt8((word0 >> 16) & 0xFF)
        let channel = statusByte & 0x0F
        let data1 = UInt8((word0 >> 8) & 0x7F)
        let data2 = UInt8(word0 & 0x7F)
        
        let parsed = ParsedMIDI1ChannelVoice(
            group: group,
            statusByte: statusByte,
            channel: channel,
            data1: data1,
            data2: data2
        )
        return .midi1ChannelVoice(parsed)
    }
    
    private static func parseMIDI2ChannelVoice(_ words: [UInt32]) -> ParsedUMPMessage {
        guard words.count >= 2 else { return .unknown(words: words) }
        
        let word0 = words[0]
        let word1 = words[1]
        
        let group = UInt8((word0 >> 24) & 0x0F)
        let statusNibble = UInt8((word0 >> 20) & 0x0F)
        let channel = UInt8((word0 >> 16) & 0x0F)
        let index = UInt8((word0 >> 8) & 0xFF)
        let extra = UInt8(word0 & 0xFF)
        
        guard let status = MIDI2ChannelVoiceStatus(rawValue: statusNibble) else {
            return .unknown(words: words)
        }
        
        let parsed = ParsedMIDI2ChannelVoice(
            group: group,
            status: status,
            channel: channel,
            index: index,
            extra: extra,
            data: word1
        )
        return .midi2ChannelVoice(parsed)
    }
    
    private static func parseData64(_ words: [UInt32]) -> ParsedUMPMessage {
        guard words.count >= 2 else { return .unknown(words: words) }

        let word0 = words[0]
        let word1 = words[1]

        let group = UInt8((word0 >> 24) & 0x0F)
        let status = UInt8((word0 >> 20) & 0x0F)
        let numBytes = Int((word0 >> 16) & 0x0F)

        // Extract all 6 data bytes from remaining bits
        var bytes: [UInt8] = []

        // Word 0: bits 15-0 (2 bytes)
        bytes.append(UInt8((word0 >> 8) & 0xFF))
        bytes.append(UInt8(word0 & 0xFF))

        // Word 1: all 4 bytes
        bytes.append(UInt8((word1 >> 24) & 0xFF))
        bytes.append(UInt8((word1 >> 16) & 0xFF))
        bytes.append(UInt8((word1 >> 8) & 0xFF))
        bytes.append(UInt8(word1 & 0xFF))

        // Trim to actual number of valid bytes (numBytes field, 0-6)
        let validCount = min(numBytes, 6)
        return .data64(group: group, status: status, bytes: Array(bytes.prefix(validCount)))
    }
    
    private static func parseData128(_ words: [UInt32]) -> ParsedUMPMessage {
        guard words.count >= 4 else { return .unknown(words: words) }
        
        let word0 = words[0]
        let group = UInt8((word0 >> 24) & 0x0F)
        let status = UInt8((word0 >> 20) & 0x0F)
        
        // Extract bytes from all words
        var bytes: [UInt8] = []
        
        // Word 0: bits 15-0 (2 bytes)
        bytes.append(UInt8((word0 >> 8) & 0xFF))
        bytes.append(UInt8(word0 & 0xFF))
        
        // Words 1-3: all 4 bytes each
        for i in 1..<4 {
            let word = words[i]
            bytes.append(UInt8((word >> 24) & 0xFF))
            bytes.append(UInt8((word >> 16) & 0xFF))
            bytes.append(UInt8((word >> 8) & 0xFF))
            bytes.append(UInt8(word & 0xFF))
        }
        
        return .data128(group: group, status: status, bytes: bytes)
    }
}

// MARK: - Convenience Extensions for Parsed Messages

extension ParsedMIDI2ChannelVoice {
    
    /// For Note On/Off: note number
    public var noteNumber: UInt8 { index }
    
    /// For Note On/Off: 16-bit velocity (upper 16 bits of data)
    public var velocity16: UInt16 { UInt16(data >> 16) }
    
    /// For Note On/Off: 7-bit velocity (scaled down)
    public var velocity7: UInt8 { UMPValueScaling.scaleVelocity16To7(velocity16) }
    
    /// For Note On/Off: attribute data (lower 16 bits of data)
    public var attributeData: UInt16 { UInt16(data & 0xFFFF) }
    
    /// For Note On/Off: attribute type
    public var attributeType: NoteAttributeType? { NoteAttributeType(rawValue: extra) }
    
    /// For Control Change: controller number
    public var controllerNumber: UInt8 { index }
    
    /// For Control Change: 32-bit value
    public var controllerValue32: UInt32 { data }
    
    /// For Control Change: 7-bit value (scaled down)
    public var controllerValue7: UInt8 { UMPValueScaling.scale32To7(data) }
    
    /// For Pitch Bend: 32-bit value
    public var pitchBendValue32: UInt32 { data }
    
    /// For Pitch Bend: 14-bit value (scaled down)
    public var pitchBendValue14: UInt16 { UMPValueScaling.scale32To14(data) }
    
    /// For Program Change: program number
    public var programNumber: UInt8 { UInt8((data >> 24) & 0x7F) }
    
    /// For Program Change: bank valid flag
    public var bankValid: Bool { (data & 0x80000000) != 0 }
    
    /// For Program Change: bank (if valid)
    public var bank: ProgramBank? {
        guard bankValid else { return nil }
        let msb = UInt8((data >> 8) & 0x7F)
        let lsb = UInt8(data & 0x7F)
        return ProgramBank(msb: msb, lsb: lsb)
    }
    
    /// For RPN/NRPN: controller address
    public var controllerAddress: ControllerAddress {
        ControllerAddress(bank: index, index: extra)
    }
    
    /// For Pressure messages: 32-bit pressure value
    public var pressureValue32: UInt32 { data }
    
    /// For Pressure messages: 7-bit pressure value (scaled down)
    public var pressureValue7: UInt8 { UMPValueScaling.scale32To7(data) }
}

extension ParsedMIDI1ChannelVoice {
    
    /// Check if this is a Note On message
    public var isNoteOn: Bool { statusNibble == 0x9 }
    
    /// Check if this is a Note Off message
    public var isNoteOff: Bool { statusNibble == 0x8 }
    
    /// Check if this is a Control Change message
    public var isControlChange: Bool { statusNibble == 0xB }
    
    /// Check if this is a Program Change message
    public var isProgramChange: Bool { statusNibble == 0xC }
    
    /// Check if this is a Pitch Bend message
    public var isPitchBend: Bool { statusNibble == 0xE }
    
    /// For Note On/Off: note number
    public var noteNumber: UInt8 { data1 }
    
    /// For Note On/Off: velocity
    public var velocity: UInt8 { data2 }
    
    /// For Control Change: controller number
    public var controllerNumber: UInt8 { data1 }
    
    /// For Control Change: controller value
    public var controllerValue: UInt8 { data2 }
    
    /// For Program Change: program number
    public var programNumber: UInt8 { data1 }
    
    /// For Pitch Bend: 14-bit value
    public var pitchBendValue: UInt16 {
        UInt16(data1) | (UInt16(data2) << 7)
    }
}
