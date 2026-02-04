//
//  UMPFlexData.swift
//  MIDI2Kit
//
//  MIDI 2.0 Flex Data Messages (Message Type 0xD)
//
//  Flex Data carries tempo, time signature, metronome, key signature,
//  chord names, and text events. All Flex Data messages are 128-bit (4 words).
//
//  Reference: MIDI 2.0 UMP Specification, Section 5 (Flex Data Messages)
//

import Foundation

// MARK: - Flex Data Format Type

/// Flex Data format type (upper nibble of status)
public enum FlexDataFormat: UInt8, Sendable {
    /// Complete message in single UMP
    case complete = 0x0

    /// First UMP of multi-UMP message
    case start = 0x1

    /// Continuing UMP of multi-UMP message
    case `continue` = 0x2

    /// Last UMP of multi-UMP message
    case end = 0x3
}

// MARK: - Flex Data Address Type

/// Flex Data address type (channel field interpretation)
public enum FlexDataAddressType: UInt8, Sendable {
    /// Message applies to entire Function Block
    case channel = 0x0

    /// Message applies to specific Group
    case group = 0x1
}

// MARK: - Flex Data Status (Bank 0 - Setup and Performance)

/// Flex Data Bank 0 status values (Setup and Performance)
public enum FlexDataSetupStatus: UInt8, Sendable {
    /// Set Tempo (10 nanosecond units per quarter note)
    case setTempo = 0x00

    /// Set Time Signature
    case setTimeSignature = 0x01

    /// Set Metronome
    case setMetronome = 0x02

    /// Set Key Signature
    case setKeySignature = 0x05

    /// Set Chord Name
    case setChordName = 0x06
}

// MARK: - Flex Data Status (Bank 1 - Metadata Text)

/// Flex Data Bank 1 status values (Metadata Text)
public enum FlexDataMetadataTextStatus: UInt8, Sendable {
    /// Unknown/Custom text
    case unknown = 0x00

    /// Project Name
    case projectName = 0x01

    /// Composition Name
    case compositionName = 0x02

    /// MIDI Clip Name
    case midiClipName = 0x03

    /// Copyright Notice
    case copyrightNotice = 0x04

    /// Composer Name
    case composerName = 0x05

    /// Lyricist Name
    case lyricistName = 0x06

    /// Arranger Name
    case arrangerName = 0x07

    /// Publisher Name
    case publisherName = 0x08

    /// Primary Performer Name
    case primaryPerformerName = 0x09

    /// Accompanying Performer Name
    case accompanyingPerformerName = 0x0A

    /// Recording/Concert Date
    case recordingDate = 0x0B

    /// Recording/Concert Location
    case recordingLocation = 0x0C
}

// MARK: - Flex Data Status (Bank 2 - Performance Text)

/// Flex Data Bank 2 status values (Performance Text)
public enum FlexDataPerformanceTextStatus: UInt8, Sendable {
    /// Unknown/Custom text
    case unknown = 0x00

    /// Lyrics (current)
    case lyrics = 0x01

    /// Lyrics Language
    case lyricsLanguage = 0x02

    /// Ruby (Japanese phonetic)
    case ruby = 0x03

    /// Ruby Language
    case rubyLanguage = 0x04
}

// MARK: - Tempo

/// Tempo in 10 nanosecond units per quarter note
///
/// Example: 120 BPM = 500,000 microseconds/quarter = 50,000,000,000 nanoseconds/quarter
/// = 5,000,000,000 in 10ns units
public struct FlexDataTempo: Sendable, Hashable {
    /// Tempo in 10 nanosecond units per quarter note
    public let value: UInt32

    public init(tenNanosecondUnits: UInt32) {
        self.value = tenNanosecondUnits
    }

    /// Create from BPM
    /// - Parameter bpm: Beats per minute (must be > 0)
    public init(bpm: Double) {
        // 60 seconds * 1,000,000 microseconds * 100 (to get 10ns units) / BPM
        let tenNsPerQuarter = (60.0 * 1_000_000.0 * 100.0) / bpm
        self.value = UInt32(clamping: Int64(tenNsPerQuarter))
    }

