//
//  MockDevicePresets.swift
//  MIDI2Kit
//
//  Preset configurations for mock MIDI-CI devices
//

import Foundation
import MIDI2Core

/// Preset configurations for mock MIDI-CI devices
public struct MockDevicePreset: Sendable {

    /// Device identity
    public let identity: DeviceIdentity

    /// Category support flags
    public let categorySupport: CategorySupport

    /// Resources to register (name -> JSON string)
    public let resources: [String: String]

    // MARK: - Factory Methods

    /// KORG Module Pro preset
    ///
    /// Simulates a KORG Module Pro with typical resources.
    public static let korgModulePro = MockDevicePreset(
        identity: DeviceIdentity(
            manufacturerID: .standard(0x42),  // KORG
            familyID: 0x006B,                 // Module Pro family
            modelID: 0x0001,
            versionID: 0x01020304             // v1.2.3.4
        ),
        categorySupport: .propertyExchange,
        resources: [
            "DeviceInfo": """
            {
                "manufacturerId": [66],
                "familyId": [107, 0],
                "modelId": [1, 0],
                "versionId": [4, 3, 2, 1],
                "manufacturer": "KORG Inc.",
                "family": "Module Pro",
                "model": "Module Pro",
                "version": "1.2.3.4"
            }
            """,

            "ResourceList": """
            [
                {"resource": "DeviceInfo"},
                {"resource": "ResourceList"},
                {"resource": "CMList"},
                {"resource": "ChannelList"},
                {"resource": "ProgramList", "canSubscribe": true}
            ]
            """,

            "CMList": """
            [
                {"cmIdx": 0, "name": "Piano", "numPrograms": 25},
                {"cmIdx": 1, "name": "E.Piano", "numPrograms": 16},
                {"cmIdx": 2, "name": "Organ", "numPrograms": 12},
                {"cmIdx": 3, "name": "Strings", "numPrograms": 8},
                {"cmIdx": 4, "name": "Synth", "numPrograms": 32}
            ]
            """,

            "ChannelList": """
            [
                {"chIdx": 0, "name": "Channel 1", "cmIdx": 0, "programIdx": 0},
                {"chIdx": 1, "name": "Channel 2", "cmIdx": 1, "programIdx": 0},
                {"chIdx": 2, "name": "Channel 3", "cmIdx": 2, "programIdx": 0},
                {"chIdx": 3, "name": "Channel 4", "cmIdx": 3, "programIdx": 0}
            ]
            """
        ]
    )

    /// Generic MIDI 2.0 device preset
    ///
    /// Basic device with minimal resources.
    public static func generic(
        name: String = "Mock Device",
        manufacturer: String = "MIDI2Kit"
    ) -> MockDevicePreset {
        MockDevicePreset(
            identity: DeviceIdentity(
                manufacturerID: .standard(0x7D),  // Educational/Development
                familyID: 0x0001,
                modelID: 0x0001,
                versionID: 0x01000000
            ),
            categorySupport: .propertyExchange,
            resources: [
                "DeviceInfo": """
                {
                    "manufacturerId": [125],
                    "familyId": [1, 0],
                    "modelId": [1, 0],
                    "versionId": [0, 0, 0, 1],
                    "manufacturer": "\(manufacturer)",
                    "family": "\(name)",
                    "model": "\(name)",
                    "version": "1.0.0"
                }
                """,

                "ResourceList": """
                [
                    {"resource": "DeviceInfo"},
                    {"resource": "ResourceList"}
                ]
                """
            ]
        )
    }

    /// Roland-style device preset
    public static let rolandStyle = MockDevicePreset(
        identity: DeviceIdentity(
            manufacturerID: .standard(0x41),  // Roland
            familyID: 0x0010,
            modelID: 0x0001,
            versionID: 0x02000000
        ),
        categorySupport: .propertyExchange,
        resources: [
            "DeviceInfo": """
            {
                "manufacturerId": [65],
                "familyId": [16, 0],
                "modelId": [1, 0],
                "versionId": [0, 0, 0, 2],
                "manufacturer": "Roland",
                "family": "Test Device",
                "model": "TD-01",
                "version": "2.0.0"
            }
            """,

            "ResourceList": """
            [
                {"resource": "DeviceInfo"},
                {"resource": "ResourceList"},
                {"resource": "PatchList"}
            ]
            """,

            "PatchList": """
            [
                {"idx": 0, "name": "Init Patch"},
                {"idx": 1, "name": "Lead Synth"},
                {"idx": 2, "name": "Pad"},
                {"idx": 3, "name": "Bass"}
            ]
            """
        ]
    )

    /// Yamaha-style device preset
    public static let yamahaStyle = MockDevicePreset(
        identity: DeviceIdentity(
            manufacturerID: .standard(0x43),  // Yamaha
            familyID: 0x0020,
            modelID: 0x0001,
            versionID: 0x03000000
        ),
        categorySupport: .propertyExchange,
        resources: [
            "DeviceInfo": """
            {
                "manufacturerId": [67],
                "familyId": [32, 0],
                "modelId": [1, 0],
                "versionId": [0, 0, 0, 3],
                "manufacturer": "Yamaha",
                "family": "Test Synth",
                "model": "YS-01",
                "version": "3.0.0"
            }
            """,

            "ResourceList": """
            [
                {"resource": "DeviceInfo"},
                {"resource": "ResourceList"},
                {"resource": "VoiceList"}
            ]
            """,

            "VoiceList": """
            [
                {"voiceId": 0, "name": "Grand Piano"},
                {"voiceId": 1, "name": "Bright Piano"},
                {"voiceId": 2, "name": "Stage EP"},
                {"voiceId": 3, "name": "DX Piano"}
            ]
            """
        ]
    )

    /// Minimal device with only required resources
    public static let minimal = MockDevicePreset(
        identity: .default,
        categorySupport: .propertyExchange,
        resources: [
            "DeviceInfo": """
            {
                "manufacturer": "Test",
                "model": "Minimal"
            }
            """,

            "ResourceList": """
            [
                {"resource": "DeviceInfo"},
                {"resource": "ResourceList"}
            ]
            """
        ]
    )
}

// MARK: - CustomStringConvertible

extension MockDevicePreset: CustomStringConvertible {
    public var description: String {
        let resourceNames = resources.keys.sorted().joined(separator: ", ")
        return "MockDevicePreset(identity: \(identity), resources: [\(resourceNames)])"
    }
}
