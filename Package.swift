// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MIDI2Kit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        // Full library with all features
        .library(
            name: "MIDI2Kit",
            targets: ["MIDI2Kit"]
        ),
        // Individual modules for selective import
        .library(
            name: "MIDI2Core",
            targets: ["MIDI2Core"]
        ),
        .library(
            name: "MIDI2CI",
            targets: ["MIDI2CI"]
        ),
        .library(
            name: "MIDI2PE",
            targets: ["MIDI2PE"]
        ),
        .library(
            name: "MIDI2Transport",
            targets: ["MIDI2Transport"]
        ),

        // MARK: - Dynamic libraries for XCFramework distribution
        .library(
            name: "MIDI2CoreDynamic",
            type: .dynamic,
            targets: ["MIDI2Core"]
        ),
        .library(
            name: "MIDI2TransportDynamic",
            type: .dynamic,
            targets: ["MIDI2Transport"]
        ),
        .library(
            name: "MIDI2CIDynamic",
            type: .dynamic,
            targets: ["MIDI2CI"]
        ),
        .library(
            name: "MIDI2PEDynamic",
            type: .dynamic,
            targets: ["MIDI2PE"]
        ),
        .library(
            name: "MIDI2KitDynamic",
            type: .dynamic,
            targets: ["MIDI2Kit"]
        ),
        // Example executable for real device testing
        .executable(
            name: "RealDeviceTest",
            targets: ["RealDeviceTest"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        // MARK: - Core Module
        // Foundation types: MUID, UMP, DeviceIdentity, etc.
        .target(
            name: "MIDI2Core",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // MARK: - MIDI-CI Module
        // Capability Inquiry: Discovery, Protocol Negotiation, Profile Configuration
        .target(
            name: "MIDI2CI",
            dependencies: ["MIDI2Core", "MIDI2Transport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // MARK: - Property Exchange Module
        // PE: Get/Set resources, Subscription, Chunk handling
        .target(
            name: "MIDI2PE",
            dependencies: ["MIDI2Core", "MIDI2CI", "MIDI2Transport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // MARK: - Transport Module
        // CoreMIDI integration, SysEx assembly
        .target(
            name: "MIDI2Transport",
            dependencies: ["MIDI2Core"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // MARK: - Umbrella Module
        // Re-exports all modules for convenience
        .target(
            name: "MIDI2Kit",
            dependencies: ["MIDI2Core", "MIDI2CI", "MIDI2PE", "MIDI2Transport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // MARK: - Examples
        .executableTarget(
            name: "RealDeviceTest",
            dependencies: ["MIDI2Kit", "MIDI2Transport"],
            path: "Examples/RealDeviceTest",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "MIDI2KitTests",
            dependencies: [
                "MIDI2Kit",
                "MIDI2Core",
                "MIDI2Transport",
                "MIDI2CI",
                "MIDI2PE"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
