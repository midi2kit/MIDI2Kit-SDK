//
//  UMPFlexDataTests.swift
//  MIDI2KitTests
//
//  Tests for UMP Flex Data messages (Message Type 0xD)
//

import Testing
import Foundation
@testable import MIDI2Core

@Suite("UMP Flex Data Tests")
struct UMPFlexDataTests {

    // MARK: - Tempo Tests

    @Test("Set Tempo - 120 BPM")
    func setTempo120BPM() {
        let tempo = FlexDataTempo(bpm: 120)
        let message = UMPFlexData.setTempo(group: 0, tempo: tempo)

        let words = message.toWords()
        #expect(words.count == 4)

        // Verify message type (0xD) and format (complete)
        #expect((words[0] >> 28) == 0x0D)

        // Parse back
        let parsed = UMPFlexData.parse(words)
        if case .setTempo(_, let parsedTempo) = parsed {
            #expect(abs(parsedTempo.bpm - 120.0) < 0.1)
        } else {
            Issue.record("Failed to parse tempo message")
        }
    }

    @Test("Set Tempo - Various BPM values")
    func setTempoVariousBPM() {
        let bpmValues: [Double] = [60, 90, 120, 140, 180, 200]

        for bpm in bpmValues {
            let tempo = FlexDataTempo(bpm: bpm)
            let message = UMPFlexData.setTempo(group: 0, tempo: tempo)
            let words = message.toWords()
            let parsed = UMPFlexData.parse(words)

            if case .setTempo(_, let parsedTempo) = parsed {
                // Allow 0.1 BPM tolerance for rounding
                #expect(abs(parsedTempo.bpm - bpm) < 0.1, "BPM \(bpm) should round-trip correctly")
            } else {
                Issue.record("Failed to parse tempo message for BPM \(bpm)")
            }
        }
    }

    @Test("Set Tempo via factory method")
    func setTempoFactory() {
        let message = UMP.flexData.setTempo(bpm: 120)
        let words = message.toWords()

        #expect((words[0] >> 28) == 0x0D)

        if case .setTempo(_, let tempo) = message {
            #expect(abs(tempo.bpm - 120.0) < 0.1)
        } else {
            Issue.record("Factory method should create setTempo")
        }
    }

    // MARK: - Time Signature Tests

    @Test("Set Time Signature - 4/4")
    func setTimeSignature44() {
        let ts = FlexDataTimeSignature.fourFour
        let message = UMPFlexData.setTimeSignature(group: 0, timeSignature: ts)

        let words = message.toWords()
        #expect(words.count == 4)

        let parsed = UMPFlexData.parse(words)
        if case .setTimeSignature(_, let parsedTS) = parsed {
            #expect(parsedTS.numerator == 4)
            #expect(parsedTS.denominator == 4)
        } else {
            Issue.record("Failed to parse time signature")
        }
    }

    @Test("Set Time Signature - Various signatures")
    func setTimeSignatureVarious() {
        let signatures: [(UInt8, UInt8)] = [
            (3, 4),  // 3/4
            (6, 8),  // 6/8
            (5, 4),  // 5/4
            (7, 8),  // 7/8
            (2, 2),  // 2/2
        ]

        for (num, denom) in signatures {
            let ts = FlexDataTimeSignature(numerator: num, denominator: denom)
            let message = UMPFlexData.setTimeSignature(group: 0, timeSignature: ts)
            let words = message.toWords()
            let parsed = UMPFlexData.parse(words)

            if case .setTimeSignature(_, let parsedTS) = parsed {
                #expect(parsedTS.numerator == num, "\(num)/\(denom) numerator")
                #expect(parsedTS.denominator == Int(denom), "\(num)/\(denom) denominator")
            } else {
                Issue.record("Failed to parse \(num)/\(denom)")
            }
        }
    }

    @Test("Set Time Signature via factory")
    func setTimeSignatureFactory() {
        let message = UMP.flexData.setTimeSignature(numerator: 6, denominator: 8)

        if case .setTimeSignature(_, let ts) = message {
            #expect(ts.numerator == 6)
            #expect(ts.denominator == 8)
        } else {
            Issue.record("Factory should create setTimeSignature")
        }
    }

