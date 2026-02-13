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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.18/MIDI2Core.xcframework.zip",
            checksum: "8359e7c3d2bab7d249515a628577c4a991192eada76f7ebf9a3111f6dcacdefd"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.18/MIDI2Transport.xcframework.zip",
            checksum: "fef5e5ad7d6228269d1e08fdb1512fd820271b34f96ffec1e1a66f0e31281adb"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.18/MIDI2CI.xcframework.zip",
            checksum: "6d92d5044d75b9d0d3e1665c99a07ba37c5c20deb428c8ebece9814ca03faac8"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.18/MIDI2PE.xcframework.zip",
            checksum: "9e1670e69359e2c4fdc39d1021b499d620bb281308e07b87e1cd992a6f10680a"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.18/MIDI2Kit.xcframework.zip",
            checksum: "bf823830a25f35f3816db7ffeed8aed300c082f2e2c98a4c0c194f5b2ff32d2f"
        )
    ]
)