    /// Tempo as beats per minute
    public var bpm: Double {
        guard value > 0 else { return 0 }
        return (60.0 * 1_000_000.0 * 100.0) / Double(value)
    }

    /// Tempo as microseconds per quarter note
    public var microsecondsPerQuarter: Double {
        Double(value) / 100.0
    }
}

// MARK: - Time Signature

/// Time signature representation
public struct FlexDataTimeSignature: Sendable, Hashable {
    /// Numerator of time signature
    public let numerator: UInt8

    /// Denominator as power of 2 (0=1, 1=2, 2=4, 3=8, 4=16, etc.)
    public let denominatorPower: UInt8

    /// Number of 32nd notes per 24 MIDI clocks
    public let numberOf32ndNotesPerClock: UInt8

    public init(numerator: UInt8, denominatorPower: UInt8, numberOf32ndNotesPerClock: UInt8 = 8) {
        self.numerator = numerator
        self.denominatorPower = denominatorPower
        self.numberOf32ndNotesPerClock = numberOf32ndNotesPerClock
    }

    /// Create common time signatures
    public init(numerator: UInt8, denominator: UInt8) {
        self.numerator = numerator
        // Calculate power of 2: 1=0, 2=1, 4=2, 8=3, 16=4, etc.
        var power: UInt8 = 0
        var d = denominator
        while d > 1 {
            d >>= 1
            power += 1
        }
        self.denominatorPower = power
        self.numberOf32ndNotesPerClock = 8 // Default: 8 32nd notes per 24 MIDI clocks
    }

    /// Actual denominator value
    public var denominator: Int {
        1 << Int(denominatorPower)
    }

    /// Common time signatures
    public static let fourFour = FlexDataTimeSignature(numerator: 4, denominator: 4)
    public static let threeFour = FlexDataTimeSignature(numerator: 3, denominator: 4)
    public static let sixEight = FlexDataTimeSignature(numerator: 6, denominator: 8)
    public static let twoFour = FlexDataTimeSignature(numerator: 2, denominator: 4)
    public static let fiveQuarter = FlexDataTimeSignature(numerator: 5, denominator: 4)
    public static let sevenEight = FlexDataTimeSignature(numerator: 7, denominator: 8)
}

// MARK: - Key Signature

/// Key signature representation
public struct FlexDataKeySignature: Sendable, Hashable {
    /// Number of sharps (positive) or flats (negative): -7 to +7
    public let sharpsFlats: Int8

    /// Tonic note (0=C, 1=C#, 2=D, ..., 11=B)
    public let tonicNote: UInt8

    public init(sharpsFlats: Int8, tonicNote: UInt8) {
        self.sharpsFlats = max(-7, min(7, sharpsFlats))
        self.tonicNote = tonicNote % 12
    }

    /// Note names
    public static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Description (e.g., "C Major", "A minor")
    public var description: String {
        Self.noteNames[Int(tonicNote)]
    }

    /// Common key signatures
    public static let cMajor = FlexDataKeySignature(sharpsFlats: 0, tonicNote: 0)
    public static let gMajor = FlexDataKeySignature(sharpsFlats: 1, tonicNote: 7)
    public static let dMajor = FlexDataKeySignature(sharpsFlats: 2, tonicNote: 2)
    public static let fMajor = FlexDataKeySignature(sharpsFlats: -1, tonicNote: 5)
    public static let bFlatMajor = FlexDataKeySignature(sharpsFlats: -2, tonicNote: 10)
}

// MARK: - Chord Name

/// Chord type for Flex Data chord messages
public enum FlexDataChordType: UInt8, Sendable {
    /// Clear chord
    case clear = 0x00

    /// Major
    case major = 0x01

    /// Major 6th
    case major6 = 0x02

    /// Major 7th
    case major7 = 0x03

    /// Major 9th
    case major9 = 0x04

    /// Major 11th
    case major11 = 0x05

    /// Major 13th
    case major13 = 0x06

    /// Minor
    case minor = 0x07

    /// Minor 6th
    case minor6 = 0x08

    /// Minor 7th
    case minor7 = 0x09

