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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.4/MIDI2Core.xcframework.zip",
            checksum: "925f818305507f684cf397c962281cc98df193af3200874dabc6d3db3dd12e7b"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.4/MIDI2Transport.xcframework.zip",
            checksum: "2a79f3ec6bab0bd743965d51961cf42c469c6f590911f7d4e1d264e52e7eed5e"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.4/MIDI2CI.xcframework.zip",
            checksum: "e009c51c2f534db5983363d363158290a354c40ed7bf6ec7a528649ccae8f88c"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.4/MIDI2PE.xcframework.zip",
            checksum: "f614034aeee5d8d65d049610fd756c55d4ddf7f8f09a1bdaabc100c678f3ed6c"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.4/MIDI2Kit.xcframework.zip",
            checksum: "82220864e16fa5d233b5274d38e3a66a51fa0cdd4e56ee5556b28b4b5d5a2fc3"
        )
    ]
)
