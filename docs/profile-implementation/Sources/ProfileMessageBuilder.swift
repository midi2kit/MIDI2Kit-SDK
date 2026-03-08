// ProfileMessageBuilder.swift
// MIDI2Profile
//
// Profile Configuration メッセージの SysEx バイト列構築
// CIMessageBuilder パターンに準拠

import Foundation

/// Profile Configuration メッセージの構築
///
/// MIDI-CI SysEx フォーマット:
/// ```
/// F0 7E <deviceID> 0D <Sub-ID#2> <CI version> <source MUID> <dest MUID> <payload> F7
/// ```
public enum ProfileMessageBuilder: Sendable {

    // MARK: - 定数

    /// MIDI-CI Universal SysEx ヘッダ
    private static let sysExStart: UInt8 = 0xF0
    private static let universalNonRealtime: UInt8 = 0x7E
    private static let deviceIDBroadcast: UInt8 = 0x7F
    private static let ciSubID1: UInt8 = 0x0D
    private static let sysExEnd: UInt8 = 0xF7

    /// MIDI-CI バージョン (v1.2 = 0x02)
    private static let ciVersion: UInt8 = 0x02

    // MARK: - Profile Inquiry (0x20)

    /// Profile Inquiry メッセージを構築
    public static func profileInquiry(
        source: MUID,
        destination: MUID
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .profileInquiry, source: source, destination: destination)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Reply to Profile Inquiry (0x21)

    /// Reply to Profile Inquiry メッセージを構築
    public static func profileInquiryReply(
        source: MUID,
        destination: MUID,
        enabledProfiles: [ProfileID],
        disabledProfiles: [ProfileID]
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .replyToProfileInquiry, source: source, destination: destination)

        // Enabled Profiles リスト
        appendUInt16LE(UInt16(enabledProfiles.count), to: &bytes)
        for profile in enabledProfiles {
            bytes.append(contentsOf: profile.bytes)
        }

        // Disabled Profiles リスト
        appendUInt16LE(UInt16(disabledProfiles.count), to: &bytes)
        for profile in disabledProfiles {
            bytes.append(contentsOf: profile.bytes)
        }

        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Set Profile On (0x22)

    /// Set Profile On メッセージを構築
    public static func setProfileOn(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        numberOfChannels: UInt16 = 0
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .setProfileOn, source: source, destination: destination)
        bytes.append(contentsOf: profile.bytes)
        appendUInt16LE(numberOfChannels, to: &bytes)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Set Profile Off (0x23)

    /// Set Profile Off メッセージを構築
    public static func setProfileOff(
        source: MUID,
        destination: MUID,
        profile: ProfileID
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .setProfileOff, source: source, destination: destination)
        bytes.append(contentsOf: profile.bytes)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Profile Enabled Report (0x24)

    /// Profile Enabled Report メッセージを構築
    public static func profileEnabledReport(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        numberOfChannels: UInt16 = 0
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .profileEnabledReport, source: source, destination: destination)
        bytes.append(contentsOf: profile.bytes)
        appendUInt16LE(numberOfChannels, to: &bytes)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Profile Disabled Report (0x25)

    /// Profile Disabled Report メッセージを構築
    public static func profileDisabledReport(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        numberOfChannels: UInt16 = 0
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .profileDisabledReport, source: source, destination: destination)
        bytes.append(contentsOf: profile.bytes)
        appendUInt16LE(numberOfChannels, to: &bytes)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Profile Added Report (0x26)

    /// Profile Added Report メッセージを構築
    public static func profileAddedReport(
        source: MUID,
        destination: MUID,
        profile: ProfileID
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .profileAddedReport, source: source, destination: destination)
        bytes.append(contentsOf: profile.bytes)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Profile Removed Report (0x27)

    /// Profile Removed Report メッセージを構築
    public static func profileRemovedReport(
        source: MUID,
        destination: MUID,
        profile: ProfileID
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .profileRemovedReport, source: source, destination: destination)
        bytes.append(contentsOf: profile.bytes)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Profile Details Inquiry (0x28)

    /// Profile Details Inquiry メッセージを構築
    public static func profileDetailsInquiry(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        target: UInt8
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .profileDetailsInquiry, source: source, destination: destination)
        bytes.append(contentsOf: profile.bytes)
        bytes.append(target & 0x7F)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Reply to Profile Details (0x29)

    /// Reply to Profile Details メッセージを構築
    public static func profileDetailsReply(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        target: UInt8,
        data: Data
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .replyToProfileDetails, source: source, destination: destination)
        bytes.append(contentsOf: profile.bytes)
        bytes.append(target & 0x7F)
        // データ長 (UInt16 LE)
        appendUInt16LE(UInt16(data.count), to: &bytes)
        bytes.append(contentsOf: data)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Profile Specific Data (0x2F)

    /// Profile Specific Data メッセージを構築
    public static func profileSpecificData(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        data: Data
    ) -> [UInt8] {
        var bytes = buildHeader(subtype: .profileSpecificData, source: source, destination: destination)
        bytes.append(contentsOf: profile.bytes)
        // データ長 (UInt32 LE, 仕様上 4バイト)
        appendUInt32LE(UInt32(data.count), to: &bytes)
        bytes.append(contentsOf: data)
        bytes.append(sysExEnd)
        return bytes
    }

    // MARK: - Internal Helpers

    /// MIDI-CI SysEx ヘッダを構築
    /// F0 7E 7F 0D <Sub-ID#2> <version> <source MUID 4 bytes> <dest MUID 4 bytes>
    private static func buildHeader(
        subtype: ProfileMessageSubtype,
        source: MUID,
        destination: MUID
    ) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        bytes.append(sysExStart)
        bytes.append(universalNonRealtime)
        bytes.append(deviceIDBroadcast)
        bytes.append(ciSubID1)
        bytes.append(subtype.rawValue)
        bytes.append(ciVersion)
        bytes.append(contentsOf: source.bytes)
        bytes.append(contentsOf: destination.bytes)
        return bytes
    }

    /// UInt16 を Little Endian (7-bit safe) で追加
    /// MIDI-CI は 7-bit バイトで数値を送信 (LSB first)
    private static func appendUInt16LE(_ value: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0x7F))
        bytes.append(UInt8((value >> 7) & 0x7F))
    }

    /// UInt32 を Little Endian (7-bit safe) で追加
    private static func appendUInt32LE(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0x7F))
        bytes.append(UInt8((value >> 7) & 0x7F))
        bytes.append(UInt8((value >> 14) & 0x7F))
        bytes.append(UInt8((value >> 21) & 0x7F))
    }
}