    /// Minor 9th
    case minor9 = 0x0A

    /// Minor 11th
    case minor11 = 0x0B

    /// Minor 13th
    case minor13 = 0x0C

    /// Dominant 7th
    case dominant = 0x0D

    /// Dominant 9th
    case dominant9 = 0x0E

    /// Dominant 11th
    case dominant11 = 0x0F

    /// Dominant 13th
    case dominant13 = 0x10

    /// Augmented
    case augmented = 0x11

    /// Augmented 7th
    case augmented7 = 0x12

    /// Diminished
    case diminished = 0x13

    /// Diminished 7th
    case diminished7 = 0x14

    /// Half-diminished
    case halfDiminished = 0x15

    /// Major/Minor (e.g., C/E)
    case majorMinor = 0x16

    /// Pedal
    case pedal = 0x17

    /// Power (5th)
    case power = 0x18

    /// Suspended 2nd
    case suspended2 = 0x19

    /// Suspended 4th
    case suspended4 = 0x1A
}

/// Chord alteration (sharpen/flatten)
public enum FlexDataChordAlteration: UInt8, Sendable {
    /// No alteration
    case none = 0x0

    /// Add degree
    case add = 0x1

    /// Subtract degree
    case subtract = 0x2

    /// Raise degree by half step
    case raise = 0x3

    /// Lower degree by half step
    case lower = 0x4
}

/// Chord representation
public struct FlexDataChordName: Sendable, Hashable {
    /// Root note (0-11: C, C#, D, ..., B)
    public let rootNote: UInt8

    /// Root note alteration (sharp/flat)
    public let rootAlteration: FlexDataChordAlteration

    /// Chord type
    public let chordType: FlexDataChordType

    /// Bass note (0-11, or nil for root bass)
    public let bassNote: UInt8?

    /// Bass alteration
    public let bassAlteration: FlexDataChordAlteration

    public init(
        rootNote: UInt8,
        rootAlteration: FlexDataChordAlteration = .none,
        chordType: FlexDataChordType,
        bassNote: UInt8? = nil,
        bassAlteration: FlexDataChordAlteration = .none
    ) {
        self.rootNote = rootNote % 12
        self.rootAlteration = rootAlteration
        self.chordType = chordType
        self.bassNote = bassNote.map { $0 % 12 }
        self.bassAlteration = bassAlteration
    }
}

// MARK: - Flex Data Message

/// MIDI 2.0 Flex Data Message (128-bit)
public enum UMPFlexData: UMPMessage, Sendable {

    // MARK: - Setup and Performance (Bank 0)

    /// Set Tempo
    case setTempo(group: UMPGroup, tempo: FlexDataTempo)

    /// Set Time Signature
    case setTimeSignature(group: UMPGroup, timeSignature: FlexDataTimeSignature)

    /// Set Metronome
    case setMetronome(
        group: UMPGroup,
        clocksPerPrimaryClick: UInt8,
        barAccent1: UInt8,
        barAccent2: UInt8,
        barAccent3: UInt8,
        subDivClicks1: UInt8,
        subDivClicks2: UInt8
    )

    /// Set Key Signature
    case setKeySignature(group: UMPGroup, channel: UMPChannel, keySignature: FlexDataKeySignature)

    /// Set Chord Name
    case setChordName(group: UMPGroup, channel: UMPChannel, chord: FlexDataChordName)

    // MARK: - Text Events (Bank 1 - Metadata, Bank 2 - Performance)

    /// Metadata text (Bank 1)
    case metadataText(
        group: UMPGroup,
        format: FlexDataFormat,
        textStatus: FlexDataMetadataTextStatus,
        text: Data
    )

    /// Performance text (Bank 2)
    case performanceText(
        group: UMPGroup,
        channel: UMPChannel,
        format: FlexDataFormat,
        textStatus: FlexDataPerformanceTextStatus,
        text: Data
    )

    // MARK: - UMPMessage Protocol

    public var messageType: UMPMessageType { .flexData }

