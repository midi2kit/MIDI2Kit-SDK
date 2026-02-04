//
//  PEChannelInfo.swift
//  MIDI2Kit
//
//  Property Exchange Channel Information
//

import Foundation

// MARK: - Channel Info

/// Channel information from X-ChannelList resource
///
/// Represents a single MIDI channel's configuration and state.
public struct PEChannelInfo: Sendable, Codable, Identifiable {
    public var id: Int { channel }

    /// Channel number (0-15 for standard MIDI, 0-255 for MIDI 2.0)
    public let channel: Int

    /// Channel title/name
    public let title: String?

    /// Current program number (0-127)
    public let programNumber: Int?

    /// Current bank MSB (CC#0)
    public let bankMSB: Int?

    /// Current bank LSB (CC#32)
    public let bankLSB: Int?

    /// Current program name
    public let programTitle: String?

    /// Cluster type ("channel", "group", etc.)
    public let clusterType: String?

    /// Cluster index within group
    public let clusterIndex: Int?

    /// Number of channels in cluster
    public let clusterLength: Int?

    /// Whether channel is muted
    public let mute: Bool?

    /// Whether channel is solo'd
    public let solo: Bool?

    enum CodingKeys: String, CodingKey {
        case channel
        case title
        case programNumber = "program"
        case bankMSB = "bankPC"
        case bankLSB = "bankCC"
        case programTitle
        case clusterType
        case clusterIndex
        case clusterLength
        case mute
        case solo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Channel can be Int or String
        if let intValue = try? container.decode(Int.self, forKey: .channel) {
            channel = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .channel),
                  let parsed = Int(stringValue) {
            channel = parsed
        } else {
            channel = 0
        }

        title = try container.decodeIfPresent(String.self, forKey: .title)
        programNumber = try container.decodeIfPresent(Int.self, forKey: .programNumber)
        bankMSB = try container.decodeIfPresent(Int.self, forKey: .bankMSB)
        bankLSB = try container.decodeIfPresent(Int.self, forKey: .bankLSB)
        programTitle = try container.decodeIfPresent(String.self, forKey: .programTitle)
        clusterType = try container.decodeIfPresent(String.self, forKey: .clusterType)
        clusterIndex = try container.decodeIfPresent(Int.self, forKey: .clusterIndex)
        clusterLength = try container.decodeIfPresent(Int.self, forKey: .clusterLength)
        mute = try container.decodeIfPresent(Bool.self, forKey: .mute)
        solo = try container.decodeIfPresent(Bool.self, forKey: .solo)
    }

    public init(
        channel: Int,
        title: String? = nil,
        programNumber: Int? = nil,
        bankMSB: Int? = nil,
        bankLSB: Int? = nil,
        programTitle: String? = nil,
        clusterType: String? = nil,
        clusterIndex: Int? = nil,
        clusterLength: Int? = nil,
        mute: Bool? = nil,
        solo: Bool? = nil
    ) {
        self.channel = channel
        self.title = title
        self.programNumber = programNumber
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.programTitle = programTitle
        self.clusterType = clusterType
        self.clusterIndex = clusterIndex
        self.clusterLength = clusterLength
        self.mute = mute
        self.solo = solo
    }

    /// Display name (title or "Ch {channel}")
    public var displayName: String {
        title ?? "Ch \(channel)"
    }

    /// Full program description ("Bank MSB-LSB Program: Name")
    public var programDescription: String? {
        guard let prog = programNumber else { return nil }

        var parts: [String] = []

        if let msb = bankMSB, let lsb = bankLSB {
            parts.append("\(msb)-\(lsb)")
        }

        parts.append("#\(prog)")

        if let name = programTitle {
            parts.append(name)
        }

        return parts.joined(separator: " ")
    }
}
