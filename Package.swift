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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.3/MIDI2Core.xcframework.zip",
            checksum: "cf16a16ab3b3ca07aa7537e486be354b7a3e3f1d171dbad5b44b0734cba292f5"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.3/MIDI2Transport.xcframework.zip",
            checksum: "07159a99a0815514f6e9254bf0b104be9861e1af0d3f4649117d61b353dbe9ca"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.3/MIDI2CI.xcframework.zip",
            checksum: "9606f020e180829d18c16ce4009578b44beac6d70f8bf1e40c8749a5f37212cd"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.3/MIDI2PE.xcframework.zip",
            checksum: "a88894f8056a04f9d55ed8910e368d2c4f69d232602e96f723e2b006d3e41a10"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.3/MIDI2Kit.xcframework.zip",
            checksum: "794127a672fb003bae4ca2eb5b1925de28cd0dc8987f5032a5ee1589a0ab0c36"
        )
    ]
)
