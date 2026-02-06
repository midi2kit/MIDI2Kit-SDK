//
//  UMPTranslatorTests.swift
//  MIDI2Kit
//
//  Tests for UMP⇔MIDI1 translation
//

import Testing
import Foundation
@testable import MIDI2Core

@Suite("UMPTranslator Tests")
struct UMPTranslatorTests {

    // MARK: - UMP to MIDI 1.0

    @Test("MIDI 1.0 UMP Note On to MIDI 1.0 bytes")
    func midi1UmpNoteOnToMidi1() {
        let ump = UMPMIDI1ChannelVoice.noteOn(group: 0, channel: 0, note: 60, velocity: 100)
        let bytes = UMPTranslator.toMIDI1(ump)

        #expect(bytes == [0x90, 0x3C, 0x64])
    }

    @Test("MIDI 1.0 UMP Note Off to MIDI 1.0 bytes")
    func midi1UmpNoteOffToMidi1() {
        let ump = UMPMIDI1ChannelVoice.noteOff(group: 0, channel: 5, note: 72, velocity: 64)
        let bytes = UMPTranslator.toMIDI1(ump)

        #expect(bytes == [0x85, 0x48, 0x40])
    }

    @Test("MIDI 1.0 UMP Control Change to MIDI 1.0 bytes")
    func midi1UmpCCToMidi1() {
        let ump = UMPMIDI1ChannelVoice.controlChange(group: 0, channel: 0, controller: 7, value: 100)
        let bytes = UMPTranslator.toMIDI1(ump)

        #expect(bytes == [0xB0, 0x07, 0x64])
    }

    @Test("MIDI 1.0 UMP Program Change to MIDI 1.0 bytes")
    func midi1UmpProgramChangeToMidi1() {
        let ump = UMPMIDI1ChannelVoice.programChange(group: 0, channel: 3, program: 25)
        let bytes = UMPTranslator.toMIDI1(ump)

        #expect(bytes == [0xC3, 0x19])
    }

    @Test("MIDI 1.0 UMP Pitch Bend to MIDI 1.0 bytes")
    func midi1UmpPitchBendToMidi1() {
        // Center value: 8192 = 0x2000
        let ump = UMPMIDI1ChannelVoice.pitchBend(group: 0, channel: 0, value: 8192)
        let bytes = UMPTranslator.toMIDI1(ump)

        // 8192 = 0x2000, LSB = 0x00, MSB = 0x40
        #expect(bytes == [0xE0, 0x00, 0x40])
    }

    @Test("MIDI 2.0 UMP Note On to MIDI 1.0 bytes (downscaled)")
    func midi2UmpNoteOnToMidi1() {
        // MIDI 2.0 velocity 0x8000 (50%) should become ~64 in MIDI 1.0
        let ump = UMPMIDI2ChannelVoice.noteOn(group: 0, channel: 0, note: 60, velocity: 0x8000)
        let bytes = UMPTranslator.toMIDI1(ump)

        #expect(bytes != nil)
        #expect(bytes![0] == 0x90)
        #expect(bytes![1] == 60)
        // 0x8000 >> 9 = 64
        #expect(bytes![2] == 64)
    }

    @Test("MIDI 2.0 UMP Control Change to MIDI 1.0 bytes (downscaled)")
    func midi2UmpCCToMidi1() {
        // MIDI 2.0 CC max value 0xFFFFFFFF should become 127 in MIDI 1.0
        let ump = UMPMIDI2ChannelVoice.controlChange(group: 0, channel: 0, controller: 1, value: 0xFFFFFFFF)
        let bytes = UMPTranslator.toMIDI1(ump)

        #expect(bytes != nil)
        #expect(bytes![0] == 0xB0)
        #expect(bytes![1] == 1)
        #expect(bytes![2] == 127)
    }

    @Test("System Real-Time to MIDI 1.0 bytes")
    func systemRealTimeToMidi1() {
        #expect(UMPTranslator.toMIDI1(UMPSystemRealTime.timingClock(group: 0)) == [0xF8])
        #expect(UMPTranslator.toMIDI1(UMPSystemRealTime.start(group: 0)) == [0xFA])
        #expect(UMPTranslator.toMIDI1(UMPSystemRealTime.continue(group: 0)) == [0xFB])
        #expect(UMPTranslator.toMIDI1(UMPSystemRealTime.stop(group: 0)) == [0xFC])
        #expect(UMPTranslator.toMIDI1(UMPSystemRealTime.activeSensing(group: 0)) == [0xFE])
        #expect(UMPTranslator.toMIDI1(UMPSystemRealTime.systemReset(group: 0)) == [0xFF])
    }

