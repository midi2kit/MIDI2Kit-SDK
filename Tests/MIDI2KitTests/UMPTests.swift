//
//  UMPTests.swift
//  MIDI2Kit
//
//  Tests for UMP types, builder, and parser
//

import Testing
@testable import MIDI2Core

// MARK: - UMP Types Tests

@Suite("UMP Types")
struct UMPTypesTests {
    
    @Test("Message type word counts are correct")
    func messageTypeWordCounts() {
        #expect(UMPMessageType.utility.wordCount == 1)
        #expect(UMPMessageType.system.wordCount == 1)
        #expect(UMPMessageType.midi1ChannelVoice.wordCount == 1)
        #expect(UMPMessageType.data64.wordCount == 2)
        #expect(UMPMessageType.midi2ChannelVoice.wordCount == 2)
        #expect(UMPMessageType.data128.wordCount == 4)
    }
    
    @Test("UMP Group clamping")
    func umpGroupClamping() {
        let group = UMPGroup(rawValue: 20)
        #expect(group.rawValue == 4)  // 20 & 0x0F = 4
        
        let validGroup = UMPGroup(rawValue: 15)
        #expect(validGroup.rawValue == 15)
    }
    
    @Test("MIDI Channel clamping")
    func midiChannelClamping() {
        let channel = MIDIChannel(rawValue: 18)
        #expect(channel.rawValue == 2)  // 18 & 0x0F = 2
        #expect(channel.displayValue == 3)
    }
    
    @Test("Program Bank combined value")
    func programBankCombined() {
        let bank = ProgramBank(msb: 1, lsb: 32)
        #expect(bank.combined == 160)  // 1 * 128 + 32
        
        let fromCombined = ProgramBank(combined: 160)
        #expect(fromCombined.msb == 1)
        #expect(fromCombined.lsb == 32)
    }
}

// MARK: - Value Scaling Tests

@Suite("UMP Value Scaling")
struct UMPValueScalingTests {
    
    @Test("7-bit to 32-bit scaling")
    func scale7To32() {
        #expect(UMPValueScaling.scale7To32(0) == 0)
        #expect(UMPValueScaling.scale7To32(127) == 0xFE000000)
        #expect(UMPValueScaling.scale7To32(64) == 0x80000000)
    }
    
    @Test("32-bit to 7-bit scaling")
    func scale32To7() {
        #expect(UMPValueScaling.scale32To7(0) == 0)
        #expect(UMPValueScaling.scale32To7(0xFE000000) == 127)
        #expect(UMPValueScaling.scale32To7(0x80000000) == 64)
    }
    
    @Test("14-bit to 32-bit scaling")
    func scale14To32() {
        #expect(UMPValueScaling.scale14To32(0) == 0)
        #expect(UMPValueScaling.scale14To32(0x3FFF) == 0xFFFC0000)
        #expect(UMPValueScaling.scale14To32(0x2000) == 0x80000000)
    }
    
    @Test("Velocity 7 to 16 scaling")
    func velocityScaling() {
        #expect(UMPValueScaling.scaleVelocity7To16(0) == 0)
        #expect(UMPValueScaling.scaleVelocity7To16(127) == 0xFE00)
        #expect(UMPValueScaling.scaleVelocity16To7(0xFE00) == 127)
    }
    
    @Test("Normalized to 32-bit scaling")
    func normalizedScaling() {
        #expect(UMPValueScaling.normalizedTo32(0.0) == 0)
        #expect(UMPValueScaling.normalizedTo32(1.0) == UInt32.max)
        
        // 0.5 should map to approximately mid-range (allowing for floating-point rounding)
        let halfValue = UMPValueScaling.normalizedTo32(0.5)
        #expect(halfValue >= 0x7FFFFFFF)
        #expect(halfValue <= 0x80000000)
    }
}

// MARK: - UMP Builder Tests

@Suite("UMP Builder")
struct UMPBuilderTests {
    
