//
//  PETypesKORGFormatTests.swift
//  MIDI2Kit
//
//  Tests for KORG-specific format handling in PETypes
//

import Testing
import Foundation
@testable import MIDI2PE

// MARK: - PEProgramDef KORG Format Tests

@Suite("PEProgramDef KORG Format")
struct PEProgramDefKORGFormatTests {

    @Test("Decodes standard format correctly")
    func decodesStandardFormat() throws {
        let json = """
        {
            "program": 5,
            "bankPC": 1,
            "bankCC": 2,
            "name": "Grand Piano"
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.programNumber == 5)
        #expect(program.bankMSB == 1)
        #expect(program.bankLSB == 2)
        #expect(program.name == "Grand Piano")
    }

    @Test("Decodes KORG bankPC array format [bankMSB, bankLSB, program]")
    func decodesKORGBankPCArray() throws {
        let json = """
        {
            "bankPC": [3, 4, 10],
            "name": "Electric Piano"
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.bankMSB == 3)
        #expect(program.bankLSB == 4)
        #expect(program.programNumber == 10)
        #expect(program.name == "Electric Piano")
    }

    @Test("Decodes KORG title field as name")
    func decodesKORGTitleAsName() throws {
        let json = """
        {
            "bankPC": [0, 0, 1],
            "title": "Strings"
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.name == "Strings")
    }

    @Test("Prefers name over title when both present")
    func prefersNameOverTitle() throws {
        let json = """
        {
            "bankPC": [0, 0, 2],
            "name": "Primary Name",
            "title": "Secondary Title"
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.name == "Primary Name")
    }

    @Test("Handles partial bankPC array [bankMSB, bankLSB]")
    func handlesPartialBankPCArray() throws {
        let json = """
        {
            "program": 15,
            "bankPC": [5, 6]
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.bankMSB == 5)
        #expect(program.bankLSB == 6)
        #expect(program.programNumber == 15)
    }

    @Test("Handles single element bankPC array")
    func handlesSingleElementBankPCArray() throws {
        let json = """
        {
            "program": 20,
            "bankPC": [7]
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.bankMSB == 7)
        #expect(program.bankLSB == 0)
        #expect(program.programNumber == 20)
    }

