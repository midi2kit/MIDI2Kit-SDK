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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.11/MIDI2Core.xcframework.zip",
            checksum: "3f73e43b77bb50b9cbc147608e707497cfc40e2f2848ca20e8ff8d1de27a4339"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.11/MIDI2Transport.xcframework.zip",
            checksum: "2c67a19cf77714d909cf5c9c5e6149d902b85f23e16f0455ba4d291f107bbdbf"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.11/MIDI2CI.xcframework.zip",
            checksum: "9595ce7425647f8619ccf3a1b5eb6b3167ab29f86dbb28e56ba1bd48716ff4f7"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.11/MIDI2PE.xcframework.zip",
            checksum: "c7ab58a34b97aaa711a49415a500757b9a5d61876de73913faafd7be4f258204"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.11/MIDI2Kit.xcframework.zip",
            checksum: "560adc213494f2f86c55a182a700a8bb3c3eed18a84ead2dfe1943a766c8fbfe"
        )
    ]
)
