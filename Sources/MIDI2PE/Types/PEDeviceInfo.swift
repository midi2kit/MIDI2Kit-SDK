//
//  PEDeviceInfo.swift
//  MIDI2Kit
//
//  Property Exchange Device Information
//

import Foundation

// MARK: - DeviceInfo

/// Device information from PE DeviceInfo resource
///
/// Supports both MIDI-CI 1.2 standard format and KORG proprietary format:
/// - Standard: `manufacturerName`, `productName`, `familyName`, `softwareVersion`
/// - KORG: `manufacturer`, `model`, `family`, `version`
public struct PEDeviceInfo: Sendable, Codable {

    /// Manufacturer name
    public let manufacturerName: String?

    /// Product/model name
    public let productName: String?

    /// Product instance ID (serial number, etc.)
    public let productInstanceID: String?

    /// Software/firmware version
    public let softwareVersion: String?

    /// Product family name
    public let familyName: String?

    /// Model name within family
    public let modelName: String?

    // CodingKeys for standard MIDI-CI format
    enum CodingKeys: String, CodingKey {
        case manufacturerName
        case productName
        case productInstanceID = "productInstanceId"
        case softwareVersion
        case familyName
        case modelName
        // KORG alternative keys
        case manufacturer
        case model
        case family
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try standard format first, fall back to KORG format
        manufacturerName = try container.decodeIfPresent(String.self, forKey: .manufacturerName)
            ?? container.decodeIfPresent(String.self, forKey: .manufacturer)

        productName = try container.decodeIfPresent(String.self, forKey: .productName)
            ?? container.decodeIfPresent(String.self, forKey: .model)

        productInstanceID = try container.decodeIfPresent(String.self, forKey: .productInstanceID)

        softwareVersion = try container.decodeIfPresent(String.self, forKey: .softwareVersion)
            ?? container.decodeIfPresent(String.self, forKey: .version)

        familyName = try container.decodeIfPresent(String.self, forKey: .familyName)
            ?? container.decodeIfPresent(String.self, forKey: .family)

        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
    }

    public init(
        manufacturerName: String? = nil,
        productName: String? = nil,
        productInstanceID: String? = nil,
        softwareVersion: String? = nil,
        familyName: String? = nil,
        modelName: String? = nil
    ) {
        self.manufacturerName = manufacturerName
        self.productName = productName
        self.productInstanceID = productInstanceID
        self.softwareVersion = softwareVersion
        self.familyName = familyName
        self.modelName = modelName
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode using standard MIDI-CI format only
        try container.encodeIfPresent(manufacturerName, forKey: .manufacturerName)
        try container.encodeIfPresent(productName, forKey: .productName)
        try container.encodeIfPresent(productInstanceID, forKey: .productInstanceID)
        try container.encodeIfPresent(softwareVersion, forKey: .softwareVersion)
        try container.encodeIfPresent(familyName, forKey: .familyName)
        try container.encodeIfPresent(modelName, forKey: .modelName)
    }

    /// Display name (product name or manufacturer name)
    public var displayName: String {
        productName ?? manufacturerName ?? "Unknown Device"
    }
}
