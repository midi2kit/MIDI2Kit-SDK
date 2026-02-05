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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.6/MIDI2Core.xcframework.zip",
            checksum: "963eb1ff160634afa815abf74b568248234739e11d080beb5587a305a24b5de6"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.6/MIDI2Transport.xcframework.zip",
            checksum: "86e112b67ef4679e6f41886d3241fd1d78bd10e7427b20e89dd21a7f49be5a21"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.6/MIDI2CI.xcframework.zip",
            checksum: "0a0c4d707a6022d55f553ef8eba4fd751757c3400609a41318fd1a45774d4514"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.6/MIDI2PE.xcframework.zip",
            checksum: "11f6deaff713a4d9a35146738b83b46b8c7945e2ea5bb9c0c4e19a52da3d66b7"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.6/MIDI2Kit.xcframework.zip",
            checksum: "546d0081bd9faaba5d743fa1b8d1849c9e1be50e2a7108485dab317160490173"
        )
    ]
)
