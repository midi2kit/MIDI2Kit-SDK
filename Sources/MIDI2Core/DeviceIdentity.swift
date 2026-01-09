//
//  DeviceIdentity.swift
//  MIDI2Kit
//
//  Device Identity from MIDI-CI Discovery
//

import Foundation

/// Manufacturer ID as defined in MIDI specification
public enum ManufacturerID: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Standard 1-byte manufacturer ID (0x01-0x7F)
    case standard(UInt8)
    
    /// Extended 3-byte manufacturer ID (0x00, byte1, byte2)
    case extended(UInt8, UInt8)
    
    // MARK: - Known Manufacturers
    
    public static let sequential = ManufacturerID.standard(0x01)
    public static let moogMusic = ManufacturerID.standard(0x04)
    public static let oberheim = ManufacturerID.standard(0x10)
    public static let roland = ManufacturerID.standard(0x41)
    public static let korg = ManufacturerID.standard(0x42)
    public static let yamaha = ManufacturerID.standard(0x43)
    public static let casio = ManufacturerID.standard(0x44)
    public static let akai = ManufacturerID.standard(0x47)
    
    // Extended IDs
    public static let nativeInstruments = ManufacturerID.extended(0x00, 0x21)
    public static let ableton = ManufacturerID.extended(0x00, 0x77)
    
    // MARK: - Initialization from bytes
    
    /// Create from SysEx bytes
    /// - Parameter bytes: 3 bytes as transmitted
    public init(bytes: (UInt8, UInt8, UInt8)) {
        if bytes.0 == 0x00 {
            // Extended 3-byte ID
            self = .extended(bytes.1, bytes.2)
        } else {
            // Standard 1-byte ID (ignore remaining bytes)
            self = .standard(bytes.0)
        }
    }
    
    /// Create from byte array
    public init?(from bytes: [UInt8], offset: Int = 0) {
        guard bytes.count >= offset + 3 else { return nil }
        self.init(bytes: (bytes[offset], bytes[offset + 1], bytes[offset + 2]))
    }
    
    // MARK: - Serialization
    
    /// Convert to 3 bytes for SysEx transmission
    public var bytes: [UInt8] {
        switch self {
        case .standard(let id):
            return [id, 0x00, 0x00]
        case .extended(let byte1, let byte2):
            return [0x00, byte1, byte2]
        }
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        switch self {
        case .standard(let id):
            return String(format: "0x%02X", id)
        case .extended(let b1, let b2):
            return String(format: "0x00%02X%02X", b1, b2)
        }
    }
    
    /// Human-readable manufacturer name (if known)
    public var name: String? {
        switch self {
        case .standard(0x01): return "Sequential"
        case .standard(0x04): return "Moog Music"
        case .standard(0x10): return "Oberheim"
        case .standard(0x41): return "Roland"
        case .standard(0x42): return "KORG"
        case .standard(0x43): return "Yamaha"
        case .standard(0x44): return "Casio"
        case .standard(0x47): return "Akai"
        case .extended(0x00, 0x21): return "Native Instruments"
        case .extended(0x00, 0x77): return "Ableton"
        default: return nil
        }
    }
}

/// Device Identity as returned in MIDI-CI Discovery Reply
public struct DeviceIdentity: Hashable, Sendable, Codable {
    
    /// Manufacturer ID
    public let manufacturerID: ManufacturerID
    
    /// Device family (16-bit, LSB first in SysEx)
    public let familyID: UInt16
    
    /// Model number within family (16-bit, LSB first in SysEx)
    public let modelID: UInt16
    
    /// Software/firmware version (32-bit, LSB first in SysEx)
    public let versionID: UInt32
    
    // MARK: - Initialization
    
    public init(
        manufacturerID: ManufacturerID,
        familyID: UInt16,
        modelID: UInt16,
        versionID: UInt32
    ) {
        self.manufacturerID = manufacturerID
        self.familyID = familyID
        self.modelID = modelID
        self.versionID = versionID
    }
    
    /// Create from SysEx bytes (11 bytes total)
    /// Layout: [mfr0, mfr1, mfr2, famL, famH, modL, modH, verLL, verLH, verHL, verHH]
    public init?(from bytes: [UInt8], offset: Int = 0) {
        guard bytes.count >= offset + 11 else { return nil }
        
        let i = offset
        self.manufacturerID = ManufacturerID(bytes: (bytes[i], bytes[i+1], bytes[i+2]))
        self.familyID = UInt16(bytes[i+3]) | (UInt16(bytes[i+4]) << 8)
        self.modelID = UInt16(bytes[i+5]) | (UInt16(bytes[i+6]) << 8)
        self.versionID = UInt32(bytes[i+7])
            | (UInt32(bytes[i+8]) << 8)
            | (UInt32(bytes[i+9]) << 16)
            | (UInt32(bytes[i+10]) << 24)
    }
    
    // MARK: - Serialization
    
    /// Convert to 11 bytes for SysEx transmission
    public var bytes: [UInt8] {
        var result = manufacturerID.bytes
        result.append(UInt8(familyID & 0xFF))
        result.append(UInt8((familyID >> 8) & 0xFF))
        result.append(UInt8(modelID & 0xFF))
        result.append(UInt8((modelID >> 8) & 0xFF))
        result.append(UInt8(versionID & 0xFF))
        result.append(UInt8((versionID >> 8) & 0xFF))
        result.append(UInt8((versionID >> 16) & 0xFF))
        result.append(UInt8((versionID >> 24) & 0xFF))
        return result
    }
    
    // MARK: - Convenience
    
    /// Version as string (e.g., "1.2.3.4")
    public var versionString: String {
        let v0 = (versionID >> 24) & 0xFF
        let v1 = (versionID >> 16) & 0xFF
        let v2 = (versionID >> 8) & 0xFF
        let v3 = versionID & 0xFF
        return "\(v0).\(v1).\(v2).\(v3)"
    }
}

extension DeviceIdentity: CustomStringConvertible {
    public var description: String {
        let mfrName = manufacturerID.name ?? manufacturerID.description
        return "\(mfrName) Family:\(familyID) Model:\(modelID) Ver:\(versionString)"
    }
}
