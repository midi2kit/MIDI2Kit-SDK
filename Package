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
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.12/MIDI2Core.xcframework.zip",
            checksum: "deada014523bf61cbab20890e6e26289eca4391a0580ee8095687757c0498374"
        ),
        .binaryTarget(
            name: "MIDI2Transport",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.12/MIDI2Transport.xcframework.zip",
            checksum: "839f8ea53c97d70f265911ddf7b502ee9d3b0d711b38e221c1bd5a4e204b05c7"
        ),
        .binaryTarget(
            name: "MIDI2CI",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.12/MIDI2CI.xcframework.zip",
            checksum: "248dda899867fb383c96be2075137a4ba029c2179fa7c32a8ccb23eaf4a480ae"
        ),
        .binaryTarget(
            name: "MIDI2PE",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.12/MIDI2PE.xcframework.zip",
            checksum: "f4fb32a0ca7581b4f4afbb1a21f249c46e400ff2a4741a7c5dca0cccdcdcb915"
        ),
        .binaryTarget(
            name: "MIDI2Kit",
            url: "https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.12/MIDI2Kit.xcframework.zip",
            checksum: "d700d2750fd7dbf5a559df932e9479027739b9186be8cc07bd537c006cf92559"
        )
    ]
)
