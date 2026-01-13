//
//  UMPMessage.swift
//  MIDI2Kit
//
//  Type-safe MIDI 2.0 Universal MIDI Packet (UMP) messages
//

import Foundation

// MARK: - UMP Channel

/// MIDI Channel (0-15)
public struct UMPChannel: Sendable, Hashable, ExpressibleByIntegerLiteral {
    public let value: UInt8
    
    public init(_ value: UInt8) {
        self.value = value & 0x0F
    }
    
    public init(integerLiteral value: UInt8) {
        self.init(value)
    }
    
    public static let channel1: UMPChannel = 0
    public static let channel2: UMPChannel = 1
    // ... etc, but 0-indexed internally
}

// MARK: - UMP Protocol

/// Protocol for all UMP messages
public protocol UMPMessage: Sendable {
    /// Message type
    var messageType: UMPMessageType { get }
    
    /// Group (0-15)
    var group: UMPGroup { get }
    
    /// Convert to raw UMP bytes
    func toBytes() -> [UInt8]
    
    /// Size in 32-bit words
    var wordCount: Int { get }
}

// MARK: - MIDI 2.0 Channel Voice Messages

/// MIDI 2.0 Channel Voice Message (64-bit)
public enum UMPMIDI2ChannelVoice: UMPMessage, Sendable {
    
    /// Note Off with velocity
    case noteOff(group: UMPGroup, channel: UMPChannel, note: UInt8, velocity: UInt16, attributeType: UInt8 = 0, attribute: UInt16 = 0)
    
    /// Note On with velocity
    case noteOn(group: UMPGroup, channel: UMPChannel, note: UInt8, velocity: UInt16, attributeType: UInt8 = 0, attribute: UInt16 = 0)
    
    /// Polyphonic Key Pressure (Aftertouch)
    case polyPressure(group: UMPGroup, channel: UMPChannel, note: UInt8, pressure: UInt32)
    
    /// Control Change (high-resolution 32-bit value)
    case controlChange(group: UMPGroup, channel: UMPChannel, controller: UInt8, value: UInt32)
    
    /// Program Change with bank select
    case programChange(group: UMPGroup, channel: UMPChannel, program: UInt8, bankValid: Bool = false, bankMSB: UInt8 = 0, bankLSB: UInt8 = 0)
    
    /// Channel Pressure (Aftertouch)
    case channelPressure(group: UMPGroup, channel: UMPChannel, pressure: UInt32)
    
    /// Pitch Bend (high-resolution 32-bit value)
    case pitchBend(group: UMPGroup, channel: UMPChannel, value: UInt32)
    
    /// Per-Note Pitch Bend
    case perNotePitchBend(group: UMPGroup, channel: UMPChannel, note: UInt8, value: UInt32)
    
    /// Registered Per-Note Controller
    case registeredPerNoteController(group: UMPGroup, channel: UMPChannel, note: UInt8, controller: UInt8, value: UInt32)
    
    /// Assignable Per-Note Controller
    case assignablePerNoteController(group: UMPGroup, channel: UMPChannel, note: UInt8, controller: UInt8, value: UInt32)
    
    /// Per-Note Management
    case perNoteManagement(group: UMPGroup, channel: UMPChannel, note: UInt8, flags: UInt8)
    
    /// Registered Controller (RPN)
    case registeredController(group: UMPGroup, channel: UMPChannel, bank: UInt8, index: UInt8, value: UInt32)
    
    /// Assignable Controller (NRPN)
    case assignableController(group: UMPGroup, channel: UMPChannel, bank: UInt8, index: UInt8, value: UInt32)
    
    /// Relative Registered Controller
    case relativeRegisteredController(group: UMPGroup, channel: UMPChannel, bank: UInt8, index: UInt8, value: Int32)
    
    /// Relative Assignable Controller
    case relativeAssignableController(group: UMPGroup, channel: UMPChannel, bank: UInt8, index: UInt8, value: Int32)
    
    // MARK: - UMPMessage Protocol
    
    public var messageType: UMPMessageType { .midi2ChannelVoice }
    
    public var group: UMPGroup {
        switch self {
        case .noteOff(let g, _, _, _, _, _): return g
        case .noteOn(let g, _, _, _, _, _): return g
        case .polyPressure(let g, _, _, _): return g
        case .controlChange(let g, _, _, _): return g
        case .programChange(let g, _, _, _, _, _): return g
        case .channelPressure(let g, _, _): return g
        case .pitchBend(let g, _, _): return g
        case .perNotePitchBend(let g, _, _, _): return g
        case .registeredPerNoteController(let g, _, _, _, _): return g
        case .assignablePerNoteController(let g, _, _, _, _): return g
        case .perNoteManagement(let g, _, _, _): return g
        case .registeredController(let g, _, _, _, _): return g
        case .assignableController(let g, _, _, _, _): return g
        case .relativeRegisteredController(let g, _, _, _, _): return g
        case .relativeAssignableController(let g, _, _, _, _): return g
        }
    }
    
