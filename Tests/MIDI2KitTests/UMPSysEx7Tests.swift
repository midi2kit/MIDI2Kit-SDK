//
//  UMPSysEx7Tests.swift
//  MIDI2Kit
//
//  Tests for SysEx7 (Data 64) bidirectional conversion and UMPSysEx7Assembler
//

import Testing
import Foundation
@testable import MIDI2Core

@Suite("SysEx7 (Data 64) Tests")
struct UMPSysEx7Tests {

    // MARK: - SysEx7Status

    @Test("SysEx7Status raw values")
    func sysEx7StatusRawValues() {
        #expect(SysEx7Status.complete.rawValue == 0x0)
        #expect(SysEx7Status.start.rawValue == 0x1)
        #expect(SysEx7Status.continue.rawValue == 0x2)
        #expect(SysEx7Status.end.rawValue == 0x3)
    }

    // MARK: - UMPBuilder.data64

    @Test("Build and parse Data 64 roundtrip")
    func buildParseRoundtrip() {
        let data: [UInt8] = [0x7E, 0x7F, 0x09, 0x01]
        let words = UMPBuilder.data64(group: 0, status: SysEx7Status.complete.rawValue, numBytes: 4, data: data)

        #expect(words.count == 2)

        let parsed = UMPParser.parse(words)
        guard case .data64(let group, let status, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }

        #expect(group == 0)
        #expect(status == SysEx7Status.complete.rawValue)
        #expect(bytes == [0x7E, 0x7F, 0x09, 0x01])
    }

    @Test("Build Data 64 with 6 bytes (full packet)")
    func buildData64FullPacket() {
        let data: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
        let words = UMPBuilder.data64(group: 2, status: SysEx7Status.complete.rawValue, numBytes: 6, data: data)

        let parsed = UMPParser.parse(words)
        guard case .data64(let group, let status, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }

        #expect(group == 2)
        #expect(status == SysEx7Status.complete.rawValue)
        #expect(bytes == data)
    }

    @Test("Build Data 64 with 0 bytes (empty)")
    func buildData64EmptyPacket() {
        let words = UMPBuilder.data64(group: 0, status: SysEx7Status.complete.rawValue, numBytes: 0, data: [])

        let parsed = UMPParser.parse(words)
        guard case .data64(_, _, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }

        #expect(bytes.isEmpty)
    }

    @Test("parseData64 respects numBytes field")
    func parseData64NumBytes() {
        // Build a packet with numBytes=3 but data positions 4-6 non-zero
        let word0: UInt32 = UInt32(UMPMessageType.data64.rawValue) << 28 |
                             UInt32(0) << 24 |              // group 0
                             UInt32(0) << 20 |              // complete
                             UInt32(3) << 16 |              // numBytes = 3
                             UInt32(0x10) << 8 |            // data[0]
                             UInt32(0x20)                    // data[1]
        let word1: UInt32 = UInt32(0x30) << 24 |            // data[2]
                             UInt32(0xFF) << 16 |            // data[3] (should be excluded)
                             UInt32(0xFF) << 8 |             // data[4] (should be excluded)
                             UInt32(0xFF)                    // data[5] (should be excluded)

        let parsed = UMPParser.parse([word0, word1])
        guard case .data64(_, _, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }

        #expect(bytes.count == 3)
        #expect(bytes == [0x10, 0x20, 0x30])
    }

    // MARK: - fromMIDI1SysEx (MIDI 1.0 → UMP)

    @Test("Short SysEx (<=6 payload bytes) generates single Complete packet")
    func shortSysExComplete() {
        // Identity Request: F0 7E 7F 06 01 F7
        let sysex: [UInt8] = [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]
        let packets = UMPTranslator.fromMIDI1SysEx(sysex, group: 0)

        #expect(packets.count == 1)

        let parsed = UMPParser.parse(packets[0])
        guard case .data64(_, let status, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }

        #expect(status == SysEx7Status.complete.rawValue)
        #expect(bytes == [0x7E, 0x7F, 0x06, 0x01])
    }

    @Test("Empty SysEx returns empty packets")
    func emptySysEx() {
        let packets = UMPTranslator.fromMIDI1SysEx([], group: 0)
        #expect(packets.isEmpty)
    }

