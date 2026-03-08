// ProfileMessageParser.swift
// MIDI2Profile
//
// Profile Configuration メッセージの SysEx バイト列解析
// CIMessageParser パターンに準拠

import Foundation

/// Profile Configuration メッセージの解析
///
/// SysEx バイト列を ProfileMessage にパースする。
/// Sub-ID#2 が Profile Configuration 範囲外の場合は nil を返す。
public enum ProfileMessageParser: Sendable {

    // MARK: - 定数

    /// MIDI-CI SysEx ヘッダの最小長
    /// F0 7E 7F 0D <Sub-ID#2> <version> <src MUID x4> <dst MUID x4> ... F7
    private static let minimumHeaderLength = 14  // F0 含む、F7 含まない

    // MARK: - Public API

    /// SysEx バイト列を Profile メッセージとしてパースする
    public static func parse(_ bytes: [UInt8]) -> ProfileMessage? {
        // 最小長チェック
        guard bytes.count >= minimumHeaderLength + 1 else { return nil }

        // SysEx ヘッダ検証
        guard bytes[0] == 0xF0,
              bytes[1] == 0x7E,
              bytes[3] == 0x0D else { return nil }

        let subID2 = bytes[4]
        guard ProfileMessageSubtype.isProfileMessage(subID2),
              let subtype = ProfileMessageSubtype(rawValue: subID2) else { return nil }

        // Source MUID (offset 6-9)
        guard let source = MUID(from: bytes, offset: 6) else { return nil }

        // Destination MUID (offset 10-13)
        guard let destination = MUID(from: bytes, offset: 10) else { return nil }

        // ペイロード開始位置 (ヘッダの直後)
        let payloadOffset = 14

        return parsePayload(subtype: subtype, source: source, destination: destination,
                            bytes: bytes, payloadOffset: payloadOffset)
    }

    // MARK: - Internal Parsing

    private static func parsePayload(
        subtype: ProfileMessageSubtype,
        source: MUID,
        destination: MUID,
        bytes: [UInt8],
        payloadOffset: Int
    ) -> ProfileMessage? {
        switch subtype {
        case .profileInquiry:
            return .profileInquiry(ProfileInquiry(source: source, destination: destination))

        case .replyToProfileInquiry:
            return parseProfileInquiryReply(source: source, destination: destination,
                                            bytes: bytes, offset: payloadOffset)

        case .setProfileOn:
            return parseSetProfileOn(source: source, destination: destination,
                                     bytes: bytes, offset: payloadOffset)

        case .setProfileOff:
            return parseSetProfileOff(source: source, destination: destination,
                                      bytes: bytes, offset: payloadOffset)

        case .profileEnabledReport:
            return parseProfileEnabledReport(source: source, destination: destination,
                                             bytes: bytes, offset: payloadOffset)

        case .profileDisabledReport:
            return parseProfileDisabledReport(source: source, destination: destination,
                                              bytes: bytes, offset: payloadOffset)

        case .profileAddedReport:
            return parseProfileReport(source: source, destination: destination,
                                      bytes: bytes, offset: payloadOffset, isAdded: true)

        case .profileRemovedReport:
            return parseProfileReport(source: source, destination: destination,
                                      bytes: bytes, offset: payloadOffset, isAdded: false)

        case .profileDetailsInquiry:
            return parseProfileDetailsInquiry(source: source, destination: destination,
                                              bytes: bytes, offset: payloadOffset)

        case .replyToProfileDetails:
            return parseProfileDetailsReply(source: source, destination: destination,
                                            bytes: bytes, offset: payloadOffset)

        case .profileSpecificData:
            return parseProfileSpecificData(source: source, destination: destination,
                                            bytes: bytes, offset: payloadOffset)
        }
    }

    // MARK: - Reply to Profile Inquiry (0x21)

    private static func parseProfileInquiryReply(
        source: MUID, destination: MUID,
        bytes: [UInt8], offset: Int
    ) -> ProfileMessage? {
        var pos = offset

        // Enabled Profiles 数 (UInt16 LE, 7-bit)
        guard pos + 2 <= bytes.count else { return nil }
        let enabledCount = readUInt16LE(bytes, at: pos)
        pos += 2

        // Enabled Profiles
        var enabledProfiles: [ProfileID] = []
        for _ in 0..<enabledCount {
            guard let profile = ProfileID(from: bytes, offset: pos) else { return nil }
            enabledProfiles.append(profile)
            pos += 5
        }

        // Disabled Profiles 数
        guard pos + 2 <= bytes.count else { return nil }
        let disabledCount = readUInt16LE(bytes, at: pos)
        pos += 2

        // Disabled Profiles
        var disabledProfiles: [ProfileID] = []
        for _ in 0..<disabledCount {
            guard let profile = ProfileID(from: bytes, offset: pos) else { return nil }
            disabledProfiles.append(profile)
            pos += 5
        }

        return .profileInquiryReply(ProfileInquiryReply(
            source: source, destination: destination,
            enabledProfiles: enabledProfiles, disabledProfiles: disabledProfiles
        ))
    }

    // MARK: - Set Profile On (0x22)

    private static func parseSetProfileOn(
        source: MUID, destination: MUID,
        bytes: [UInt8], offset: Int
    ) -> ProfileMessage? {
        // Profile ID (5 bytes) + numberOfChannels (2 bytes)
        guard let profile = ProfileID(from: bytes, offset: offset) else { return nil }
        let channelsOffset = offset + 5
        guard channelsOffset + 2 <= bytes.count else { return nil }
        let numberOfChannels = readUInt16LE(bytes, at: channelsOffset)

        return .setProfileOn(SetProfileOn(
            source: source, destination: destination,
            profile: profile, numberOfChannels: numberOfChannels
        ))
    }