    @Test("MIDI 2.0 Control Change")
    func midi2ControlChange() {
        let words = UMPBuilder.midi2ControlChange(
            group: 0,
            channel: 5,
            controller: 74,
            value: 0x80000000
        )
        
        #expect(words.count == 2)
        
        // Word 0: [0x4][0x0][0xB][0x5][74][0x00]
        let expectedWord0: UInt32 = 0x40B54A00
        #expect(words[0] == expectedWord0)
        #expect(words[1] == 0x80000000)
    }
    
    @Test("MIDI 2.0 Note On")
    func midi2NoteOn() {
        let words = UMPBuilder.midi2NoteOn(
            group: 1,
            channel: 0,
            note: 60,
            velocity: 0xC000
        )
        
        #expect(words.count == 2)
        
        // Word 0: [0x4][0x1][0x9][0x0][60][0x00]
        let expectedWord0: UInt32 = 0x41903C00
        #expect(words[0] == expectedWord0)
        
        // Word 1: [velocity:16][attr:16]
        #expect(words[1] == 0xC0000000)
    }
    
    @Test("MIDI 2.0 Note Off")
    func midi2NoteOff() {
        let words = UMPBuilder.midi2NoteOff(
            group: 0,
            channel: 0,
            note: 60,
            velocity: 0x4000
        )
        
        #expect(words.count == 2)
        #expect((words[0] >> 20) & 0x0F == 0x8)  // Note Off status
    }
    
    @Test("MIDI 2.0 Program Change with bank")
    func midi2ProgramChangeWithBank() {
        let words = UMPBuilder.midi2ProgramChange(
            group: 0,
            channel: 0,
            program: 10,
            bank: ProgramBank(msb: 0, lsb: 32)
        )
        
        #expect(words.count == 2)
        
        // Check bank valid flag
        #expect((words[1] & 0x80000000) != 0)
        
        // Check program number
        #expect((words[1] >> 24) & 0x7F == 10)
        
        // Check bank MSB/LSB
        #expect((words[1] >> 8) & 0x7F == 0)
        #expect(words[1] & 0x7F == 32)
    }
    
    @Test("MIDI 2.0 Program Change without bank")
    func midi2ProgramChangeWithoutBank() {
        let words = UMPBuilder.midi2ProgramChange(
            group: 0,
            channel: 0,
            program: 10,
            bank: nil
        )
        
        #expect(words.count == 2)
        #expect((words[1] & 0x80000000) == 0)  // Bank valid flag should be 0
        #expect((words[1] >> 24) & 0x7F == 10)
    }
    
    @Test("MIDI 2.0 Pitch Bend")
    func midi2PitchBend() {
        let words = UMPBuilder.midi2PitchBend(
            group: 0,
            channel: 0,
            value: PitchBendValue.center
        )
        
        #expect(words.count == 2)
        #expect((words[0] >> 20) & 0x0F == 0xE)  // Pitch Bend status
        #expect(words[1] == 0x80000000)
    }
    
    @Test("MIDI 2.0 Registered Controller (RPN)")
    func midi2RegisteredController() {
        let words = UMPBuilder.midi2RegisteredController(
            group: 0,
            channel: 0,
            address: RegisteredController.pitchBendSensitivity,
            value: 0x30000000
        )
        
        #expect(words.count == 2)
        #expect((words[0] >> 20) & 0x0F == 0x2)  // Registered Controller status
    }
    
    @Test("MIDI 1.0 over UMP Control Change")
    func midi1ControlChange() {
        let words = UMPBuilder.midi1ControlChange(
            group: 0,
            channel: 0,
            controller: 1,
            value: 64
        )
        
        #expect(words.count == 1)
        
        // Word: [0x2][0x0][0xB0][1][64]
        let expectedWord: UInt32 = 0x20B00140
        #expect(words[0] == expectedWord)
    }
    
