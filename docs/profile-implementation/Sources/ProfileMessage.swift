// ProfileMessage.swift
// MIDI2Profile
//
// Profile Configuration メッセージ型定義
// MIDI-CI v1.2 仕様 (M2-101-UM) Section 8 に準拠

import Foundation

// MARK: - Sub-ID#2 定数

/// Profile Configuration メッセージの Sub-ID#2 値
public enum ProfileMessageSubtype: UInt8, Sendable, CaseIterable {
    case profileInquiry          = 0x20
    case replyToProfileInquiry   = 0x21
    case setProfileOn            = 0x22
    case setProfileOff           = 0x23
    case profileEnabledReport    = 0x24
    case profileDisabledReport   = 0x25
    case profileAddedReport      = 0x26
    case profileRemovedReport    = 0x27
    case profileDetailsInquiry   = 0x28
    case replyToProfileDetails   = 0x29
    case profileSpecificData     = 0x2F

    /// Profile Configuration メッセージの範囲内かどうか
    public static func isProfileMessage(_ subID2: UInt8) -> Bool {
        (0x20...0x29).contains(subID2) || subID2 == 0x2F
    }
}

// MARK: - メッセージ構造体

/// Profile Inquiry (0x20): Initiator → Responder
public struct ProfileInquiry: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID

    public init(source: MUID, destination: MUID) {
        self.source = source
        self.destination = destination
    }
}

/// Reply to Profile Inquiry (0x21): Responder → Initiator
public struct ProfileInquiryReply: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let enabledProfiles: [ProfileID]
    public let disabledProfiles: [ProfileID]

    public init(source: MUID, destination: MUID, enabledProfiles: [ProfileID], disabledProfiles: [ProfileID]) {
        self.source = source
        self.destination = destination
        self.enabledProfiles = enabledProfiles
        self.disabledProfiles = disabledProfiles
    }
}

/// Set Profile On (0x22): Initiator → Responder
public struct SetProfileOn: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    /// v1.2: マルチチャンネルプロファイルサポート (0 = v1.1 互換)
    public let numberOfChannels: UInt16

    public init(source: MUID, destination: MUID, profile: ProfileID, numberOfChannels: UInt16 = 0) {
        self.source = source
        self.destination = destination
        self.profile = profile
        self.numberOfChannels = numberOfChannels
    }
}

/// Set Profile Off (0x23): Initiator → Responder
public struct SetProfileOff: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID

    public init(source: MUID, destination: MUID, profile: ProfileID) {
        self.source = source
        self.destination = destination
        self.profile = profile
    }
}

/// Profile Enabled Report (0x24): Responder → Broadcast
public struct ProfileEnabledReport: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let numberOfChannels: UInt16

    public init(source: MUID, destination: MUID, profile: ProfileID, numberOfChannels: UInt16 = 0) {
        self.source = source
        self.destination = destination
        self.profile = profile
        self.numberOfChannels = numberOfChannels
    }
}

/// Profile Disabled Report (0x25): Responder → Broadcast
public struct ProfileDisabledReport: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let numberOfChannels: UInt16

    public init(source: MUID, destination: MUID, profile: ProfileID, numberOfChannels: UInt16 = 0) {
        self.source = source
        self.destination = destination
        self.profile = profile
        self.numberOfChannels = numberOfChannels
    }
}

/// Profile Added Report (0x26): Responder → Broadcast
public struct ProfileAddedReport: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID

    public init(source: MUID, destination: MUID, profile: ProfileID) {
        self.source = source
        self.destination = destination
        self.profile = profile
    }
}

/// Profile Removed Report (0x27): Responder → Broadcast
public struct ProfileRemovedReport: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID

    public init(source: MUID, destination: MUID, profile: ProfileID) {
        self.source = source
        self.destination = destination
        self.profile = profile
    }
}

/// Profile Details Inquiry (0x28): Initiator → Responder
public struct ProfileDetailsInquiry: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    /// 0-127: プロファイル定義の照会ターゲット
    public let target: UInt8

    public init(source: MUID, destination: MUID, profile: ProfileID, target: UInt8) {
        self.source = source
        self.destination = destination
        self.profile = profile
        self.target = target
    }
}

/// Reply to Profile Details (0x29): Responder → Initiator
public struct ProfileDetailsReply: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let target: UInt8
    public let data: Data

    public init(source: MUID, destination: MUID, profile: ProfileID, target: UInt8, data: Data) {
        self.source = source
        self.destination = destination
        self.profile = profile
        self.target = target
        self.data = data
    }
}

/// Profile Specific Data (0x2F): 双方向
public struct ProfileSpecificData: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let data: Data

    public init(source: MUID, destination: MUID, profile: ProfileID, data: Data) {
        self.source = source
        self.destination = destination
        self.profile = profile
        self.data = data
    }
}

// MARK: - パース結果の統合 enum

/// パースされた Profile Configuration メッセージ
public enum ProfileMessage: Sendable, Equatable {
    case profileInquiry(ProfileInquiry)
    case profileInquiryReply(ProfileInquiryReply)
    case setProfileOn(SetProfileOn)
    case setProfileOff(SetProfileOff)
    case profileEnabledReport(ProfileEnabledReport)
    case profileDisabledReport(ProfileDisabledReport)
    case profileAddedReport(ProfileAddedReport)
    case profileRemovedReport(ProfileRemovedReport)
    case profileDetailsInquiry(ProfileDetailsInquiry)
    case profileDetailsReply(ProfileDetailsReply)
    case profileSpecificData(ProfileSpecificData)

    /// メッセージの Sub-ID#2 値
    public var subtype: ProfileMessageSubtype {
        switch self {
        case .profileInquiry: return .profileInquiry
        case .profileInquiryReply: return .replyToProfileInquiry
        case .setProfileOn: return .setProfileOn
        case .setProfileOff: return .setProfileOff
        case .profileEnabledReport: return .profileEnabledReport
        case .profileDisabledReport: return .profileDisabledReport
        case .profileAddedReport: return .profileAddedReport
        case .profileRemovedReport: return .profileRemovedReport
        case .profileDetailsInquiry: return .profileDetailsInquiry
        case .profileDetailsReply: return .replyToProfileDetails
        case .profileSpecificData: return .profileSpecificData
        }
    }

    /// メッセージの source MUID
    public var source: MUID {
        switch self {
        case .profileInquiry(let m): return m.source
        case .profileInquiryReply(let m): return m.source
        case .setProfileOn(let m): return m.source
        case .setProfileOff(let m): return m.source
        case .profileEnabledReport(let m): return m.source
        case .profileDisabledReport(let m): return m.source
        case .profileAddedReport(let m): return m.source
        case .profileRemovedReport(let m): return m.source
        case .profileDetailsInquiry(let m): return m.source
        case .profileDetailsReply(let m): return m.source
        case .profileSpecificData(let m): return m.source
        }
    }

    /// メッセージの destination MUID
    public var destination: MUID {
        switch self {
        case .profileInquiry(let m): return m.destination
        case .profileInquiryReply(let m): return m.destination
        case .setProfileOn(let m): return m.destination
        case .setProfileOff(let m): return m.destination
        case .profileEnabledReport(let m): return m.destination
        case .profileDisabledReport(let m): return m.destination
        case .profileAddedReport(let m): return m.destination
        case .profileRemovedReport(let m): return m.destination
        case .profileDetailsInquiry(let m): return m.destination
        case .profileDetailsReply(let m): return m.destination
        case .profileSpecificData(let m): return m.destination
        }
    }
}
