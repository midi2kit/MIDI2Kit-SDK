//
//  MUID.swift
//  MIDI2Kit
//
//  MIDI Unique Identifier (28-bit)
//

import Foundation

/// MIDI Unique Identifier - 28-bit value used in MIDI-CI
///
/// Valid range: 0x0000_0000 - 0x0FFF_FFFE
/// Broadcast: 0x0FFF_FFFF
public struct MUID: Hashable, Sendable, CustomStringConvertible, Codable {
    
    /// Raw 28-bit value (stored in lower 28 bits of UInt32)
    public let value: UInt32
    
    /// Broadcast MUID - targets all devices
    public static let broadcast = MUID(rawValue: 0x0FFF_FFFF)!
    
    /// Reserved/Invalid MUID
    public static let reserved = MUID(rawValue: 0x0000_0000)!
    
    // MARK: - Initialization
    
    /// Create MUID from raw 28-bit value
    /// - Parameter rawValue: Value must be in range 0x0000_0000 - 0x0FFF_FFFF
    public init?(rawValue: UInt32) {
        guard rawValue <= 0x0FFF_FFFF else { return nil }
        self.value = rawValue
    }
    
    /// Create MUID from 4 bytes (7-bit each, as transmitted in SysEx)
    /// - Parameter bytes: 4 bytes, each with MSB clear (0x00-0x7F)
    public init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
        // MIDI-CI transmits MUID as 4 x 7-bit bytes, LSB first
        self.value = UInt32(bytes.0 & 0x7F)
            | (UInt32(bytes.1 & 0x7F) << 7)
            | (UInt32(bytes.2 & 0x7F) << 14)
            | (UInt32(bytes.3 & 0x7F) << 21)
    }
    
    /// Create MUID from byte array (at least 4 bytes)
    public init?(from bytes: [UInt8], offset: Int = 0) {
        guard bytes.count >= offset + 4 else { return nil }
        self.init(bytes: (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]))
    }
    
    /// Generate a random valid MUID
    public static func random() -> MUID {
        // Avoid broadcast (0x0FFFFFFF) and reserved (0x00000000)
        let value = UInt32.random(in: 0x0000_0001...0x0FFF_FFFE)
        return MUID(rawValue: value)!
    }
    
    // MARK: - Serialization
    
    /// Convert to 4 bytes for SysEx transmission (7-bit each, LSB first)
    public var bytes: [UInt8] {
        [
            UInt8(value & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 21) & 0x7F)
        ]
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        String(format: "MUID(0x%07X)", value)
    }
    
    // MARK: - Convenience
    
    /// Check if this is the broadcast MUID
    public var isBroadcast: Bool {
        value == 0x0FFF_FFFF
    }
    
    /// Check if this is the reserved/invalid MUID
    public var isReserved: Bool {
        value == 0x0000_0000
    }
}

// MARK: - Equatable by value

extension MUID: Equatable {
    public static func == (lhs: MUID, rhs: MUID) -> Bool {
        lhs.value == rhs.value
    }
}

// MARK: - Identifiable

extension MUID: Identifiable {
    public var id: UInt32 { value }
}