    public var group: UMPGroup {
        switch self {
        case .setTempo(let g, _): return g
        case .setTimeSignature(let g, _): return g
        case .setMetronome(let g, _, _, _, _, _, _): return g
        case .setKeySignature(let g, _, _): return g
        case .setChordName(let g, _, _): return g
        case .metadataText(let g, _, _, _): return g
        case .performanceText(let g, _, _, _, _): return g
        }
    }

    public var wordCount: Int { 4 }

    public func toBytes() -> [UInt8] {
        let words = toWords()
        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        for word in words {
            bytes.append(UInt8((word >> 24) & 0xFF))
            bytes.append(UInt8((word >> 16) & 0xFF))
            bytes.append(UInt8((word >> 8) & 0xFF))
            bytes.append(UInt8(word & 0xFF))
        }
        return bytes
    }

    /// Convert to 32-bit words
    public func toWords() -> [UInt32] {
        switch self {
        case .setTempo(let group, let tempo):
            let word1 = makeWord1(
                group: group,
                format: .complete,
                address: .group,
                channel: 0,
                bank: 0,
                status: FlexDataSetupStatus.setTempo.rawValue
            )
            return [word1, tempo.value, 0, 0]

        case .setTimeSignature(let group, let ts):
            let word1 = makeWord1(
                group: group,
                format: .complete,
                address: .group,
                channel: 0,
                bank: 0,
                status: FlexDataSetupStatus.setTimeSignature.rawValue
            )
            let word2 = (UInt32(ts.numerator) << 24)
                      | (UInt32(ts.denominatorPower) << 16)
                      | (UInt32(ts.numberOf32ndNotesPerClock) << 8)
            return [word1, word2, 0, 0]

        case .setMetronome(let group, let clocksPerClick, let accent1, let accent2, let accent3, let sub1, let sub2):
            let word1 = makeWord1(
                group: group,
                format: .complete,
                address: .group,
                channel: 0,
                bank: 0,
                status: FlexDataSetupStatus.setMetronome.rawValue
            )
            let word2 = (UInt32(clocksPerClick) << 24)
                      | (UInt32(accent1) << 16)
                      | (UInt32(accent2) << 8)
                      | UInt32(accent3)
            let word3 = (UInt32(sub1) << 24) | (UInt32(sub2) << 16)
            return [word1, word2, word3, 0]

        case .setKeySignature(let group, let channel, let ks):
            let word1 = makeWord1(
                group: group,
                format: .complete,
                address: .channel,
                channel: channel.value,
                bank: 0,
                status: FlexDataSetupStatus.setKeySignature.rawValue
            )
            // sharpsFlats is signed, encode as two's complement in 4 bits
            let sf = UInt8(bitPattern: ks.sharpsFlats) & 0x0F
            let word2 = (UInt32(sf) << 28) | (UInt32(ks.tonicNote) << 24)
            return [word1, word2, 0, 0]

        case .setChordName(let group, let channel, let chord):
            let word1 = makeWord1(
                group: group,
                format: .complete,
                address: .channel,
                channel: channel.value,
                bank: 0,
                status: FlexDataSetupStatus.setChordName.rawValue
            )
            // Word 2: root note(4) + root alt(4) + chord type(8) + alteration 1(16)
            let word2 = (UInt32(chord.rootNote) << 28)
                      | (UInt32(chord.rootAlteration.rawValue) << 24)
                      | (UInt32(chord.chordType.rawValue) << 16)
            // Word 3: alteration 2(16) + alteration 3(16)
            let word3: UInt32 = 0
            // Word 4: alteration 4(16) + bass note(4) + bass alt(4) + bass type(8)
            let bassNoteValue = chord.bassNote ?? 0
            let word4 = (UInt32(bassNoteValue) << 12)
                      | (UInt32(chord.bassAlteration.rawValue) << 8)
            return [word1, word2, word3, word4]

        case .metadataText(let group, let format, let textStatus, let text):
            let word1 = makeWord1(
                group: group,
                format: format,
                address: .group,
                channel: 0,
                bank: 1, // Metadata text bank
                status: textStatus.rawValue
            )
            return makeTextWords(word1: word1, text: text)

        case .performanceText(let group, let channel, let format, let textStatus, let text):
            let word1 = makeWord1(
                group: group,
                format: format,
                address: .channel,
                channel: channel.value,
                bank: 2, // Performance text bank
                status: textStatus.rawValue
            )
            return makeTextWords(word1: word1, text: text)
        }
    }

