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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.9/MIDI2Core.xcframework.zip",
            checksum: "88d6b5cfca5f2563f9154c2f26ee7884d760f07ba8f768c6746bf49250b379f2"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.9/MIDI2Transport.xcframework.zip",
            checksum: "7bedcb3ccf57997b3e986c9445bb08bc6122c13a217cebf40edf05dc83c353bb"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.9/MIDI2CI.xcframework.zip",
            checksum: "b1515272d0efae65b31e3098c6d8ee49cecd5ddbcef52dbe698e57cd1b7f7154"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.9/MIDI2PE.xcframework.zip",
            checksum: "4eea5c8bc42906f2276c78018edc904e2892c28c5d8d27b6dbe684b0139afebf"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.9/MIDI2Kit.xcframework.zip",
            checksum: "fe0fd5ea24c53e8024012c76f2326eaf2584be4a8edc6bfa8d73f25ad46afefc"
        )
    ]
)
