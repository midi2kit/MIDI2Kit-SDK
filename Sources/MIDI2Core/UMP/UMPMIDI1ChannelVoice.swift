//
//  UMPMIDI1ChannelVoice.swift
//  MIDI2Kit
//
//  MIDI 1.0 Channel Voice Messages in UMP format (32-bit)
//

import Foundation

// MARK: - MIDI 1.0 Channel Voice Messages

/// MIDI 1.0 Channel Voice Message (32-bit UMP)
public enum UMPMIDI1ChannelVoice: UMPMessage, Sendable {
    
    /// Note Off
    case noteOff(group: UMPGroup, channel: UMPChannel, note: UInt8, velocity: UInt8)
    
    /// Note On
    case noteOn(group: UMPGroup, channel: UMPChannel, note: UInt8, velocity: UInt8)
    
    /// Polyphonic Key Pressure (Aftertouch)
    case polyPressure(group: UMPGroup, channel: UMPChannel, note: UInt8, pressure: UInt8)
    
    /// Control Change
    case controlChange(group: UMPGroup, channel: UMPChannel, controller: UInt8, value: UInt8)
    
    /// Program Change
    case programChange(group: UMPGroup, channel: UMPChannel, program: UInt8)
    
    /// Channel Pressure (Aftertouch)
    case channelPressure(group: UMPGroup, channel: UMPChannel, pressure: UInt8)
    
    /// Pitch Bend (14-bit value: 0-16383, center = 8192)
    case pitchBend(group: UMPGroup, channel: UMPChannel, value: UInt16)
    
    // MARK: - UMPMessage Protocol
    
    public var messageType: UMPMessageType { .midi1ChannelVoice }
    
    public var group: UMPGroup {
        switch self {
        case .noteOff(let g, _, _, _): return g
        case .noteOn(let g, _, _, _): return g
        case .polyPressure(let g, _, _, _): return g
        case .controlChange(let g, _, _, _): return g
        case .programChange(let g, _, _): return g
        case .channelPressure(let g, _, _): return g
        case .pitchBend(let g, _, _): return g
        }
    }
    
    public var wordCount: Int { 1 }
    
    public func toBytes() -> [UInt8] {
        let word = toWord()
        return [
            UInt8((word >> 24) & 0xFF),
            UInt8((word >> 16) & 0xFF),
            UInt8((word >> 8) & 0xFF),
            UInt8(word & 0xFF)
        ]
    }
    
    /// Convert to 32-bit word
    public func toWord() -> UInt32 {
        switch self {
        case .noteOff(let group, let channel, let note, let velocity):
            return makeWord(group: group, status: 0x80 | channel.value, data1: note, data2: velocity)
            
        case .noteOn(let group, let channel, let note, let velocity):
            return makeWord(group: group, status: 0x90 | channel.value, data1: note, data2: velocity)
            
        case .polyPressure(let group, let channel, let note, let pressure):
            return makeWord(group: group, status: 0xA0 | channel.value, data1: note, data2: pressure)
            
        case .controlChange(let group, let channel, let controller, let value):
            return makeWord(group: group, status: 0xB0 | channel.value, data1: controller, data2: value)
            
        case .programChange(let group, let channel, let program):
            return makeWord(group: group, status: 0xC0 | channel.value, data1: program, data2: 0)
            
        case .channelPressure(let group, let channel, let pressure):
            return makeWord(group: group, status: 0xD0 | channel.value, data1: pressure, data2: 0)
            
        case .pitchBend(let group, let channel, let value):
            let lsb = UInt8(value & 0x7F)
            let msb = UInt8((value >> 7) & 0x7F)
            return makeWord(group: group, status: 0xE0 | channel.value, data1: lsb, data2: msb)
        }
    }
    
    private func makeWord(group: UMPGroup, status: UInt8, data1: UInt8, data2: UInt8) -> UInt32 {
        let mt = UInt32(UMPMessageType.midi1ChannelVoice.rawValue) << 28
        let grp = UInt32(group.rawValue) << 24
        let sts = UInt32(status) << 16
        let d1 = UInt32(data1 & 0x7F) << 8
        let d2 = UInt32(data2 & 0x7F)
        return mt | grp | sts | d1 | d2
    }
}

// MARK: - Common Control Change Numbers

extension UMPMIDI1ChannelVoice {
    /// Bank Select MSB (CC 0)
    public static func bankSelectMSB(group: UMPGroup = 0, channel: UMPChannel, value: UInt8) -> Self {
        .controlChange(group: group, channel: channel, controller: 0, value: value)
    }
    
    /// Modulation Wheel (CC 1)
    public static func modulation(group: UMPGroup = 0, channel: UMPChannel, value: UInt8) -> Self {
        .controlChange(group: group, channel: channel, controller: 1, value: value)
    }
    
    /// Breath Controller (CC 2)
    public static func breath(group: UMPGroup = 0, channel: UMPChannel, value: UInt8) -> Self {
        .controlChange(group: group, channel: channel, controller: 2, value: value)
    }
    
    /// Foot Controller (CC 4)
    public static func foot(group: UMPGroup = 0, channel: UMPChannel, value: UInt8) -> Self {
        .controlChange(group: group, channel: channel, controller: 4, value: value)
    }
    
    /// Volume (CC 7)
    public static func volume(group: UMPGroup = 0, channel: UMPChannel, value: UInt8) -> Self {
        .controlChange(group: group, channel: channel, controller: 7, value: value)
    }
    
    /// Pan (CC 10)
    public static func pan(group: UMPGroup = 0, channel: UMPChannel, value: UInt8) -> Self {
        .controlChange(group: group, channel: channel, controller: 10, value: value)
    }
    
    /// Expression (CC 11)
    public static func expression(group: UMPGroup = 0, channel: UMPChannel, value: UInt8) -> Self {
        .controlChange(group: group, channel: channel, controller: 11, value: value)
    }
    
    /// Bank Select LSB (CC 32)
    public static func bankSelectLSB(group: UMPGroup = 0, channel: UMPChannel, value: UInt8) -> Self {
        .controlChange(group: group, channel: channel, controller: 32, value: value)
    }
    
    /// Sustain Pedal (CC 64)
    public static func sustain(group: UMPGroup = 0, channel: UMPChannel, on: Bool) -> Self {
        .controlChange(group: group, channel: channel, controller: 64, value: on ? 127 : 0)
    }
    
    /// All Sound Off (CC 120)
    public static func allSoundOff(group: UMPGroup = 0, channel: UMPChannel) -> Self {
        .controlChange(group: group, channel: channel, controller: 120, value: 0)
    }
    
    /// Reset All Controllers (CC 121)
    public static func resetAllControllers(group: UMPGroup = 0, channel: UMPChannel) -> Self {
        .controlChange(group: group, channel: channel, controller: 121, value: 0)
    }
    
    /// All Notes Off (CC 123)
    public static func allNotesOff(group: UMPGroup = 0, channel: UMPChannel) -> Self {
        .controlChange(group: group, channel: channel, controller: 123, value: 0)
    }
}
