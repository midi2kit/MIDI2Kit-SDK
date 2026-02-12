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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.15/MIDI2Core.xcframework.zip",
            checksum: "af00144c38cbe6b9b7fb90af3382a809886aa827bfb4ad2fbe2a00daff1af69a"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.15/MIDI2Transport.xcframework.zip",
            checksum: "c6bcadefb12ac9d6da877b9d5c4d76b6f87dd28856fb47e5cf36761e7e97d65a"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.15/MIDI2CI.xcframework.zip",
            checksum: "62a34cb37b3aa412e9ee99d61974fb5f8856b557fb49365e41798446125727d8"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.15/MIDI2PE.xcframework.zip",
            checksum: "07d3d536df744690c861cf6b2cb1334526e84259bd00fa9fe24e90c0b71b4412"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.15/MIDI2Kit.xcframework.zip",
            checksum: "2e435a742d23bd778cbb931f2943a3d306441ba66d634ade0415b278618a55d9"
        )
    ]
)