    // MARK: - Key Signature Tests

    @Test("Set Key Signature - C Major")
    func setKeySignatureCMajor() {
        let ks = FlexDataKeySignature.cMajor
        let message = UMPFlexData.setKeySignature(group: 0, channel: 0, keySignature: ks)

        let words = message.toWords()
        let parsed = UMPFlexData.parse(words)

        if case .setKeySignature(_, _, let parsedKS) = parsed {
            #expect(parsedKS.sharpsFlats == 0)
            #expect(parsedKS.tonicNote == 0)  // C
        } else {
            Issue.record("Failed to parse key signature")
        }
    }

    @Test("Set Key Signature - Various keys")
    func setKeySignatureVarious() {
        let keys: [(Int8, UInt8, String)] = [
            (0, 0, "C"),      // C Major
            (1, 7, "G"),      // G Major (1 sharp)
            (-1, 5, "F"),     // F Major (1 flat)
            (2, 2, "D"),      // D Major (2 sharps)
            (-2, 10, "Bb"),   // Bb Major (2 flats)
        ]

        for (sf, tonic, name) in keys {
            let ks = FlexDataKeySignature(sharpsFlats: sf, tonicNote: tonic)
            let message = UMPFlexData.setKeySignature(group: 0, channel: 0, keySignature: ks)
            let words = message.toWords()
            let parsed = UMPFlexData.parse(words)

            if case .setKeySignature(_, _, let parsedKS) = parsed {
                #expect(parsedKS.sharpsFlats == sf, "\(name) sharps/flats")
                #expect(parsedKS.tonicNote == tonic, "\(name) tonic")
            } else {
                Issue.record("Failed to parse \(name) key")
            }
        }
    }

    // MARK: - Chord Name Tests

    @Test("Set Chord Name - C Major")
    func setChordNameCMajor() {
        let chord = FlexDataChordName(rootNote: 0, chordType: .major)
        let message = UMPFlexData.setChordName(group: 0, channel: 0, chord: chord)

        let words = message.toWords()
        let parsed = UMPFlexData.parse(words)

        if case .setChordName(_, _, let parsedChord) = parsed {
            #expect(parsedChord.rootNote == 0)
            #expect(parsedChord.chordType == .major)
        } else {
            Issue.record("Failed to parse chord name")
        }
    }

    @Test("Set Chord Name - Various chords")
    func setChordNameVarious() {
        let chords: [(UInt8, FlexDataChordType)] = [
            (0, .major),     // C
            (2, .minor),     // Dm
            (4, .major7),    // E7
            (5, .minor7),    // Fm7
            (7, .dominant),  // G7
            (9, .diminished), // Adim
        ]

        for (root, type) in chords {
            let chord = FlexDataChordName(rootNote: root, chordType: type)
            let message = UMPFlexData.setChordName(group: 0, channel: 0, chord: chord)
            let words = message.toWords()
            let parsed = UMPFlexData.parse(words)

            if case .setChordName(_, _, let parsedChord) = parsed {
                #expect(parsedChord.rootNote == root, "Root note \(root)")
                #expect(parsedChord.chordType == type, "Chord type \(type)")
            } else {
                Issue.record("Failed to parse chord \(root) \(type)")
            }
        }
    }

    @Test("Set Chord Name via factory")
    func setChordNameFactory() {
        let message = UMP.flexData.setChordName(rootNote: 7, chordType: .dominant)

        if case .setChordName(_, _, let chord) = message {
            #expect(chord.rootNote == 7)  // G
            #expect(chord.chordType == .dominant)
        } else {
            Issue.record("Factory should create setChordName")
        }
    }

    // MARK: - Metronome Tests

    @Test("Set Metronome")
    func setMetronome() {
        let message = UMPFlexData.setMetronome(
            group: 0,
            clocksPerPrimaryClick: 24,
            barAccent1: 2,
            barAccent2: 0,
            barAccent3: 0,
            subDivClicks1: 2,
            subDivClicks2: 0
        )

        let words = message.toWords()
        #expect(words.count == 4)

        let parsed = UMPFlexData.parse(words)
        if case .setMetronome(_, let clicks, let a1, _, _, let s1, _) = parsed {
            #expect(clicks == 24)
            #expect(a1 == 2)
            #expect(s1 == 2)
        } else {
            Issue.record("Failed to parse metronome")
        }
    }

