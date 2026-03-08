// ProfileID.swift
// MIDI2Profile
//
// MIDI-CI Profile Identifier (5バイト構造)
// MIDI-CI v1.2 仕様 (M2-101-UM) に準拠

import Foundation

/// MIDI-CI Profile 識別子 (5バイト)
///
/// Standard Defined Profile:   [0x7E, number1, number2, number3, level]
/// Manufacturer Specific:      [mfr1, mfr2, mfr3, info, level]
public struct ProfileID: Sendable, Hashable, Codable, CustomStringConvertible {

    // MARK: - Properties

    /// Byte 1: Profile ID Bank (0x7E = Standard Defined, その他 = Manufacturer Specific)
    public let byte1: UInt8

    /// Byte 2: Profile Number / Manufacturer ID byte 1
    public let byte2: UInt8

    /// Byte 3: Profile Number / Manufacturer ID byte 2
    public let byte3: UInt8

    /// Byte 4: Profile 固有バイト
    public let byte4: UInt8

    /// Byte 5: Profile Level
    public let byte5: UInt8

    // MARK: - Initialization

    /// 5バイトから ProfileID を作成
    public init(_ byte1: UInt8, _ byte2: UInt8, _ byte3: UInt8, _ byte4: UInt8, _ byte5: UInt8) {
        self.byte1 = byte1
        self.byte2 = byte2
        self.byte3 = byte3
        self.byte4 = byte4
        self.byte5 = byte5
    }

    /// バイト配列から作成 (5バイト必須)
    public init(bytes: [UInt8]) {
        precondition(bytes.count == 5, "ProfileID は 5 バイト必須")
        self.byte1 = bytes[0]
        self.byte2 = bytes[1]
        self.byte3 = bytes[2]
        self.byte4 = bytes[3]
        self.byte5 = bytes[4]
    }

    /// バイト配列の指定オフセットから作成
    /// オフセット + 5 がバイト数を超える場合は nil
    public init?(from bytes: [UInt8], offset: Int = 0) {
        guard offset + 5 <= bytes.count else { return nil }
        self.byte1 = bytes[offset]
        self.byte2 = bytes[offset + 1]
        self.byte3 = bytes[offset + 2]
        self.byte4 = bytes[offset + 3]
        self.byte5 = bytes[offset + 4]
    }

    // MARK: - Computed Properties

    /// Standard Defined Profile かどうか (Byte1 == 0x7E)
    public var isStandardDefined: Bool { byte1 == 0x7E }

    /// Manufacturer Specific Profile かどうか
    public var isManufacturerSpecific: Bool { byte1 != 0x7E }

    /// 5バイト配列として返す
    public var bytes: [UInt8] { [byte1, byte2, byte3, byte4, byte5] }

    /// Profile Level (byte5 のエイリアス)
    public var level: UInt8 { byte5 }

    // MARK: - CustomStringConvertible

    public var description: String {
        let hex = bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
        if isStandardDefined {
            return "ProfileID(Standard: [\(hex)])"
        } else {
            return "ProfileID(Manufacturer: [\(hex)])"
        }
    }
}

// MARK: - Standard Defined Profiles

extension ProfileID {

    /// Standard Defined Profile の定数
    public enum Standard {

        /// Default Control Change Mapping Profile (M2-113-UM)
        public static let defaultCCMapping = ProfileID(0x7E, 0x01, 0x00, 0x00, 0x00)

        /// General MIDI 2 Function Block Profile (M2-118-UM)
        public static let gmFunctionBlock = ProfileID(0x7E, 0x02, 0x00, 0x00, 0x00)

        /// General MIDI 2 Single Channel Profile (M2-119-UM)
        public static let gmSingleChannel = ProfileID(0x7E, 0x03, 0x00, 0x00, 0x00)

        /// MPE Profile (M2-120-UM)
        public static let mpe = ProfileID(0x7E, 0x04, 0x00, 0x00, 0x00)

        /// Drawbar Organ Profile (M2-121-UM)
        public static let drawbarOrgan = ProfileID(0x7E, 0x05, 0x00, 0x00, 0x00)

        /// Orchestral Articulation Profile (M2-123-UM)
        public static let orchestralArticulation = ProfileID(0x7E, 0x06, 0x00, 0x00, 0x00)
    }

    /// Manufacturer Specific Profile を作成
    public static func manufacturer(
        _ id1: UInt8, _ id2: UInt8, _ id3: UInt8,
        info: UInt8, level: UInt8
    ) -> ProfileID {
        ProfileID(id1, id2, id3, info, level)
    }
}

// MARK: - CoreMIDI 相互運用

extension ProfileID {

    /// CoreMIDI の MIDICIProfile 用 Data に変換
    public var profileIDData: Data {
        Data(bytes)
    }

    /// CoreMIDI の MIDICIProfile 用 Data から作成
    public init?(profileIDData: Data) {
        guard profileIDData.count == 5 else { return nil }
        self.init(bytes: Array(profileIDData))
    }
}