    // MARK: - Private Helpers

    private func makeWord1(
        group: UMPGroup,
        format: FlexDataFormat,
        address: FlexDataAddressType,
        channel: UInt8,
        bank: UInt8,
        status: UInt8
    ) -> UInt32 {
        let mt = UInt32(UMPMessageType.flexData.rawValue) << 28
        let grp = UInt32(group.rawValue) << 24
        let fmt = UInt32(format.rawValue) << 22
        let addr = UInt32(address.rawValue) << 20
        let ch = UInt32(channel & 0x0F) << 16
        let bnk = UInt32(bank) << 8
        let sts = UInt32(status)
        return mt | grp | fmt | addr | ch | bnk | sts
    }

    private func makeTextWords(word1: UInt32, text: Data) -> [UInt32] {
        var words: [UInt32] = [word1, 0, 0, 0]

        // Pack up to 12 bytes of text into words 2-4
        let textBytes = Array(text.prefix(12))

        for (index, byte) in textBytes.enumerated() {
            let wordIndex = 1 + (index / 4)
            let bytePosition = 3 - (index % 4)
            words[wordIndex] |= UInt32(byte) << (bytePosition * 8)
        }

        return words
    }
}

// MARK: - UMP Factory Extensions

extension UMP {

    /// Flex Data message factory
    public enum flexData {

        /// Set Tempo
        /// - Parameters:
        ///   - group: UMP group
        ///   - bpm: Beats per minute
        public static func setTempo(group: UMPGroup = 0, bpm: Double) -> UMPFlexData {
            .setTempo(group: group, tempo: FlexDataTempo(bpm: bpm))
        }

        /// Set Tempo with raw value
        /// - Parameters:
        ///   - group: UMP group
        ///   - tenNanosecondUnits: Tempo in 10ns units per quarter note
        public static func setTempoRaw(group: UMPGroup = 0, tenNanosecondUnits: UInt32) -> UMPFlexData {
            .setTempo(group: group, tempo: FlexDataTempo(tenNanosecondUnits: tenNanosecondUnits))
        }

        /// Set Time Signature
        /// - Parameters:
        ///   - group: UMP group
        ///   - numerator: Numerator (e.g., 4 for 4/4)
        ///   - denominator: Denominator (e.g., 4 for 4/4)
        public static func setTimeSignature(
            group: UMPGroup = 0,
            numerator: UInt8,
            denominator: UInt8
        ) -> UMPFlexData {
            .setTimeSignature(
                group: group,
                timeSignature: FlexDataTimeSignature(numerator: numerator, denominator: denominator)
            )
        }

        /// Set Key Signature
        /// - Parameters:
        ///   - group: UMP group
        ///   - channel: MIDI channel
        ///   - sharpsFlats: Number of sharps (positive) or flats (negative)
        ///   - tonicNote: Tonic note (0=C, 1=C#, ..., 11=B)
        public static func setKeySignature(
            group: UMPGroup = 0,
            channel: UMPChannel = 0,
            sharpsFlats: Int8,
            tonicNote: UInt8
        ) -> UMPFlexData {
            .setKeySignature(
                group: group,
                channel: channel,
                keySignature: FlexDataKeySignature(sharpsFlats: sharpsFlats, tonicNote: tonicNote)
            )
        }

        /// Set Chord Name
        /// - Parameters:
        ///   - group: UMP group
        ///   - channel: MIDI channel
        ///   - rootNote: Root note (0=C, 1=C#, ..., 11=B)
        ///   - chordType: Chord type
        ///   - bassNote: Optional bass note for inversions
        public static func setChordName(
            group: UMPGroup = 0,
            channel: UMPChannel = 0,
            rootNote: UInt8,
            chordType: FlexDataChordType,
            bassNote: UInt8? = nil
        ) -> UMPFlexData {
            .setChordName(
                group: group,
                channel: channel,
                chord: FlexDataChordName(
                    rootNote: rootNote,
                    chordType: chordType,
                    bassNote: bassNote
                )
            )
        }

