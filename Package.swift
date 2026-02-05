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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.1/MIDI2Core.xcframework.zip",
            checksum: "1d4c2129df647ad5ac1347326d5cf81c36335ba6e92847d1415be79a3b1bcdc8"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.1/MIDI2Transport.xcframework.zip",
            checksum: "4a8d22d0400bf3bf766b1f70c3fd27f4df860fa4550dfad33e5f79d13971da45"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.1/MIDI2CI.xcframework.zip",
            checksum: "083b2a44ce98f2ae49a443b7375a87fdb50e2e7d5474191eb06eeb740d8112ad"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.1/MIDI2PE.xcframework.zip",
            checksum: "39d1982e1f07a4cde986355cc6f4f0cebdaad350bd82e9f615f1f01a963227f7"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.1/MIDI2Kit.xcframework.zip",
            checksum: "0fb7231548fdc756825ccf3e46872b6b995b1e81153bf0f089af10022f56031d"
        )
    ]
)