    @Test("System Common to MIDI 1.0 bytes")
    func systemCommonToMidi1() {
        #expect(UMPTranslator.toMIDI1(UMPSystemCommon.songSelect(group: 0, song: 5)) == [0xF3, 0x05])
        #expect(UMPTranslator.toMIDI1(UMPSystemCommon.tuneRequest(group: 0)) == [0xF6])
        #expect(UMPTranslator.toMIDI1(UMPSystemCommon.mtcQuarterFrame(group: 0, data: 0x15)) == [0xF1, 0x15])
    }

    // MARK: - MIDI 1.0 to UMP

    @Test("MIDI 1.0 Note On to UMP")
    func midi1NoteOnToUmp() {
        let bytes: [UInt8] = [0x90, 0x3C, 0x64]  // Note On, C4, velocity 100
        let ump = UMPTranslator.fromMIDI1(bytes, group: 0)

        guard let noteOn = ump as? UMPMIDI1ChannelVoice else {
            Issue.record("Expected UMPMIDI1ChannelVoice")
            return
        }

        if case .noteOn(let group, let channel, let note, let velocity) = noteOn {
            #expect(group.rawValue == 0)
            #expect(channel.value == 0)
            #expect(note == 60)
            #expect(velocity == 100)
        } else {
            Issue.record("Expected noteOn case")
        }
    }

    @Test("MIDI 1.0 Note On with velocity 0 becomes Note Off")
    func midi1NoteOnVelocityZero() {
        let bytes: [UInt8] = [0x90, 0x3C, 0x00]  // Note On, C4, velocity 0
        let ump = UMPTranslator.fromMIDI1(bytes, group: 0)

        guard let noteOff = ump as? UMPMIDI1ChannelVoice else {
            Issue.record("Expected UMPMIDI1ChannelVoice")
            return
        }

        if case .noteOff(_, _, let note, _) = noteOff {
            #expect(note == 60)
        } else {
            Issue.record("Expected noteOff case")
        }
    }

    @Test("MIDI 1.0 Pitch Bend to UMP")
    func midi1PitchBendToUmp() {
        // Center value: LSB=0x00, MSB=0x40 -> 8192
        let bytes: [UInt8] = [0xE0, 0x00, 0x40]
        let ump = UMPTranslator.fromMIDI1(bytes, group: 0)

        guard let pitchBend = ump as? UMPMIDI1ChannelVoice else {
            Issue.record("Expected UMPMIDI1ChannelVoice")
            return
        }

        if case .pitchBend(_, _, let value) = pitchBend {
            #expect(value == 8192)
        } else {
            Issue.record("Expected pitchBend case")
        }
    }

    @Test("MIDI 1.0 System Real-Time to UMP")
    func midi1SystemRealTimeToUmp() {
        #expect(UMPTranslator.fromMIDI1([0xF8], group: 0) is UMPSystemRealTime)
        #expect(UMPTranslator.fromMIDI1([0xFA], group: 0) is UMPSystemRealTime)
        #expect(UMPTranslator.fromMIDI1([0xFC], group: 0) is UMPSystemRealTime)
    }

    // MARK: - MIDI 1.0 to MIDI 2.0 UMP (Upscaled)

    @Test("MIDI 1.0 Note On to MIDI 2.0 UMP (upscaled)")
    func midi1ToMidi2Upscaled() {
        let bytes: [UInt8] = [0x90, 0x3C, 0x64]  // Note On, C4, velocity 100
        let ump = UMPTranslator.fromMIDI1ToMIDI2(bytes, group: 0)

        guard let noteOn = ump else {
            Issue.record("Expected UMPMIDI2ChannelVoice")
            return
        }

        if case .noteOn(_, _, let note, let velocity, _, _) = noteOn {
            #expect(note == 60)
            // 100 -> upscaled 16-bit value
            // 100 << 9 | 100 << 2 | 100 >> 5 = 51200 | 400 | 3 = 0xC8C3
            #expect(velocity == UMPTranslator.upscale7to16(100))
        } else {
            Issue.record("Expected noteOn case")
        }
    }

    @Test("MIDI 1.0 Control Change to MIDI 2.0 UMP (upscaled)")
    func midi1CCToMidi2Upscaled() {
        let bytes: [UInt8] = [0xB0, 0x07, 0x7F]  // CC7 (Volume), value 127
        let ump = UMPTranslator.fromMIDI1ToMIDI2(bytes, group: 0)

        guard let cc = ump else {
            Issue.record("Expected UMPMIDI2ChannelVoice")
            return
        }

        if case .controlChange(_, _, let controller, let value) = cc {
            #expect(controller == 7)
            #expect(value == UMPTranslator.upscale7to32(127))
        } else {
            Issue.record("Expected controlChange case")
        }
    }