        /// Lyrics text event
        /// - Parameters:
        ///   - group: UMP group
        ///   - channel: MIDI channel
        ///   - format: Message format (complete, start, continue, end)
        ///   - text: Lyrics text (up to 12 bytes per message)
        public static func lyrics(
            group: UMPGroup = 0,
            channel: UMPChannel = 0,
            format: FlexDataFormat = .complete,
            text: String
        ) -> UMPFlexData {
            .performanceText(
                group: group,
                channel: channel,
                format: format,
                textStatus: .lyrics,
                text: Data(text.utf8.prefix(12))
            )
        }

        /// Project Name metadata
        /// - Parameters:
        ///   - group: UMP group
        ///   - format: Message format
        ///   - text: Project name (up to 12 bytes per message)
        public static func projectName(
            group: UMPGroup = 0,
            format: FlexDataFormat = .complete,
            text: String
        ) -> UMPFlexData {
            .metadataText(
                group: group,
                format: format,
                textStatus: .projectName,
                text: Data(text.utf8.prefix(12))
            )
        }

        /// Composition Name metadata
        public static func compositionName(
            group: UMPGroup = 0,
            format: FlexDataFormat = .complete,
            text: String
        ) -> UMPFlexData {
            .metadataText(
                group: group,
                format: format,
                textStatus: .compositionName,
                text: Data(text.utf8.prefix(12))
            )
        }

        /// Copyright Notice metadata
        public static func copyrightNotice(
            group: UMPGroup = 0,
            format: FlexDataFormat = .complete,
            text: String
        ) -> UMPFlexData {
            .metadataText(
                group: group,
                format: format,
                textStatus: .copyrightNotice,
                text: Data(text.utf8.prefix(12))
            )
        }
    }
}

// MARK: - Flex Data Parser

extension UMPFlexData {

    /// Parse Flex Data message from 4 UMP words
    /// - Parameter words: Array of 4 UInt32 words
    /// - Returns: Parsed Flex Data message, or nil if invalid
    public static func parse(_ words: [UInt32]) -> UMPFlexData? {
        guard words.count >= 4 else { return nil }

        let word1 = words[0]

        // Verify message type
        let mt = UInt8((word1 >> 28) & 0x0F)
        guard mt == UMPMessageType.flexData.rawValue else { return nil }

        let group = UMPGroup(rawValue: UInt8((word1 >> 24) & 0x0F))
        let format = FlexDataFormat(rawValue: UInt8((word1 >> 22) & 0x03)) ?? .complete
        let channel = UMPChannel(UInt8((word1 >> 16) & 0x0F))
        let bank = UInt8((word1 >> 8) & 0xFF)
        let status = UInt8(word1 & 0xFF)

        switch bank {
        case 0: // Setup and Performance
            return parseSetupMessage(
                group: group,
                channel: channel,
                status: status,
                words: words
            )

        case 1: // Metadata Text
            guard let textStatus = FlexDataMetadataTextStatus(rawValue: status) else { return nil }
            let text = extractTextData(from: words)
            return .metadataText(group: group, format: format, textStatus: textStatus, text: text)

        case 2: // Performance Text
            guard let textStatus = FlexDataPerformanceTextStatus(rawValue: status) else { return nil }
            let text = extractTextData(from: words)
            return .performanceText(group: group, channel: channel, format: format, textStatus: textStatus, text: text)

        default:
            return nil
        }
    }

