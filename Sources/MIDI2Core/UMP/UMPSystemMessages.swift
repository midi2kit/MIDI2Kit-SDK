//
//  UMPSystemMessages.swift
//  MIDI2Kit
//
//  System Real Time and System Common Messages in UMP format
//

import Foundation

// MARK: - System Real Time Messages

/// System Real Time Messages (32-bit UMP)
public enum UMPSystemRealTime: UMPMessage, Sendable {
    /// Timing Clock
    case timingClock(group: UMPGroup)
    
    /// Start
    case start(group: UMPGroup)
    
    /// Continue
    case `continue`(group: UMPGroup)
    
    /// Stop
    case stop(group: UMPGroup)
    
    /// Active Sensing
    case activeSensing(group: UMPGroup)
    
    /// System Reset
    case systemReset(group: UMPGroup)
    
    // MARK: - UMPMessage Protocol
    
    public var messageType: UMPMessageType { .systemRealTime }
    
    public var group: UMPGroup {
        switch self {
        case .timingClock(let g): return g
        case .start(let g): return g
        case .continue(let g): return g
        case .stop(let g): return g
        case .activeSensing(let g): return g
        case .systemReset(let g): return g
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
        let status: UInt8
        switch self {
        case .timingClock: status = 0xF8
        case .start: status = 0xFA
        case .continue: status = 0xFB
        case .stop: status = 0xFC
        case .activeSensing: status = 0xFE
        case .systemReset: status = 0xFF
        }
        
        let mt = UInt32(UMPMessageType.systemRealTime.rawValue) << 28
        let grp = UInt32(group.value) << 24
        let sts = UInt32(status) << 16
        return mt | grp | sts
    }
}

// MARK: - System Common Messages

/// System Common Messages (32-bit UMP)
public enum UMPSystemCommon: UMPMessage, Sendable {
    /// MIDI Time Code Quarter Frame
    case mtcQuarterFrame(group: UMPGroup, data: UInt8)
    
    /// Song Position Pointer (14-bit value)
    case songPosition(group: UMPGroup, position: UInt16)
    
    /// Song Select
    case songSelect(group: UMPGroup, song: UInt8)
    
    /// Tune Request
    case tuneRequest(group: UMPGroup)
    
    // MARK: - UMPMessage Protocol
    
    public var messageType: UMPMessageType { .systemRealTime }
    
    public var group: UMPGroup {
        switch self {
        case .mtcQuarterFrame(let g, _): return g
        case .songPosition(let g, _): return g
        case .songSelect(let g, _): return g
        case .tuneRequest(let g): return g
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
        let mt = UInt32(UMPMessageType.systemRealTime.rawValue) << 28
        let grp = UInt32(group.value) << 24
        
        switch self {
        case .mtcQuarterFrame(_, let data):
            let sts = UInt32(0xF1) << 16
            let d1 = UInt32(data & 0x7F) << 8
            return mt | grp | sts | d1
            
        case .songPosition(_, let position):
            let sts = UInt32(0xF2) << 16
            let lsb = UInt32(position & 0x7F) << 8
            let msb = UInt32((position >> 7) & 0x7F)
            return mt | grp | sts | lsb | msb
            
        case .songSelect(_, let song):
            let sts = UInt32(0xF3) << 16
            let d1 = UInt32(song & 0x7F) << 8
            return mt | grp | sts | d1
            
        case .tuneRequest:
            let sts = UInt32(0xF6) << 16
            return mt | grp | sts
        }
    }
}

// MARK: - Utility Messages

/// Utility Messages (32-bit UMP)
public enum UMPUtility: UMPMessage, Sendable {
    /// No Operation
    case noop(group: UMPGroup)
    
    /// JR Clock (Jitter Reduction Clock)
    case jrClock(group: UMPGroup, timestamp: UInt16)
    
    /// JR Timestamp
    case jrTimestamp(group: UMPGroup, timestamp: UInt16)
    
    // MARK: - UMPMessage Protocol
    
    public var messageType: UMPMessageType { .utility }
    
    public var group: UMPGroup {
        switch self {
        case .noop(let g): return g
        case .jrClock(let g, _): return g
        case .jrTimestamp(let g, _): return g
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
        let mt = UInt32(UMPMessageType.utility.rawValue) << 28
        let grp = UInt32(group.value) << 24
        
        switch self {
        case .noop:
            return mt | grp | (0x00 << 20)
            
        case .jrClock(_, let timestamp):
            return mt | grp | (0x01 << 20) | UInt32(timestamp)
            
        case .jrTimestamp(_, let timestamp):
            return mt | grp | (0x02 << 20) | UInt32(timestamp)
        }
    }
}