    public var wordCount: Int { 2 }
    
    public func toBytes() -> [UInt8] {
        let words = toWords()
        var bytes: [UInt8] = []
        bytes.reserveCapacity(8)
        for word in words {
            bytes.append(UInt8((word >> 24) & 0xFF))
            bytes.append(UInt8((word >> 16) & 0xFF))
            bytes.append(UInt8((word >> 8) & 0xFF))
            bytes.append(UInt8(word & 0xFF))
        }
        return bytes
    }
    
    /// Convert to 32-bit words
    public func toWords() -> [UInt32] {
        switch self {
        case .noteOff(let group, let channel, let note, let velocity, let attrType, let attr):
            let word1 = makeHeader(status: 0x80, group: group, channel: channel, byte3: note, byte4: attrType)
            let word2 = (UInt32(velocity) << 16) | UInt32(attr)
            return [word1, word2]
            
        case .noteOn(let group, let channel, let note, let velocity, let attrType, let attr):
            let word1 = makeHeader(status: 0x90, group: group, channel: channel, byte3: note, byte4: attrType)
            let word2 = (UInt32(velocity) << 16) | UInt32(attr)
            return [word1, word2]
            
        case .polyPressure(let group, let channel, let note, let pressure):
            let word1 = makeHeader(status: 0xA0, group: group, channel: channel, byte3: note, byte4: 0)
            return [word1, pressure]
            
        case .controlChange(let group, let channel, let controller, let value):
            let word1 = makeHeader(status: 0xB0, group: group, channel: channel, byte3: controller, byte4: 0)
            return [word1, value]
            
        case .programChange(let group, let channel, let program, let bankValid, let bankMSB, let bankLSB):
            let options: UInt8 = bankValid ? 0x01 : 0x00
            let word1 = makeHeader(status: 0xC0, group: group, channel: channel, byte3: options, byte4: 0)
            let word2 = (UInt32(program) << 24) | (UInt32(bankMSB) << 8) | UInt32(bankLSB)
            return [word1, word2]
            
        case .channelPressure(let group, let channel, let pressure):
            let word1 = makeHeader(status: 0xD0, group: group, channel: channel, byte3: 0, byte4: 0)
            return [word1, pressure]
            
        case .pitchBend(let group, let channel, let value):
            let word1 = makeHeader(status: 0xE0, group: group, channel: channel, byte3: 0, byte4: 0)
            return [word1, value]
            
        case .perNotePitchBend(let group, let channel, let note, let value):
            let word1 = makeHeader(status: 0x60, group: group, channel: channel, byte3: note, byte4: 0)
            return [word1, value]
            
        case .registeredPerNoteController(let group, let channel, let note, let controller, let value):
            let word1 = makeHeader(status: 0x00, group: group, channel: channel, byte3: note, byte4: controller)
            return [word1, value]
            
        case .assignablePerNoteController(let group, let channel, let note, let controller, let value):
            let word1 = makeHeader(status: 0x10, group: group, channel: channel, byte3: note, byte4: controller)
            return [word1, value]
            
        case .perNoteManagement(let group, let channel, let note, let flags):
            let word1 = makeHeader(status: 0xF0, group: group, channel: channel, byte3: note, byte4: flags)
            return [word1, 0]
            
        case .registeredController(let group, let channel, let bank, let index, let value):
            let word1 = makeHeader(status: 0x20, group: group, channel: channel, byte3: bank, byte4: index)
            return [word1, value]
            
        case .assignableController(let group, let channel, let bank, let index, let value):
            let word1 = makeHeader(status: 0x30, group: group, channel: channel, byte3: bank, byte4: index)
            return [word1, value]
            
        case .relativeRegisteredController(let group, let channel, let bank, let index, let value):
            let word1 = makeHeader(status: 0x40, group: group, channel: channel, byte3: bank, byte4: index)
            return [word1, UInt32(bitPattern: value)]
            
        case .relativeAssignableController(let group, let channel, let bank, let index, let value):
            let word1 = makeHeader(status: 0x50, group: group, channel: channel, byte3: bank, byte4: index)
            return [word1, UInt32(bitPattern: value)]
        }
    }
    
    private func makeHeader(status: UInt8, group: UMPGroup, channel: UMPChannel, byte3: UInt8, byte4: UInt8) -> UInt32 {
        let mt = UInt32(UMPMessageType.midi2ChannelVoice.rawValue) << 28
        let grp = UInt32(group.rawValue) << 24
        let sts = UInt32(status | channel.value) << 16
        let b3 = UInt32(byte3) << 8
        let b4 = UInt32(byte4)
        return mt | grp | sts | b3 | b4
    }
}
