//
//  Mcoded7Tests.swift
//  MIDI2Kit
//
//  Tests for Mcoded7 encoding/decoding
//

import Testing
import Foundation
@testable import MIDI2Core

@Suite("Mcoded7 Tests")
struct Mcoded7Tests {
    
    @Test("Encode empty data")
    func encodeEmpty() {
        let result = Mcoded7.encode(Data())
        #expect(result.isEmpty)
    }
    
    @Test("Decode empty data")
    func decodeEmpty() {
        let result = Mcoded7.decode(Data())
        #expect(result != nil)
        #expect(result?.isEmpty == true)
    }
    
    @Test("Encode 7-bit safe data unchanged")
    func encode7BitSafe() {
        // Data with all MSBs clear
        let input = Data([0x00, 0x01, 0x7F, 0x40, 0x20, 0x10, 0x08])
        let encoded = Mcoded7.encode(input)
        
        // First byte is high bits (all 0), then 7 data bytes
        #expect(encoded.count == 8)
        #expect(encoded[0] == 0x00)  // High bits byte
        #expect(Array(encoded[1...]) == Array(input))
    }
    
    @Test("Encode data with MSB set")
    func encodeMSBSet() {
        // Single byte with MSB set
        let input = Data([0x80])
        let encoded = Mcoded7.encode(input)
        
        // High bits: bit 6 set (MSB of first byte)
        #expect(encoded.count == 2)
        #expect(encoded[0] == 0b0100_0000)  // MSB of byte 1 in bit 6
        #expect(encoded[1] == 0x00)  // Low 7 bits of 0x80
    }
    
    @Test("Encode all 0xFF bytes")
    func encodeAllFF() {
        let input = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        let encoded = Mcoded7.encode(input)
        
        #expect(encoded.count == 8)
        #expect(encoded[0] == 0b0111_1111)  // All 7 MSBs set
        for i in 1..<8 {
            #expect(encoded[i] == 0x7F)  // Low 7 bits of 0xFF
        }
    }
    
    @Test("Round-trip encoding")
    func roundTrip() {
        let input = Data([0x00, 0x7F, 0x80, 0xFF, 0x55, 0xAA, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
        
        let encoded = Mcoded7.encode(input)
        let decoded = Mcoded7.decode(encoded)
        
        #expect(decoded != nil)
        #expect(decoded == input)
    }
    
    @Test("Encoded size calculation")
    func encodedSizeCalculation() {
        // 7 bytes -> 8 bytes
        #expect(Mcoded7.encodedSize(for: 7) == 8)
        
        // 14 bytes -> 16 bytes
        #expect(Mcoded7.encodedSize(for: 14) == 16)
        
        // 1 byte -> 2 bytes
        #expect(Mcoded7.encodedSize(for: 1) == 2)
        
        // 8 bytes -> 10 bytes (7 + 1 in second group)
        #expect(Mcoded7.encodedSize(for: 8) == 10)
        
        // 0 bytes -> 0 bytes
        #expect(Mcoded7.encodedSize(for: 0) == 0)
    }
    
    @Test("Decode invalid data returns nil")
    func decodeInvalidData() {
        // Data byte with MSB set (invalid in Mcoded7)
        let invalid = Data([0x00, 0x80])  // High bits, then invalid data byte
        let result = Mcoded7.decode(invalid)
        
        #expect(result == nil)
    }
    
    @Test("Encode partial group")
    func encodePartialGroup() {
        // 3 bytes (less than 7)
        let input = Data([0x80, 0x81, 0x82])
        let encoded = Mcoded7.encode(input)
        
        // 1 high bits byte + 3 data bytes = 4 bytes
        #expect(encoded.count == 4)
        #expect(encoded[0] == 0b0111_0000)  // MSBs for bytes 1-3 in bits 6-4
    }
    
    @Test("Large data round-trip")
    func largeDataRoundTrip() {
        // Create data with various byte values
        var input = Data()
        for i: UInt8 in 0...255 {
            input.append(i)
        }
        
        let encoded = Mcoded7.encode(input)
        let decoded = Mcoded7.decode(encoded)
        
        #expect(decoded != nil)
        #expect(decoded == input)
    }
}
