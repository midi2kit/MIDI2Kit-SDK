//
//  MUIDTests.swift
//  MIDI2Kit
//
//  Tests for MUID type
//

import Testing
@testable import MIDI2Core

@Suite("MUID Tests")
struct MUIDTests {
    
    @Test("Random MUID generation")
    func randomGeneration() {
        let muid1 = MUID.random()
        let muid2 = MUID.random()
        
        #expect(muid1 != muid2)
        #expect(!muid1.isBroadcast)
        #expect(!muid1.isReserved)
        #expect(muid1.value <= 0x0FFF_FFFE)
    }
    
    @Test("Broadcast MUID")
    func broadcast() {
        let broadcast = MUID.broadcast
        
        #expect(broadcast.value == 0x0FFF_FFFF)
        #expect(broadcast.isBroadcast)
        #expect(!broadcast.isReserved)
    }
    
    @Test("Reserved MUID")
    func reserved() {
        let reserved = MUID.reserved
        
        #expect(reserved.value == 0x0000_0000)
        #expect(!reserved.isBroadcast)
        #expect(reserved.isReserved)
    }
    
    @Test("MUID from bytes")
    func fromBytes() {
        // 4 x 7-bit bytes, LSB first
        // Value: 0x00 | (0x01 << 7) | (0x02 << 14) | (0x03 << 21)
        //      = 0x00 + 0x80 + 0x8000 + 0x600000 = 0x608080
        let muid = MUID(bytes: (0x00, 0x01, 0x02, 0x03))
        
        #expect(muid.value == 0x0060_8080)
    }
    
    @Test("MUID to bytes round-trip")
    func bytesRoundTrip() {
        let original = MUID.random()
        let bytes = original.bytes
        let restored = MUID(from: bytes, offset: 0)
        
        #expect(restored != nil)
        #expect(restored == original)
    }
    
    @Test("Invalid raw value rejected")
    func invalidRawValue() {
        let invalid = MUID(rawValue: 0x1000_0000)  // > 28 bits
        #expect(invalid == nil)
    }
    
    @Test("MUID from byte array")
    func fromByteArray() {
        // Broadcast MUID = 0x0FFFFFFF
        // As 4 x 7-bit bytes: [0x7F, 0x7F, 0x7F, 0x7F]
        let bytes: [UInt8] = [0x7F, 0x7F, 0x7F, 0x7F]
        let muid = MUID(from: bytes)
        
        #expect(muid != nil)
        #expect(muid == MUID.broadcast)
    }
    
    @Test("MUID from byte array with offset")
    func fromByteArrayWithOffset() {
        let bytes: [UInt8] = [0xAA, 0xBB, 0x12, 0x34, 0x56, 0x78, 0xCC]
        let muid = MUID(from: bytes, offset: 2)

        #expect(muid != nil)
        let expected = UInt32(0x12) | (UInt32(0x34) << 7) | (UInt32(0x56) << 14) | (UInt32(0x78) << 21)
        #expect(muid?.value == expected)
    }
    
    @Test("MUID insufficient bytes returns nil")
    func insufficientBytes() {
        let bytes: [UInt8] = [0x01, 0x02, 0x03]  // Only 3 bytes
        let muid = MUID(from: bytes)
        
        #expect(muid == nil)
    }
}
