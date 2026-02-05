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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.8/MIDI2Core.xcframework.zip",
            checksum: "118025ee47ef699d674d97f6c3d9a252ea9c6d658f3248af7335ff1d4389a9d0"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.8/MIDI2Transport.xcframework.zip",
            checksum: "9b586f355f00214fcce61a313ba7c1669c4f4f85fe11c136d78f4d567898ef2d"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.8/MIDI2CI.xcframework.zip",
            checksum: "4f239b1567480ed79806292758e591bb92e75992c2021dd6146d178c5e2f6272"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.8/MIDI2PE.xcframework.zip",
            checksum: "64f7ed73f24c4750979a7a6394170d98d575c2d3c7031ef7f77a7684b3b1efbd"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.8/MIDI2Kit.xcframework.zip",
            checksum: "9571668c5e702d936abce611aaa8517db10b59d2fc668a315b449e29c96b2638"
        )
    ]
)