    @Test("Uses program from bankPC array when program field is absent")
    func usesProgramFromBankPCWhenProgramAbsent() throws {
        let json = """
        {
            "bankPC": [1, 2, 33],
            "title": "Test"
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.programNumber == 33)
    }

    @Test("Encodes in standard format")
    func encodesInStandardFormat() throws {
        let program = PEProgramDef(
            programNumber: 42,
            bankMSB: 1,
            bankLSB: 2,
            name: "Test Program"
        )

        let data = try JSONEncoder().encode(program)
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(decoded["program"] as? Int == 42)
        #expect(decoded["bankPC"] as? Int == 1)
        #expect(decoded["bankCC"] as? Int == 2)
        #expect(decoded["name"] as? String == "Test Program")
    }
}

// MARK: - PEChannelInfo KORG Format Tests

@Suite("PEChannelInfo KORG Format")
struct PEChannelInfoKORGFormatTests {

    @Test("Decodes standard format correctly")
    func decodesStandardFormat() throws {
        let json = """
        {
            "channel": 0,
            "title": "Piano",
            "program": 5,
            "bankPC": 1,
            "bankCC": 2,
            "programTitle": "Grand Piano"
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        #expect(channel.channel == 0)
        #expect(channel.title == "Piano")
        #expect(channel.programNumber == 5)
        #expect(channel.bankMSB == 1)
        #expect(channel.bankLSB == 2)
        #expect(channel.programTitle == "Grand Piano")
    }

    @Test("Decodes KORG bankPC array format")
    func decodesKORGBankPCArray() throws {
        let json = """
        {
            "channel": 1,
            "title": "Strings",
            "bankPC": [3, 4, 10],
            "programTitle": "Orchestral Strings"
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        #expect(channel.channel == 1)
        #expect(channel.bankMSB == 3)
        #expect(channel.bankLSB == 4)
        #expect(channel.programNumber == 10)
    }

    @Test("Uses program from bankPC when program field is absent")
    func usesProgramFromBankPC() throws {
        let json = """
        {
            "channel": 2,
            "title": "Bass",
            "bankPC": [0, 0, 32]
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        #expect(channel.programNumber == 32)
    }

    @Test("Prefers explicit program over bankPC array program")
    func prefersExplicitProgram() throws {
        let json = """
        {
            "channel": 3,
            "program": 99,
            "bankPC": [0, 0, 50]
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        #expect(channel.programNumber == 99)
        #expect(channel.bankMSB == 0)
        #expect(channel.bankLSB == 0)
    }

    @Test("Handles partial bankPC array")
    func handlesPartialBankPCArray() throws {
        let json = """
        {
            "channel": 4,
            "program": 15,
            "bankPC": [5, 6]
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        #expect(channel.bankMSB == 5)
        #expect(channel.bankLSB == 6)
        #expect(channel.programNumber == 15)
    }

    @Test("Handles channel as string")
    func handlesChannelAsString() throws {
        let json = """
        {
            "channel": "5",
            "title": "Test"
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        #expect(channel.channel == 5)
    }

    @Test("Decodes full KORG ChannelList entry")
    func decodesFullKORGChannelListEntry() throws {
        let json = """
        {
            "channel": 0,
            "title": "Piano",
            "programTitle": "Grand Piano",
            "bankPC": [0, 0, 0]
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        #expect(channel.channel == 0)
        #expect(channel.title == "Piano")
        #expect(channel.programTitle == "Grand Piano")
        #expect(channel.bankMSB == 0)
        #expect(channel.bankLSB == 0)
        #expect(channel.programNumber == 0)
    }
}

// MARK: - ChannelList Array Decoding Tests

@Suite("ChannelList Array Decoding")
struct ChannelListArrayDecodingTests {

    @Test("Decodes KORG ChannelList format")
    func decodesKORGChannelListFormat() throws {
        let json = """
        [
            {
                "title": "Piano",
                "channel": 0,
                "programTitle": "Grand Piano",
                "bankPC": [0, 0, 0]
            },
            {
                "title": "Bass",
                "channel": 1,
                "programTitle": "Acoustic Bass",
                "bankPC": [0, 1, 32]
            }
        ]
        """.data(using: .utf8)!

        let channels = try JSONDecoder().decode([PEChannelInfo].self, from: json)

        #expect(channels.count == 2)

        #expect(channels[0].channel == 0)
        #expect(channels[0].title == "Piano")
        #expect(channels[0].bankMSB == 0)
        #expect(channels[0].bankLSB == 0)
        #expect(channels[0].programNumber == 0)

        #expect(channels[1].channel == 1)
        #expect(channels[1].title == "Bass")
        #expect(channels[1].bankMSB == 0)
        #expect(channels[1].bankLSB == 1)
        #expect(channels[1].programNumber == 32)
    }
}

// MARK: - ProgramList Array Decoding Tests

@Suite("ProgramList Array Decoding")
struct ProgramListArrayDecodingTests {

    @Test("Decodes KORG ProgramList format")
    func decodesKORGProgramListFormat() throws {
        let json = """
        [
            {
                "title": "Grand Piano",
                "bankPC": [0, 0, 0]
            },
            {
                "title": "Electric Piano",
                "bankPC": [0, 0, 4]
            },
            {
                "title": "Strings",
                "bankPC": [0, 1, 48]
            }
        ]
        """.data(using: .utf8)!

        let programs = try JSONDecoder().decode([PEProgramDef].self, from: json)

        #expect(programs.count == 3)

        #expect(programs[0].name == "Grand Piano")
        #expect(programs[0].bankMSB == 0)
        #expect(programs[0].bankLSB == 0)
        #expect(programs[0].programNumber == 0)

        #expect(programs[1].name == "Electric Piano")
        #expect(programs[1].programNumber == 4)

        #expect(programs[2].name == "Strings")
        #expect(programs[2].bankMSB == 0)
        #expect(programs[2].bankLSB == 1)
        #expect(programs[2].programNumber == 48)
    }
}

// MARK: - Edge Case Tests (Suggestion #4)

@Suite("PEProgramDef Edge Cases")
struct PEProgramDefEdgeCaseTests {

    @Test("Explicit program: 0 is not overwritten by bankPC array")
    func explicitProgramZeroNotOverwritten() throws {
        // When program: 0 is explicitly specified, it should NOT be replaced by bankPC[2]
        let json = """
        {
            "program": 0,
            "bankPC": [1, 2, 99],
            "name": "Test"
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        // Should use explicit program: 0, not bankPC[2]: 99
        #expect(program.programNumber == 0)
        #expect(program.bankMSB == 1)
        #expect(program.bankLSB == 2)
    }

    @Test("Empty bankPC array is handled gracefully")
    func emptyBankPCArrayHandled() throws {
        let json = """
        {
            "program": 5,
            "bankPC": [],
            "name": "Test"
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.programNumber == 5)
        #expect(program.bankMSB == 0)
        #expect(program.bankLSB == 0)
    }

    @Test("Out-of-range values are recorded without throwing")
    func outOfRangeValuesRecorded() throws {
        // MIDI values > 127 are technically invalid, but we should decode them
        // and let validation happen at usage time
        let json = """
        {
            "bankPC": [200, 200, 200],
            "name": "Test"
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.bankMSB == 200)
        #expect(program.bankLSB == 200)
        #expect(program.programNumber == 200)
    }

    @Test("Missing all fields uses defaults")
    func missingAllFieldsUsesDefaults() throws {
        let json = """
        {}
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(PEProgramDef.self, from: json)

        #expect(program.programNumber == 0)
        #expect(program.bankMSB == 0)
        #expect(program.bankLSB == 0)
        #expect(program.name == nil)
    }
}

@Suite("PEChannelInfo Edge Cases")
struct PEChannelInfoEdgeCaseTests {

    @Test("Explicit program: 0 is not overwritten by bankPC array")
    func explicitProgramZeroNotOverwritten() throws {
        let json = """
        {
            "channel": 0,
            "program": 0,
            "bankPC": [1, 2, 99]
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        // Should use explicit program: 0, not bankPC[2]: 99
        #expect(channel.programNumber == 0)
        #expect(channel.bankMSB == 1)
        #expect(channel.bankLSB == 2)
    }

    @Test("Empty bankPC array is handled gracefully")
    func emptyBankPCArrayHandled() throws {
        let json = """
        {
            "channel": 1,
            "program": 10,
            "bankPC": []
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        #expect(channel.programNumber == 10)
        #expect(channel.bankMSB == nil)
        #expect(channel.bankLSB == nil)
    }

    @Test("Out-of-range values are recorded without throwing")
    func outOfRangeValuesRecorded() throws {
        let json = """
        {
            "channel": 0,
            "bankPC": [255, 255, 255]
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(PEChannelInfo.self, from: json)

        #expect(channel.bankMSB == 255)
        #expect(channel.bankLSB == 255)
        #expect(channel.programNumber == 255)
    }
}
