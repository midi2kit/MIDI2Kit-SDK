//
//  ZlibMcoded7Tests.swift
//  MIDI2Kit
//
//  Tests for zlib + Mcoded7 encoding
//

import Testing
import Foundation
@testable import MIDI2Core

@Suite("ZlibMcoded7 Tests")
struct ZlibMcoded7Tests {

    // MARK: - Basic Encoding/Decoding

    @Test("Empty data returns empty")
    func emptyData() {
        let encoded = ZlibMcoded7.encode(Data())
        #expect(encoded == Data())

        let decoded = ZlibMcoded7.decode(Data())
        #expect(decoded == Data())
    }

    @Test("Round-trip preserves data")
    func roundTrip() {
        let original = "Hello, MIDI 2.0 Property Exchange!".data(using: .utf8)!

        guard let encoded = ZlibMcoded7.encode(original) else {
            Issue.record("Encoding failed")
            return
        }

        guard let decoded = ZlibMcoded7.decode(encoded) else {
            Issue.record("Decoding failed")
            return
        }

        #expect(decoded == original)
    }

    @Test("Round-trip with binary data")
    func roundTripBinary() {
        // Binary data with all byte values
        var original = Data()
        for i: UInt8 in 0...255 {
            original.append(i)
        }

        guard let encoded = ZlibMcoded7.encode(original) else {
            Issue.record("Encoding failed")
            return
        }

        guard let decoded = ZlibMcoded7.decode(encoded) else {
            Issue.record("Decoding failed")
            return
        }

        #expect(decoded == original)
    }

    @Test("Round-trip with large compressible data")
    func roundTripLarge() {
        // Large JSON-like data that compresses well
        let repeatedData = String(repeating: "{\"key\": \"value\", \"number\": 12345},", count: 100)
        let original = repeatedData.data(using: .utf8)!

        guard let encoded = ZlibMcoded7.encode(original) else {
            Issue.record("Encoding failed")
            return
        }

        guard let decoded = ZlibMcoded7.decode(encoded) else {
            Issue.record("Decoding failed")
            return
        }

        #expect(decoded == original)
        // Compression should be beneficial for repetitive data
        #expect(encoded.count < original.count)
    }

    // MARK: - Compression Effectiveness

    @Test("Compression reduces size for compressible data")
    func compressionEffective() {
        // Highly compressible data
        let original = String(repeating: "AAAA", count: 500).data(using: .utf8)!

        guard let (_, stats) = ZlibMcoded7.encodeWithStats(original) else {
            Issue.record("Encoding failed")
            return
        }

        #expect(stats.compressionRatio > 5.0, "Expected significant compression")
        #expect(stats.isBeneficial, "Compression should be beneficial")
    }

    @Test("Random data may not compress well")
    func randomDataCompression() {
        // Random data doesn't compress well
        var random = Data(count: 1000)
        random.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            for i in 0..<1000 {
                ptr[i] = UInt8.random(in: 0...255)
            }
        }

        guard let (_, stats) = ZlibMcoded7.encodeWithStats(random) else {
            Issue.record("Encoding failed")
            return
        }

        // Random data typically has compression ratio close to 1 or worse
        #expect(stats.compressionRatio < 2.0, "Random data should not compress well")
    }

    // MARK: - Fallback Behavior

    @Test("Fallback uses compression for large compressible data")
    func fallbackCompresses() {
        let original = String(repeating: "ResourceList entry,", count: 200).data(using: .utf8)!

        let (encoded, wasCompressed) = ZlibMcoded7.encodeWithFallback(original)

        #expect(wasCompressed, "Should use compression for compressible data")
        #expect(encoded.count < Mcoded7.encode(original).count)
    }

    @Test("Fallback skips compression for small data")
    func fallbackSmallData() {
        let original = "Small".data(using: .utf8)!

        let (encoded, wasCompressed) = ZlibMcoded7.encodeWithFallback(original)

        #expect(!wasCompressed, "Should not compress small data")
        #expect(encoded == Mcoded7.encode(original))
    }

    // MARK: - Edge Cases

    @Test("Single byte round-trip")
    func singleByte() {
        for byte: UInt8 in [0x00, 0x7F, 0x80, 0xFF] {
            let original = Data([byte])

            guard let encoded = ZlibMcoded7.encode(original) else {
                Issue.record("Encoding failed for byte \(byte)")
                continue
            }

            guard let decoded = ZlibMcoded7.decode(encoded) else {
                Issue.record("Decoding failed for byte \(byte)")
                continue
            }

            #expect(decoded == original, "Failed for byte \(byte)")
        }
    }

    @Test("Encoded data is 7-bit safe")
    func encodedIs7BitSafe() {
        let original = Data([0x80, 0xFF, 0xAB, 0xCD, 0xEF])

        guard let encoded = ZlibMcoded7.encode(original) else {
            Issue.record("Encoding failed")
            return
        }

        // All bytes in encoded data should have MSB clear
        for byte in encoded {
            #expect(byte <= 0x7F, "Encoded byte 0x\(String(format: "%02X", byte)) is not 7-bit safe")
        }
    }

    @Test("Invalid encoded data returns nil")
    func invalidData() {
        // Invalid Mcoded7 (has MSB set)
        let invalidMcoded7 = Data([0x80, 0x41, 0x42])
        #expect(ZlibMcoded7.decode(invalidMcoded7) == nil)

        // Valid Mcoded7 but invalid zlib
        let validMcoded7InvalidZlib = Mcoded7.encode(Data([0x00, 0x01, 0x02]))
        #expect(ZlibMcoded7.decode(validMcoded7InvalidZlib) == nil)
    }

    // MARK: - Statistics

    @Test("Statistics are accurate")
    func statisticsAccurate() {
        let original = String(repeating: "Test data for compression ", count: 50).data(using: .utf8)!

        guard let (_, stats) = ZlibMcoded7.encodeWithStats(original) else {
            Issue.record("Encoding failed")
            return
        }

        #expect(stats.originalSize == original.count)
        #expect(stats.compressedSize > 0)
        #expect(stats.encodedSize > 0)
        #expect(stats.compressionRatio > 1.0, "Repetitive data should compress")
        #expect(stats.overallRatio > 0)
    }

    // MARK: - Real-World Scenarios

    @Test("JSON resource list compression")
    func jsonResourceList() {
        // Simulate a typical PE ResourceList response
        let resourceList = """
        [
            {"resource": "DeviceInfo", "canGet": true, "canSet": false},
            {"resource": "ResourceList", "canGet": true, "canSet": false},
            {"resource": "ProgramList", "canGet": true, "canSet": false, "canPaginate": true},
            {"resource": "ChannelList", "canGet": true, "canSet": false},
            {"resource": "CMList", "canGet": true, "canSet": false}
        ]
        """.data(using: .utf8)!

        guard let (encoded, stats) = ZlibMcoded7.encodeWithStats(resourceList) else {
            Issue.record("Encoding failed")
            return
        }

        guard let decoded = ZlibMcoded7.decode(encoded) else {
            Issue.record("Decoding failed")
            return
        }

        #expect(decoded == resourceList)
        #expect(stats.isBeneficial, "JSON should compress well")
    }

    @Test("Minimum size threshold is reasonable")
    func minimumSizeThreshold() {
        // The minimum size threshold should be set reasonably
        #expect(ZlibMcoded7.minimumSizeForCompression >= 64)
        #expect(ZlibMcoded7.minimumSizeForCompression <= 1024)
    }
}
