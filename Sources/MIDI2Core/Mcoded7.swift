//
//  Mcoded7.swift
//  MIDI2Kit
//
//  Mcoded7 Encoding/Decoding for 8-bit data over 7-bit SysEx
//

import Foundation

/// Mcoded7 encoding/decoding for transmitting 8-bit data over 7-bit MIDI SysEx
///
/// MIDI SysEx data bytes must have MSB clear (0x00-0x7F).
/// Mcoded7 encodes arbitrary 8-bit data by grouping 7 bytes and
/// prepending a "high bits" byte containing the MSBs.
///
/// Encoding: Every 7 source bytes become 8 transmitted bytes
/// - Byte 0: MSBs of next 7 bytes (bit 6 = MSB of byte 1, bit 0 = MSB of byte 7)
/// - Bytes 1-7: Low 7 bits of source bytes
///
/// Reference: MIDI-CI 1.2 Specification, Section 5.10
public enum Mcoded7 {
    
    /// Encode 8-bit data to 7-bit safe Mcoded7 format
    /// - Parameter data: Original 8-bit data
    /// - Returns: Mcoded7 encoded data (always 7-bit safe)
    public static func encode(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        
        var result = Data()
        result.reserveCapacity((data.count * 8 + 6) / 7)
        
        var index = 0
        while index < data.count {
            let remaining = data.count - index
            let groupSize = min(7, remaining)
            
            // Calculate high bits byte
            var highBits: UInt8 = 0
            for i in 0..<groupSize {
                if data[index + i] & 0x80 != 0 {
                    highBits |= (1 << (6 - i))
                }
            }
            
            result.append(highBits)
            
            // Append low 7 bits of each byte
            for i in 0..<groupSize {
                result.append(data[index + i] & 0x7F)
            }
            
            index += groupSize
        }
        
        return result
    }
    
    /// Decode Mcoded7 format back to original 8-bit data
    /// - Parameter data: Mcoded7 encoded data
    /// - Returns: Decoded 8-bit data, or nil if invalid format
    public static func decode(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        
        var result = Data()
        
        var index = 0
        while index < data.count {
            // Read high bits byte
            let highBits = data[index]
            index += 1
            
            // Determine group size (up to 7 data bytes follow)
            let remaining = data.count - index
            let groupSize = min(7, remaining)
            
            guard groupSize > 0 else { break }
            
            // Reconstruct original bytes
            for i in 0..<groupSize {
                let lowBits = data[index + i]
                
                // Validate: data bytes should have MSB clear
                guard lowBits <= 0x7F else { return nil }
                
                // Reconstruct: MSB from high bits, low 7 bits from data byte
                let msb: UInt8 = (highBits >> (6 - i)) & 0x01
                let originalByte = (msb << 7) | lowBits
                result.append(originalByte)
            }
            
            index += groupSize
        }
        
        return result
    }
    
    /// Calculate encoded size for given input size
    /// - Parameter originalSize: Size of original 8-bit data
    /// - Returns: Size after Mcoded7 encoding
    public static func encodedSize(for originalSize: Int) -> Int {
        guard originalSize > 0 else { return 0 }
        // Every 7 bytes become 8 bytes
        let fullGroups = originalSize / 7
        let remainder = originalSize % 7
        return fullGroups * 8 + (remainder > 0 ? remainder + 1 : 0)
    }
    
    /// Calculate decoded size for given encoded size
    /// - Parameter encodedSize: Size of Mcoded7 encoded data
    /// - Returns: Approximate size after decoding (may vary by 1-6 bytes)
    public static func decodedSize(for encodedSize: Int) -> Int {
        guard encodedSize > 0 else { return 0 }
        // Every 8 bytes become 7 bytes
        let fullGroups = encodedSize / 8
        let remainder = encodedSize % 8
        return fullGroups * 7 + max(0, remainder - 1)
    }
}