    // MARK: - Value Scaling

    @Test("Downscale 16 to 7 bit")
    func downscale16to7() {
        #expect(UMPTranslator.downscale16to7(0x0000) == 0)
        #expect(UMPTranslator.downscale16to7(0x8000) == 64)
        #expect(UMPTranslator.downscale16to7(0xFFFF) == 127)
    }

    @Test("Downscale 32 to 7 bit")
    func downscale32to7() {
        #expect(UMPTranslator.downscale32to7(0x00000000) == 0)
        #expect(UMPTranslator.downscale32to7(0x80000000) == 64)
        #expect(UMPTranslator.downscale32to7(0xFFFFFFFF) == 127)
    }

    @Test("Upscale 7 to 16 bit")
    func upscale7to16() {
        #expect(UMPTranslator.upscale7to16(0) == 0)
        #expect(UMPTranslator.upscale7to16(127) == 0xFFFF)
        // Middle value: 64 is slightly above center in 7-bit scale
        let middle = UMPTranslator.upscale7to16(64)
        // 64 << 9 | 64 << 2 | 64 >> 5 = 32768 | 256 | 2 = 0x8102
        #expect(middle > 0x8000)  // Should be above center
        #expect(middle < 0x9000)  // But not too far above
    }

    @Test("Upscale 7 to 32 bit")
    func upscale7to32() {
        #expect(UMPTranslator.upscale7to32(0) == 0)
        #expect(UMPTranslator.upscale7to32(127) == 0xFFFFFFFF)
    }

    @Test("Round-trip scaling preserves approximate value")
    func roundTripScaling() {
        for value: UInt8 in [0, 32, 64, 96, 127] {
            let upscaled16 = UMPTranslator.upscale7to16(value)
            let downscaled = UMPTranslator.downscale16to7(upscaled16)
            #expect(downscaled == value, "Round-trip failed for \(value)")
        }

        for value: UInt8 in [0, 32, 64, 96, 127] {
            let upscaled32 = UMPTranslator.upscale7to32(value)
            let downscaled = UMPTranslator.downscale32to7(upscaled32)
            #expect(downscaled == value, "Round-trip failed for \(value)")
        }
    }

    // MARK: - Batch Conversion

    @Test("Batch UMP to MIDI 1.0 stream")
    func batchToMidi1Stream() {
        let messages: [any UMPMessage] = [
            UMPMIDI1ChannelVoice.noteOn(group: 0, channel: 0, note: 60, velocity: 100),
            UMPMIDI1ChannelVoice.noteOff(group: 0, channel: 0, note: 60, velocity: 64)
        ]

        let stream = UMPTranslator.toMIDI1Stream(messages)

        #expect(stream == [0x90, 0x3C, 0x64, 0x80, 0x3C, 0x40])
    }

    @Test("Batch MIDI 1.0 stream to UMP")
    func batchFromMidi1Stream() {
        let stream: [UInt8] = [0x90, 0x3C, 0x64, 0x80, 0x3C, 0x40]
        let messages = UMPTranslator.fromMIDI1Stream(stream, group: 0)

        #expect(messages.count == 2)
        #expect(messages[0] is UMPMIDI1ChannelVoice)
        #expect(messages[1] is UMPMIDI1ChannelVoice)
    }

    @Test("MIDI 1.0 stream with running status")
    func midi1StreamWithRunningStatus() {
        // Running status: Note On, then more notes without repeating status byte
        let stream: [UInt8] = [0x90, 0x3C, 0x64, 0x3E, 0x64, 0x40, 0x64]
        let messages = UMPTranslator.fromMIDI1Stream(stream, group: 0)

        #expect(messages.count == 3)
    }

    @Test("MIDI 1.0 stream with real-time messages")
    func midi1StreamWithRealTime() {
        // Real-time messages interspersed with channel voice
        // Note: embedded real-time in the middle of a message is an edge case
        // This test verifies real-time parsing when messages are complete
        let stream: [UInt8] = [0x90, 0x3C, 0x64, 0xF8, 0xFA]  // Note On, Clock, Start
        let messages = UMPTranslator.fromMIDI1Stream(stream, group: 0)

        #expect(messages.count == 3)
        #expect(messages[0] is UMPMIDI1ChannelVoice)  // Note On
        #expect(messages[1] is UMPSystemRealTime)  // Timing clock
        #expect(messages[2] is UMPSystemRealTime)  // Start
    }