    // MARK: - Set Profile Off (0x23)

    private static func parseSetProfileOff(
        source: MUID, destination: MUID,
        bytes: [UInt8], offset: Int
    ) -> ProfileMessage? {
        guard let profile = ProfileID(from: bytes, offset: offset) else { return nil }

        return .setProfileOff(SetProfileOff(
            source: source, destination: destination, profile: profile
        ))
    }

    // MARK: - Profile Enabled/Disabled Report (0x24, 0x25)

    private static func parseProfileEnabledReport(
        source: MUID, destination: MUID,
        bytes: [UInt8], offset: Int
    ) -> ProfileMessage? {
        guard let profile = ProfileID(from: bytes, offset: offset) else { return nil }
        let channelsOffset = offset + 5
        guard channelsOffset + 2 <= bytes.count else { return nil }
        let numberOfChannels = readUInt16LE(bytes, at: channelsOffset)

        return .profileEnabledReport(ProfileEnabledReport(
            source: source, destination: destination,
            profile: profile, numberOfChannels: numberOfChannels
        ))
    }

    private static func parseProfileDisabledReport(
        source: MUID, destination: MUID,
        bytes: [UInt8], offset: Int
    ) -> ProfileMessage? {
        guard let profile = ProfileID(from: bytes, offset: offset) else { return nil }
        let channelsOffset = offset + 5
        guard channelsOffset + 2 <= bytes.count else { return nil }
        let numberOfChannels = readUInt16LE(bytes, at: channelsOffset)

        return .profileDisabledReport(ProfileDisabledReport(
            source: source, destination: destination,
            profile: profile, numberOfChannels: numberOfChannels
        ))
    }

    // MARK: - Profile Added/Removed Report (0x26, 0x27)

    private static func parseProfileReport(
        source: MUID, destination: MUID,
        bytes: [UInt8], offset: Int,
        isAdded: Bool
    ) -> ProfileMessage? {
        guard let profile = ProfileID(from: bytes, offset: offset) else { return nil }

        if isAdded {
            return .profileAddedReport(ProfileAddedReport(
                source: source, destination: destination, profile: profile
            ))
        } else {
            return .profileRemovedReport(ProfileRemovedReport(
                source: source, destination: destination, profile: profile
            ))
        }
    }

    // MARK: - Profile Details Inquiry (0x28)

    private static func parseProfileDetailsInquiry(
        source: MUID, destination: MUID,
        bytes: [UInt8], offset: Int
    ) -> ProfileMessage? {
        guard let profile = ProfileID(from: bytes, offset: offset) else { return nil }
        let targetOffset = offset + 5
        guard targetOffset < bytes.count else { return nil }
        let target = bytes[targetOffset] & 0x7F

        return .profileDetailsInquiry(ProfileDetailsInquiry(
            source: source, destination: destination,
            profile: profile, target: target
        ))
    }

    // MARK: - Reply to Profile Details (0x29)

    private static func parseProfileDetailsReply(
        source: MUID, destination: MUID,
        bytes: [UInt8], offset: Int
    ) -> ProfileMessage? {
        guard let profile = ProfileID(from: bytes, offset: offset) else { return nil }
        let targetOffset = offset + 5
        guard targetOffset + 3 <= bytes.count else { return nil }

        let target = bytes[targetOffset] & 0x7F
        let dataLength = Int(readUInt16LE(bytes, at: targetOffset + 1))
        let dataOffset = targetOffset + 3

        guard dataOffset + dataLength <= bytes.count else { return nil }
        let data = Data(bytes[dataOffset..<(dataOffset + dataLength)])

        return .profileDetailsReply(ProfileDetailsReply(
            source: source, destination: destination,
            profile: profile, target: target, data: data
        ))
    }

    // MARK: - Profile Specific Data (0x2F)

    private static func parseProfileSpecificData(
        source: MUID, destination: MUID,
        bytes: [UInt8], offset: Int
    ) -> ProfileMessage? {
        guard let profile = ProfileID(from: bytes, offset: offset) else { return nil }
        let lengthOffset = offset + 5

        // データ長 (UInt32 LE, 7-bit x 4)
        guard lengthOffset + 4 <= bytes.count else { return nil }
        let dataLength = Int(readUInt32LE(bytes, at: lengthOffset))
        let dataOffset = lengthOffset + 4

        guard dataOffset + dataLength <= bytes.count else { return nil }
        let data = Data(bytes[dataOffset..<(dataOffset + dataLength)])

        return .profileSpecificData(ProfileSpecificData(
            source: source, destination: destination,
            profile: profile, data: data
        ))
    }

    // MARK: - Byte Reading Helpers

    /// UInt16 を Little Endian (7-bit) で読み取り
    private static func readUInt16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset] & 0x7F) | (UInt16(bytes[offset + 1] & 0x7F) << 7)
    }

    /// UInt32 を Little Endian (7-bit) で読み取り
    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset] & 0x7F)
        | (UInt32(bytes[offset + 1] & 0x7F) << 7)
        | (UInt32(bytes[offset + 2] & 0x7F) << 14)
        | (UInt32(bytes[offset + 3] & 0x7F) << 21)
    }
}