    @Test("SysEx with only F0 F7 generates Complete with 0 bytes")
    func minimalSysEx() {
        let packets = UMPTranslator.fromMIDI1SysEx([0xF0, 0xF7], group: 0)
        #expect(packets.count == 1)

        let parsed = UMPParser.parse(packets[0])
        guard case .data64(_, let status, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }
        #expect(status == SysEx7Status.complete.rawValue)
        #expect(bytes.isEmpty)
    }

    @Test("SysEx with exactly 6 payload bytes generates single Complete packet")
    func sysExExactly6Bytes() {
        let payload: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
        let sysex: [UInt8] = [0xF0] + payload + [0xF7]
        let packets = UMPTranslator.fromMIDI1SysEx(sysex, group: 0)

        #expect(packets.count == 1)

        let parsed = UMPParser.parse(packets[0])
        guard case .data64(_, let status, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }
        #expect(status == SysEx7Status.complete.rawValue)
        #expect(bytes == payload)
    }

    @Test("SysEx with 7 payload bytes generates Start + End")
    func sysEx7BytesSplitInTwo() {
        let payload: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]
        let sysex: [UInt8] = [0xF0] + payload + [0xF7]
        let packets = UMPTranslator.fromMIDI1SysEx(sysex, group: 0)

        #expect(packets.count == 2)

        // First packet: Start with 6 bytes
        let p0 = UMPParser.parse(packets[0])
        guard case .data64(_, let status0, let bytes0) = p0 else {
            Issue.record("Expected data64 message")
            return
        }
        #expect(status0 == SysEx7Status.start.rawValue)
        #expect(bytes0.count == 6)

