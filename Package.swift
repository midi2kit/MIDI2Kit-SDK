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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.7/MIDI2Core.xcframework.zip",
            checksum: "8c3e522e57ef3952187101ccc17ca18cbab6a2b335608e44edb8243b674fa236"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.7/MIDI2Transport.xcframework.zip",
            checksum: "5413b4a30d4dbbb24cf8088a7796666a1712b4eedcd3aa47a2fbe9a172ab70c9"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.7/MIDI2CI.xcframework.zip",
            checksum: "6f94f14b0bb8d9341b4f8b5a82cd5c2be5c830b965f729f803a57998089c0cc6"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.7/MIDI2PE.xcframework.zip",
            checksum: "8e2b73714a76036518a538e20b5bedcdecc4f45c8974b2002c17530294c066ab"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.7/MIDI2Kit.xcframework.zip",
            checksum: "414e82a03d7418a9a051a7de79f7e41aefa300cfe6ceeebf3555aa66a645f534"
        )
    ]
)