    // MARK: - Text Events Tests

    @Test("Metadata Text - Project Name")
    func metadataTextProjectName() {
        let message = UMP.flexData.projectName(text: "Test Project")

        let words = message.toWords()
        #expect(words.count == 4)

        let parsed = UMPFlexData.parse(words)
        if case .metadataText(_, _, let status, let text) = parsed {
            #expect(status == .projectName)
            let str = String(data: text, encoding: .utf8)
            #expect(str?.hasPrefix("Test") == true)
        } else {
            Issue.record("Failed to parse project name")
        }
    }

    @Test("Performance Text - Lyrics")
    func performanceTextLyrics() {
        let message = UMP.flexData.lyrics(text: "Hello World")

        let words = message.toWords()
        let parsed = UMPFlexData.parse(words)

        if case .performanceText(_, _, _, let status, let text) = parsed {
            #expect(status == .lyrics)
            let str = String(data: text, encoding: .utf8)
            #expect(str?.hasPrefix("Hello") == true)
        } else {
            Issue.record("Failed to parse lyrics")
        }
    }

    @Test("Text truncation at 12 bytes")
    func textTruncation() {
        let longText = "This is a very long string that exceeds 12 bytes"
        let message = UMP.flexData.projectName(text: longText)

        if case .metadataText(_, _, _, let text) = message {
            // Text should be truncated to 12 bytes max
            #expect(text.count <= 12)
        } else {
            Issue.record("Should be metadata text")
        }
    }

    // MARK: - Byte Conversion Tests

    @Test("toBytes produces correct length")
    func toBytesLength() {
        let message = UMP.flexData.setTempo(bpm: 120)
        let bytes = message.toBytes()

        // Flex Data is 128-bit = 16 bytes
        #expect(bytes.count == 16)
    }

    @Test("wordCount is 4")
    func wordCount() {
        let message = UMP.flexData.setTempo(bpm: 120)
        #expect(message.wordCount == 4)
    }

    @Test("messageType is flexData")
    func messageTypeCorrect() {
        let message = UMP.flexData.setTempo(bpm: 120)
        #expect(message.messageType == .flexData)
    }

    // MARK: - Group Tests

    @Test("Group is preserved")
    func groupPreserved() {
        let group: UMPGroup = 5
        let message = UMPFlexData.setTempo(group: group, tempo: FlexDataTempo(bpm: 120))

        #expect(message.group.rawValue == 5)

        let words = message.toWords()
        let parsedGroup = UInt8((words[0] >> 24) & 0x0F)
        #expect(parsedGroup == 5)
    }

    // MARK: - Description Tests

    @Test("Description is readable")
    func descriptionReadable() {
        let tempo = UMPFlexData.setTempo(group: 0, tempo: FlexDataTempo(bpm: 120))
        #expect(tempo.description.contains("120"))

        let ts = UMPFlexData.setTimeSignature(group: 0, timeSignature: .fourFour)
        #expect(ts.description.contains("4/4"))

        let chord = UMPFlexData.setChordName(group: 0, channel: 0, chord: FlexDataChordName(rootNote: 0, chordType: .major))
        #expect(chord.description.contains("C"))
    }

    // MARK: - Invalid Parse Tests

    @Test("Parse fails with wrong message type")
    func parseFailsWrongType() {
        // Create a MIDI 2.0 Channel Voice message (MT 0x4)
        let words: [UInt32] = [0x40901234, 0x80005678, 0, 0]
        let parsed = UMPFlexData.parse(words)
        #expect(parsed == nil)
    }

    @Test("Parse fails with insufficient words")
    func parseFailsInsufficientWords() {
        let words: [UInt32] = [0xD0000000]  // Only 1 word
        let parsed = UMPFlexData.parse(words)
        #expect(parsed == nil)
    }
}
