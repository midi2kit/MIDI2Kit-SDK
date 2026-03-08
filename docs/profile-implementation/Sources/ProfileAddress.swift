// ProfileAddress.swift
// MIDI2Profile
//
// Profile が適用されるアドレススコープ
// MIDI-CI v1.2 仕様 (M2-101-UM) に準拠

/// Profile が適用されるスコープ
///
/// MIDI-CI では Profile のアドレスとして、個別チャンネル・グループ・Function Block の 3 種類を使用する。
public enum ProfileAddress: Sendable, Hashable, Codable {

    /// 個別 MIDI チャンネル (0x00-0x0F)
    case channel(UInt8)

    /// MIDI 2.0 Group 全体 (0x7E)
    case group

    /// Function Block 全体 (0x7F)
    case functionBlock

    // MARK: - Raw Value

    /// SysEx バイト値に変換
    public var rawValue: UInt8 {
        switch self {
        case .channel(let ch): return ch & 0x0F
        case .group: return 0x7E
        case .functionBlock: return 0x7F
        }
    }

    /// SysEx バイト値から作成
    public init?(rawValue: UInt8) {
        switch rawValue {
        case 0x00...0x0F: self = .channel(rawValue)
        case 0x7E: self = .group
        case 0x7F: self = .functionBlock
        default: return nil
        }
    }

    // MARK: - Channel Helpers

    /// チャンネルアドレスの場合、チャンネル番号を返す (0-15)
    public var channelNumber: UInt8? {
        if case .channel(let ch) = self { return ch }
        return nil
    }

    /// チャンネルアドレスかどうか
    public var isChannel: Bool {
        if case .channel = self { return true }
        return false
    }
}

// MARK: - CustomStringConvertible

extension ProfileAddress: CustomStringConvertible {

    public var description: String {
        switch self {
        case .channel(let ch): return "Channel(\(ch))"
        case .group: return "Group"
        case .functionBlock: return "FunctionBlock"
        }
    }
}
