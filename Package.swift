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
            checksum: "73b45f329fb01fae353ac6def302a105029e3975f5b06165bb0512cb02ad608a"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.8/MIDI2Transport.xcframework.zip",
            checksum: "38de8f210db9baac85d6d8d81d78d50e7501bff2135808215fc6dd0372cc6a27"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.8/MIDI2CI.xcframework.zip",
            checksum: "7c1aa443438bbdfb78ab3f6088591f53a36fff8e55e38a963f26f5e76ab3b48d"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.8/MIDI2PE.xcframework.zip",
            checksum: "6aa65497c072c306874f604768def654ad3b8a5311bafb5ba9416365b01f6ba4"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.8/MIDI2Kit.xcframework.zip",
            checksum: "48a6f1493164a46808dcd36ba61dfa823c38e89608bddf19e75735c6243fc839"
        )
    ]
)
