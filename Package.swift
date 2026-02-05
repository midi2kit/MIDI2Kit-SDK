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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.2/MIDI2Core.xcframework.zip",
            checksum: "ede7730a857ab8cf8fe7754bb7fbc9f6c8c9eeb79c585f26bfbbadffc08b8a72"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.2/MIDI2Transport.xcframework.zip",
            checksum: "92edcdfda95887f73fc5d806a9a5f11ed0f6f9f39e2cff27291cee72d9de03f4"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.2/MIDI2CI.xcframework.zip",
            checksum: "61a23bcb522754a5388a840e22bb6b616ae73bfb883e9580154aa55a22d4b215"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.2/MIDI2PE.xcframework.zip",
            checksum: "22338d4702e0e7239cf7f823fe27127eacca93cc1b1e18e621fe5ef403d3cfa8"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.2/MIDI2Kit.xcframework.zip",
            checksum: "d0d07259f784560727a05bd4c81833cc90db9e25817aa805873cf1f180024ff7"
        )
    ]
)