    // MARK: - RPN/NRPN to MIDI 1.0

    @Test("RPN (Registered Controller) to MIDI 1.0 CC sequence")
    func rpnToMidi1() {
        let ump = UMPMIDI2ChannelVoice.registeredController(
            group: 0, channel: 0, bank: 0, index: 0, value: 0x80000000
        )
        let bytes = UMPTranslator.toMIDI1(ump)

        // RPN: CC 101 (bank), CC 100 (index), CC 6 (data entry MSB)
        // 0x80000000 >> 25 = 64
        #expect(bytes == [0xB0, 101, 0, 0xB0, 100, 0, 0xB0, 6, 64])
    }

    @Test("NRPN (Assignable Controller) to MIDI 1.0 CC sequence")
    func nrpnToMidi1() {
        let ump = UMPMIDI2ChannelVoice.assignableController(
            group: 0, channel: 0, bank: 3, index: 7, value: 0xFFFFFFFF
        )
        let bytes = UMPTranslator.toMIDI1(ump)

        // NRPN: CC 99 (bank), CC 98 (index), CC 6 (data entry MSB)
        // 0xFFFFFFFF >> 25 = 127
        #expect(bytes == [0xB0, 99, 3, 0xB0, 98, 7, 0xB0, 6, 127])
    }

    @Test("RPN on different channel")
    func rpnDifferentChannel() {
        let ump = UMPMIDI2ChannelVoice.registeredController(
            group: 0, channel: 9, bank: 0, index: 5, value: 0x00000000
        )
        let bytes = UMPTranslator.toMIDI1(ump)

        // Channel 9 → 0xB9
        #expect(bytes == [0xB9, 101, 0, 0xB9, 100, 5, 0xB9, 6, 0])
    }

    @Test("RPN with zero value")
    func rpnZeroValue() {
        let ump = UMPMIDI2ChannelVoice.registeredController(
            group: 0, channel: 0, bank: 0, index: 0, value: 0
        )
        let bytes = UMPTranslator.toMIDI1(ump)

        #expect(bytes != nil)
        #expect(bytes![8] == 0) // Data entry MSB should be 0
    }

    @Test("Relative RPN returns nil (no MIDI 1.0 equivalent)")
    func relativeRpnReturnsNil() {
        let ump = UMPMIDI2ChannelVoice.relativeRegisteredController(
            group: 0, channel: 0, bank: 0, index: 0, value: 100
        )
        #expect(UMPTranslator.toMIDI1(ump) == nil)
    }

    @Test("Relative NRPN returns nil (no MIDI 1.0 equivalent)")
    func relativeNrpnReturnsNil() {
        let ump = UMPMIDI2ChannelVoice.relativeAssignableController(
            group: 0, channel: 0, bank: 0, index: 0, value: -50
        )
        #expect(UMPTranslator.toMIDI1(ump) == nil)
    }

    @Test("RPN/NRPN in batch toMIDI1Stream")
    func rpnNrpnInBatchStream() {
        let messages: [any UMPMessage] = [
            UMPMIDI2ChannelVoice.registeredController(
                group: 0, channel: 0, bank: 0, index: 0, value: 0x80000000
            ),
            UMPMIDI1ChannelVoice.noteOn(group: 0, channel: 0, note: 60, velocity: 100)
        ]

        let stream = UMPTranslator.toMIDI1Stream(messages)

        // RPN (9 bytes) + Note On (3 bytes) = 12 bytes
        #expect(stream.count == 12)
        // RPN part
        #expect(stream[0] == 0xB0)
        #expect(stream[1] == 101)
        // Note On part
        #expect(stream[9] == 0x90)
        #expect(stream[10] == 60)
        #expect(stream[11] == 100)
    }

    // MARK: - Edge Cases

    @Test("Empty bytes return nil")
    func emptyBytes() {
        #expect(UMPTranslator.fromMIDI1([], group: 0) == nil)
        #expect(UMPTranslator.fromMIDI1ToMIDI2([], group: 0) == nil)
    }

    @Test("Invalid status byte returns nil")
    func invalidStatusByte() {
        // Data byte only (no status)
        #expect(UMPTranslator.fromMIDI1([0x3C], group: 0) == nil)
    }

    @Test("Incomplete message returns nil")
    func incompleteMessage() {
        // Note On without velocity byte
        #expect(UMPTranslator.fromMIDI1([0x90, 0x3C], group: 0) == nil)
    }
}