        // Second packet: End with 1 byte
        let p1 = UMPParser.parse(packets[1])
        guard case .data64(_, let status1, let bytes1) = p1 else {
            Issue.record("Expected data64 message")
            return
        }
        #expect(status1 == SysEx7Status.end.rawValue)
        #expect(bytes1.count == 1)
        #expect(bytes1[0] == 0x07)
    }

    @Test("Large SysEx (100 bytes) generates correct packet count")
    func largeSysEx100Bytes() {
        let payload = [UInt8](repeating: 0x55, count: 100)
        let sysex: [UInt8] = [0xF0] + payload + [0xF7]
        let packets = UMPTranslator.fromMIDI1SysEx(sysex, group: 0)

        // 100 bytes / 6 bytes per packet = 16.67 → 17 packets
        // Start(6) + 15*Continue(6) + End(4) = 6 + 90 + 4 = 100
        #expect(packets.count == 17)

        // Verify first is Start
        if case .data64(_, let s0, _) = UMPParser.parse(packets[0]) {
            #expect(s0 == SysEx7Status.start.rawValue)
        }

        // Verify middle packets are Continue
        for i in 1..<16 {
            if case .data64(_, let s, _) = UMPParser.parse(packets[i]) {
                #expect(s == SysEx7Status.continue.rawValue, "Packet \(i) should be Continue")
            }
        }

        // Verify last is End
        if case .data64(_, let sLast, let bytesLast) = UMPParser.parse(packets[16]) {
            #expect(sLast == SysEx7Status.end.rawValue)
            #expect(bytesLast.count == 4)
        }
    }

    @Test("SysEx without F0/F7 framing works correctly")
    func sysExWithoutFraming() {
        let payload: [UInt8] = [0x7E, 0x7F, 0x06, 0x01]
        let packets = UMPTranslator.fromMIDI1SysEx(payload, group: 0)

        #expect(packets.count == 1)

        let parsed = UMPParser.parse(packets[0])
        guard case .data64(_, _, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }
        #expect(bytes == payload)
    }

    @Test("SysEx preserves group assignment")
    func sysExGroupAssignment() {
        let payload: [UInt8] = [0xF0, 0x7E, 0x7F, 0xF7]
        let packets = UMPTranslator.fromMIDI1SysEx(payload, group: UMPGroup(rawValue: 5))

        let parsed = UMPParser.parse(packets[0])
        guard case .data64(let group, _, _) = parsed else {
            Issue.record("Expected data64 message")
            return
        }
        #expect(group == 5)
    }

    // MARK: - data64ToMIDI1SysEx (UMP → MIDI 1.0, Complete only)

    @Test("Complete Data 64 to MIDI 1.0 SysEx")
    func data64CompleteToMIDI1() {
        let words = UMPBuilder.data64(
            group: 0,
            status: SysEx7Status.complete.rawValue,
            numBytes: 3,
            data: [0x7E, 0x7F, 0x01]
        )
        let parsed = UMPParser.parse(words)!
        let result = UMPTranslator.data64ToMIDI1SysEx(parsed)

        #expect(result == [0xF0, 0x7E, 0x7F, 0x01, 0xF7])
    }

    @Test("Non-Complete Data 64 returns nil")
    func data64NonCompleteReturnsNil() {
        let words = UMPBuilder.data64(
            group: 0,
            status: SysEx7Status.start.rawValue,
            numBytes: 3,
            data: [0x01, 0x02, 0x03]
        )
        let parsed = UMPParser.parse(words)!
        #expect(UMPTranslator.data64ToMIDI1SysEx(parsed) == nil)
    }

    @Test("Non-data64 message returns nil")
    func nonData64ReturnsNil() {
        let parsed = ParsedUMPMessage.midi1ChannelVoice(ParsedMIDI1ChannelVoice(
            group: 0, statusByte: 0x90, channel: 0, data1: 60, data2: 100
        ))
        #expect(UMPTranslator.data64ToMIDI1SysEx(parsed) == nil)
    }

    // MARK: - UMPSysEx7Assembler

    @Test("Assembler: Complete packet returns immediately")
    func assemblerComplete() async {
        let assembler = UMPSysEx7Assembler()
        let result = await assembler.process(group: 0, status: SysEx7Status.complete.rawValue, bytes: [0x7E, 0x7F])
        #expect(result == [0xF0, 0x7E, 0x7F, 0xF7])
    }

    @Test("Assembler: Start + End")
    func assemblerStartEnd() async {
        let assembler = UMPSysEx7Assembler()

        let r1 = await assembler.process(group: 0, status: SysEx7Status.start.rawValue, bytes: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        #expect(r1 == nil)

        let r2 = await assembler.process(group: 0, status: SysEx7Status.end.rawValue, bytes: [0x07])
        #expect(r2 == [0xF0, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0xF7])
    }

    @Test("Assembler: Start + Continue + End")
    func assemblerStartContinueEnd() async {
        let assembler = UMPSysEx7Assembler()

        let r1 = await assembler.process(group: 0, status: SysEx7Status.start.rawValue, bytes: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        #expect(r1 == nil)

        let r2 = await assembler.process(group: 0, status: SysEx7Status.continue.rawValue, bytes: [0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C])
        #expect(r2 == nil)

        let r3 = await assembler.process(group: 0, status: SysEx7Status.end.rawValue, bytes: [0x0D])
        #expect(r3 == [0xF0, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0xF7])
    }

    @Test("Assembler: Continue without Start returns nil")
    func assemblerContinueWithoutStart() async {
        let assembler = UMPSysEx7Assembler()
        let result = await assembler.process(group: 0, status: SysEx7Status.continue.rawValue, bytes: [0x01])
        #expect(result == nil)
    }

    @Test("Assembler: End without Start returns nil")
    func assemblerEndWithoutStart() async {
        let assembler = UMPSysEx7Assembler()
        let result = await assembler.process(group: 0, status: SysEx7Status.end.rawValue, bytes: [0x01])
        #expect(result == nil)
    }

    @Test("Assembler: Groups are independent")
    func assemblerGroupIndependence() async {
        let assembler = UMPSysEx7Assembler()

        // Start on group 0
        _ = await assembler.process(group: 0, status: SysEx7Status.start.rawValue, bytes: [0xAA])

        // Start on group 1
        _ = await assembler.process(group: 1, status: SysEx7Status.start.rawValue, bytes: [0xBB])

        // End on group 1
        let r1 = await assembler.process(group: 1, status: SysEx7Status.end.rawValue, bytes: [0xCC])
        #expect(r1 == [0xF0, 0xBB, 0xCC, 0xF7])

        // End on group 0
        let r0 = await assembler.process(group: 0, status: SysEx7Status.end.rawValue, bytes: [0xDD])
        #expect(r0 == [0xF0, 0xAA, 0xDD, 0xF7])
    }

    @Test("Assembler: Buffer overflow protection")
    func assemblerBufferOverflow() async {
        let assembler = UMPSysEx7Assembler(maxBufferSize: 10)

        _ = await assembler.process(group: 0, status: SysEx7Status.start.rawValue, bytes: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06])

        // This would exceed 10 bytes
        let r = await assembler.process(group: 0, status: SysEx7Status.continue.rawValue, bytes: [0x07, 0x08, 0x09, 0x0A, 0x0B])
        #expect(r == nil)

        // End should also return nil since buffer was discarded
        let rEnd = await assembler.process(group: 0, status: SysEx7Status.end.rawValue, bytes: [0x0C])
        #expect(rEnd == nil)
    }

    @Test("Assembler: New Start discards previous incomplete")
    func assemblerNewStartDiscardsOld() async {
        let assembler = UMPSysEx7Assembler()

        _ = await assembler.process(group: 0, status: SysEx7Status.start.rawValue, bytes: [0xAA, 0xBB])

        // New Start replaces the old one
        _ = await assembler.process(group: 0, status: SysEx7Status.start.rawValue, bytes: [0xCC, 0xDD])

        let result = await assembler.process(group: 0, status: SysEx7Status.end.rawValue, bytes: [0xEE])
        #expect(result == [0xF0, 0xCC, 0xDD, 0xEE, 0xF7])
    }

    @Test("Assembler: Reset clears all buffers")
    func assemblerReset() async {
        let assembler = UMPSysEx7Assembler()

        _ = await assembler.process(group: 0, status: SysEx7Status.start.rawValue, bytes: [0x01])
        _ = await assembler.process(group: 1, status: SysEx7Status.start.rawValue, bytes: [0x02])

        await assembler.reset()

        // End on both groups should return nil (buffers cleared)
        let r0 = await assembler.process(group: 0, status: SysEx7Status.end.rawValue, bytes: [0x03])
        let r1 = await assembler.process(group: 1, status: SysEx7Status.end.rawValue, bytes: [0x04])
        #expect(r0 == nil)
        #expect(r1 == nil)
    }

    // MARK: - Full Roundtrip

    @Test("Full roundtrip: MIDI 1.0 → Data 64 → Assembler → MIDI 1.0")
    func fullRoundtrip() async {
        let originalSysEx: [UInt8] = [0xF0, 0x7E, 0x7F, 0x09, 0x01, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0xF7]

        // MIDI 1.0 → UMP packets
        let packets = UMPTranslator.fromMIDI1SysEx(originalSysEx, group: 3)

        // UMP packets → Assembler → MIDI 1.0
        let assembler = UMPSysEx7Assembler()
        var reassembled: [UInt8]? = nil

        for packet in packets {
            let parsed = UMPParser.parse(packet)
            guard case .data64(let group, let status, let bytes) = parsed else {
                Issue.record("Expected data64 message")
                return
            }
            #expect(group == 3)
            if let result = await assembler.process(group: group, status: status, bytes: bytes) {
                reassembled = result
            }
        }

        // Should match original
        #expect(reassembled == originalSysEx)
    }

    @Test("Short roundtrip: Complete packet via Assembler")
    func shortRoundtrip() async {
        let originalSysEx: [UInt8] = [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]

        let packets = UMPTranslator.fromMIDI1SysEx(originalSysEx, group: 0)
        #expect(packets.count == 1)

        let assembler = UMPSysEx7Assembler()
        let parsed = UMPParser.parse(packets[0])
        guard case .data64(let group, let status, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }

        let result = await assembler.process(group: group, status: status, bytes: bytes)
        #expect(result == originalSysEx)
    }

    // MARK: - UMP.sysEx7 Factory

    @Test("UMP.sysEx7.complete with valid payload")
    func umpSysEx7Complete() {
        let packet = UMP.sysEx7.complete(payload: [0x7E, 0x7F, 0x06])
        #expect(packet != nil)
        #expect(packet!.count == 2)

        let parsed = UMPParser.parse(packet!)
        guard case .data64(_, let status, let bytes) = parsed else {
            Issue.record("Expected data64 message")
            return
        }
        #expect(status == SysEx7Status.complete.rawValue)
        #expect(bytes == [0x7E, 0x7F, 0x06])
    }

    @Test("UMP.sysEx7.complete with oversized payload returns nil")
    func umpSysEx7CompleteTooLarge() {
        let packet = UMP.sysEx7.complete(payload: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        #expect(packet == nil)
    }

    @Test("UMP.sysEx7.fromMIDI1 delegates to UMPTranslator")
    func umpSysEx7FromMIDI1() {
        let packets = UMP.sysEx7.fromMIDI1(bytes: [0xF0, 0x7E, 0x7F, 0xF7])
        let direct = UMPTranslator.fromMIDI1SysEx([0xF0, 0x7E, 0x7F, 0xF7], group: 0)

        #expect(packets.count == direct.count)
        for i in 0..<packets.count {
            #expect(packets[i] == direct[i])
        }
    }
}
