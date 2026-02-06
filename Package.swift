// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MIDI2Kit-SDK",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Individual modules for fine-grained dependency control
        .library(name: "MIDI2Core", targets: ["MIDI2Core"]),
        .library(name: "MIDI2Transport", targets: ["MIDI2Transport"]),
        .library(name: "MIDI2CI", targets: ["MIDI2CI"]),
        .library(name: "MIDI2PE", targets: ["MIDI2PE"]),

        // High-level API (use this for most applications)
        .library(name: "MIDI2Kit", targets: ["MIDI2Kit"])
    ],
    targets: [
        .binaryTarget(
            name: "MIDI2Core",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.10/MIDI2Core.xcframework.zip",
            checksum: "f2cd189dce790038a92d173601f0c60a3b36524fedc2ad1f0daedfb3435d7176"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.10/MIDI2Transport.xcframework.zip",
            checksum: "50362da54408abef4d40576d65307dfd51787295b5394c6ac906ef67f033b04b"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.10/MIDI2CI.xcframework.zip",
            checksum: "7e74833b03ac8524ac45e16613b37835f3d8b30e3af57f53513667e67e93b6bc"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.10/MIDI2PE.xcframework.zip",
            checksum: "8b87b63d9406be15f103f3a4562dad21435c6a472a0ea9ede83caf20b6a024d0"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.10/MIDI2Kit.xcframework.zip",
            checksum: "756c744e034a6ecac95d328145f7bc4d62515c47090c5cdae6c07afb516cf85f"
        )
    ]
)
