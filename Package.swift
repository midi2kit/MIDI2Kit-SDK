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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.5/MIDI2Core.xcframework.zip",
            checksum: "34f6bb3ad08aed5a571a2393ff906f7c27c9156163178b475edf7492a4e095df"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.5/MIDI2Transport.xcframework.zip",
            checksum: "16568c1deca7ec7f19e33991f8fa95ae17628fe8ab99646ee858852f07663525"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.5/MIDI2CI.xcframework.zip",
            checksum: "9e39719f1819465a09ebc4ad38af6098cf38e023cd121554692d1e5ba21d7fc6"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.5/MIDI2PE.xcframework.zip",
            checksum: "b303ba82f31fb1da137e4130f50793e7723a7f6f5a51d60ea372778ab3a4b81f"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.5/MIDI2Kit.xcframework.zip",
            checksum: "d385212021c984579b8953fbc5b0993ab3b9a4b67ad258e9452b14b9799a4db1"
        )
    ]
)
