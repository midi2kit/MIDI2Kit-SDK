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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.17/MIDI2Core.xcframework.zip",
            checksum: "8b7d09403327db4b7783bef43b3c955f713e11317abdb00973edccb522e21cb8"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.17/MIDI2Transport.xcframework.zip",
            checksum: "77fa31b28a122cc167be6dbac2cf1b9c97c4563d541d140a61bc00552280bc7b"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.17/MIDI2CI.xcframework.zip",
            checksum: "cb16a9f3cda6f5862cc31a93defa550ede9d12926adf0de8b4169906c24d6de8"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.17/MIDI2PE.xcframework.zip",
            checksum: "d8396f87a8c7c55eb8eaac61143fafdabef64df08bb39998df885f07c4621b27"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.17/MIDI2Kit.xcframework.zip",
            checksum: "b155525f2c825e5a999dd304e4895599ca52f26aa3c64b361151bc9ddf775197"
        )
    ]
)