    private static func parseSetupMessage(
        group: UMPGroup,
        channel: UMPChannel,
        status: UInt8,
        words: [UInt32]
    ) -> UMPFlexData? {
        guard let setupStatus = FlexDataSetupStatus(rawValue: status) else { return nil }

        let word2 = words[1]

        switch setupStatus {
        case .setTempo:
            return .setTempo(group: group, tempo: FlexDataTempo(tenNanosecondUnits: word2))

        case .setTimeSignature:
            let numerator = UInt8((word2 >> 24) & 0xFF)
            let denominatorPower = UInt8((word2 >> 16) & 0xFF)
            let clocks = UInt8((word2 >> 8) & 0xFF)
            return .setTimeSignature(
                group: group,
                timeSignature: FlexDataTimeSignature(
                    numerator: numerator,
                    denominatorPower: denominatorPower,
                    numberOf32ndNotesPerClock: clocks
                )
            )

        case .setMetronome:
            let word3 = words[2]
            return .setMetronome(
                group: group,
                clocksPerPrimaryClick: UInt8((word2 >> 24) & 0xFF),
                barAccent1: UInt8((word2 >> 16) & 0xFF),
                barAccent2: UInt8((word2 >> 8) & 0xFF),
                barAccent3: UInt8(word2 & 0xFF),
                subDivClicks1: UInt8((word3 >> 24) & 0xFF),
                subDivClicks2: UInt8((word3 >> 16) & 0xFF)
            )

        case .setKeySignature:
            let sfRaw = UInt8((word2 >> 28) & 0x0F)
            // Convert from 4-bit two's complement
            let sf: Int8 = sfRaw > 7 ? Int8(sfRaw) - 16 : Int8(sfRaw)
            let tonic = UInt8((word2 >> 24) & 0x0F)
            return .setKeySignature(
                group: group,
                channel: channel,
                keySignature: FlexDataKeySignature(sharpsFlats: sf, tonicNote: tonic)
            )

        case .setChordName:
            let word4 = words[3]
            let rootNote = UInt8((word2 >> 28) & 0x0F)
            let rootAlt = FlexDataChordAlteration(rawValue: UInt8((word2 >> 24) & 0x0F)) ?? .none
            let chordType = FlexDataChordType(rawValue: UInt8((word2 >> 16) & 0xFF)) ?? .major
            let bassNote = UInt8((word4 >> 12) & 0x0F)
            let bassAlt = FlexDataChordAlteration(rawValue: UInt8((word4 >> 8) & 0x0F)) ?? .none

            return .setChordName(
                group: group,
                channel: channel,
                chord: FlexDataChordName(
                    rootNote: rootNote,
                    rootAlteration: rootAlt,
                    chordType: chordType,
                    bassNote: bassNote == 0 ? nil : bassNote,
                    bassAlteration: bassAlt
                )
            )
        }
    }

    private static func extractTextData(from words: [UInt32]) -> Data {
        var bytes: [UInt8] = []

        // Extract bytes from words 2, 3, 4 (indices 1, 2, 3)
        for wordIndex in 1..<4 {
            let word = words[wordIndex]
            for bytePosition in stride(from: 24, through: 0, by: -8) {
                let byte = UInt8((word >> bytePosition) & 0xFF)
                if byte != 0 {
                    bytes.append(byte)
                }
            }
        }

        return Data(bytes)
    }
}

// MARK: - CustomStringConvertible

extension UMPFlexData: CustomStringConvertible {
    public var description: String {
        switch self {
        case .setTempo(_, let tempo):
            return "FlexData.SetTempo(\(String(format: "%.2f", tempo.bpm)) BPM)"

        case .setTimeSignature(_, let ts):
            return "FlexData.SetTimeSignature(\(ts.numerator)/\(ts.denominator))"

        case .setMetronome(_, let clicks, _, _, _, _, _):
            return "FlexData.SetMetronome(clicks: \(clicks))"

        case .setKeySignature(_, _, let ks):
            return "FlexData.SetKeySignature(\(ks.description))"

        case .setChordName(_, _, let chord):
            return "FlexData.SetChordName(\(FlexDataKeySignature.noteNames[Int(chord.rootNote)]) \(chord.chordType))"

        case .metadataText(_, _, let status, let text):
            let str = String(data: text, encoding: .utf8) ?? text.hexString
            return "FlexData.MetadataText(\(status), \"\(str)\")"

        case .performanceText(_, _, _, let status, let text):
            let str = String(data: text, encoding: .utf8) ?? text.hexString
            return "FlexData.PerformanceText(\(status), \"\(str)\")"
        }
    }
}

// MARK: - Data Extension

fileprivate extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