    @Test("MIDI 1.0 over UMP Pitch Bend")
    func midi1PitchBend() {
        let words = UMPBuilder.midi1PitchBend(
            group: 0,
            channel: 0,
            value: 8192  // Center
        )
        
        #expect(words.count == 1)
        
        // LSB = 0, MSB = 64 for center
        let lsb = UInt8(8192 & 0x7F)  // 0
        let msb = UInt8((8192 >> 7) & 0x7F)  // 64
        
        #expect((words[0] >> 8) & 0x7F == UInt32(lsb))
        #expect(words[0] & 0x7F == UInt32(msb))
    }
    
    @Test("Convenience method: MIDI 2.0 CC with 7-bit value")
    func midi2ControlChange7() {
        let words = UMPBuilder.midi2ControlChange7(
            group: 0,
            channel: 0,
            controller: 74,
            value7: 64
        )
        
        #expect(words.count == 2)
        #expect(words[1] == UMPValueScaling.scale7To32(64))
    }
    
    @Test("NOOP message")
    func noop() {
        let words = UMPBuilder.noop(group: 5)
        
        #expect(words.count == 1)
        #expect((words[0] >> 28) == 0x0)  // Utility type
        #expect((words[0] >> 24) & 0x0F == 5)  // Group 5
    }
}

// MARK: - UMP Parser Tests

@Suite("UMP Parser")
struct UMPParserTests {
    
    @Test("Parse MIDI 2.0 Control Change")
    func parseMIDI2ControlChange() {
        let words = UMPBuilder.midi2ControlChange(
            group: 0,
            channel: 5,
            controller: 74,
            value: 0x80000000
        )
        
        guard let parsed = UMPParser.parse(words) else {
            Issue.record("Failed to parse")
            return
        }
        
        if case .midi2ChannelVoice(let cv) = parsed {
            #expect(cv.group == 0)
            #expect(cv.channel == 5)
            #expect(cv.status == .controlChange)
            #expect(cv.controllerNumber == 74)
            #expect(cv.controllerValue32 == 0x80000000)
            #expect(cv.controllerValue7 == 64)
        } else {
            Issue.record("Expected midi2ChannelVoice")
        }
    }
    
    @Test("Parse MIDI 2.0 Note On")
    func parseMIDI2NoteOn() {
        let words = UMPBuilder.midi2NoteOn(
            group: 1,
            channel: 0,
            note: 60,
            velocity: 0xC000,
            attributeType: .pitch7_9,
            attributeData: 0x1234
        )
        
        guard let parsed = UMPParser.parse(words) else {
            Issue.record("Failed to parse")
            return
        }
        
        if case .midi2ChannelVoice(let cv) = parsed {
            #expect(cv.group == 1)
            #expect(cv.channel == 0)
            #expect(cv.status == .noteOn)
            #expect(cv.noteNumber == 60)
            #expect(cv.velocity16 == 0xC000)
            #expect(cv.attributeType == .pitch7_9)
            #expect(cv.attributeData == 0x1234)
        } else {
            Issue.record("Expected midi2ChannelVoice")
        }
    }
    
    @Test("Parse MIDI 2.0 Program Change with bank")
    func parseMIDI2ProgramChange() {
        let words = UMPBuilder.midi2ProgramChange(
            group: 0,
            channel: 0,
            program: 10,
            bank: ProgramBank(msb: 0, lsb: 32)
        )
        
        guard let parsed = UMPParser.parse(words) else {
            Issue.record("Failed to parse")
            return
        }
        
        if case .midi2ChannelVoice(let cv) = parsed {
            #expect(cv.status == .programChange)
            #expect(cv.programNumber == 10)
            #expect(cv.bankValid == true)
            #expect(cv.bank?.msb == 0)
            #expect(cv.bank?.lsb == 32)
        } else {
            Issue.record("Expected midi2ChannelVoice")
        }
    }
    
    @Test("Parse MIDI 1.0 over UMP")
    func parseMIDI1OverUMP() {
        let words = UMPBuilder.midi1ControlChange(
            group: 0,
            channel: 5,
            controller: 1,
            value: 64
        )
        
        guard let parsed = UMPParser.parse(words) else {
            Issue.record("Failed to parse")
            return
        }
        
        if case .midi1ChannelVoice(let cv) = parsed {
            #expect(cv.group == 0)
            #expect(cv.channel == 5)
            #expect(cv.isControlChange == true)
            #expect(cv.controllerNumber == 1)
            #expect(cv.controllerValue == 64)
        } else {
            Issue.record("Expected midi1ChannelVoice")
        }
    }
    
    @Test("Parse Utility NOOP")
    func parseUtilityNoop() {
        let words = UMPBuilder.noop(group: 5)
        
        guard let parsed = UMPParser.parse(words) else {
            Issue.record("Failed to parse")
            return
        }
        
        if case .utility(let group, let status, _) = parsed {
            #expect(group == 5)
            #expect(status == 0)  // NOOP
        } else {
            Issue.record("Expected utility")
        }
    }
    
    @Test("Message type extraction")
    func messageTypeExtraction() {
        let word0: UInt32 = 0x40903C00  // MIDI 2.0 Note On
        #expect(UMPParser.messageType(from: word0) == .midi2ChannelVoice)
        
        let word1: UInt32 = 0x20B00140  // MIDI 1.0 CC
        #expect(UMPParser.messageType(from: word1) == .midi1ChannelVoice)
    }
    
    @Test("Group extraction")
    func groupExtraction() {
        let word0: UInt32 = 0x45903C00  // Group 5
        #expect(UMPParser.group(from: word0) == 5)
    }
    
    @Test("Parse empty array returns nil")
    func parseEmpty() {
        #expect(UMPParser.parse([]) == nil)
    }
    
    @Test("Parse incomplete message returns nil")
    func parseIncomplete() {
        // MIDI 2.0 CV needs 2 words
        #expect(UMPParser.parse([0x40903C00]) == nil)
    }
}

// MARK: - Roundtrip Tests

@Suite("UMP Roundtrip")
struct UMPRoundtripTests {
    
    @Test("Control Change roundtrip")
    func controlChangeRoundtrip() {
        let originalController: UInt8 = 74
        let originalValue: UInt32 = 0xABCDEF00
        let originalChannel: UInt8 = 5
        let originalGroup: UInt8 = 2
        
        let words = UMPBuilder.midi2ControlChange(
            group: originalGroup,
            channel: originalChannel,
            controller: originalController,
            value: originalValue
        )
        
        guard let parsed = UMPParser.parse(words),
              case .midi2ChannelVoice(let cv) = parsed else {
            Issue.record("Failed roundtrip")
            return
        }
        
        #expect(cv.group == originalGroup)
        #expect(cv.channel == originalChannel)
        #expect(cv.controllerNumber == originalController)
        #expect(cv.controllerValue32 == originalValue)
    }
    
    @Test("Note On roundtrip")
    func noteOnRoundtrip() {
        let originalNote: UInt8 = 60
        let originalVelocity: UInt16 = 0xC000
        let originalAttrType: NoteAttributeType = .pitch7_9
        let originalAttrData: UInt16 = 0x1234
        
        let words = UMPBuilder.midi2NoteOn(
            group: 0,
            channel: 0,
            note: originalNote,
            velocity: originalVelocity,
            attributeType: originalAttrType,
            attributeData: originalAttrData
        )
        
        guard let parsed = UMPParser.parse(words),
              case .midi2ChannelVoice(let cv) = parsed else {
            Issue.record("Failed roundtrip")
            return
        }
        
        #expect(cv.noteNumber == originalNote)
        #expect(cv.velocity16 == originalVelocity)
        #expect(cv.attributeType == originalAttrType)
        #expect(cv.attributeData == originalAttrData)
    }
}
