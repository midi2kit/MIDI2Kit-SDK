# MIDI2Kit-SDK

Pre-built XCFramework binaries for [MIDI2Kit](https://github.com/hakaru/MIDI2Kit) - A modern Swift library for MIDI 2.0 / MIDI-CI / Property Exchange on Apple platforms.

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/midi2kit/MIDI2Kit-SDK.git", from: "1.0.4")
]
```

Or in Xcode:
1. File > Add Package Dependencies...
2. Enter: `https://github.com/midi2kit/MIDI2Kit-SDK.git`
3. Select "Up to Next Major Version" starting from `1.0.4`

## Available Modules

| Module | Description |
|--------|-------------|
| `MIDI2Core` | Foundation types, UMP messages, constants |
| `MIDI2Transport` | CoreMIDI integration with connection management |
| `MIDI2CI` | MIDI Capability Inquiry protocol (device discovery) |
| `MIDI2PE` | Property Exchange (GET/SET device properties) |
| `MIDI2Kit` | High-level unified API (recommended) |

## Usage

### Quick Start

```swift
import MIDI2Kit

// Create client with standard configuration
let client = MIDI2Client(configuration: .standard)

// Start and wait for devices
try await client.start()

// Listen for device discovery
for await event in client.events {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.deviceIdentity)")

        // Get device info via Property Exchange
        if let info = try? await client.getDeviceInfo(from: device.muid) {
            print("Manufacturer: \(info.manufacturerName)")
        }

    case .deviceLost(let muid):
        print("Lost device: \(muid)")

    default:
        break
    }
}
```

### KORG BLE MIDI Devices

Use the optimized preset for BLE MIDI devices like KORG Module Pro:

```swift
// Optimized preset for KORG BLE MIDI devices
let client = MIDI2Client(configuration: .explorer)
```

The `.explorer` preset includes the following optimizations:
- Uses `broadcast` strategy for Property Exchange
- Fixes PE timeout issues (improved KORG BLE MIDI compatibility)
- Improved device auto-detection (`registerFromInquiry = true`)

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Migration Guides

### v1.0.0 → v1.0.4

#### Breaking Change (v1.0.1)
Module name has been changed:

```swift
// Before (v1.0.0)
import MIDI2Client

// After (v1.0.1+)
import MIDI2Kit
```

#### Behavior Change (v1.0.3)
Device discovery behavior has been improved:
- Default value of `registerFromInquiry` changed from `false` to `true`
- Improved compatibility with KORG and similar devices
- No code changes required (unless you explicitly set this option)

#### KORG BLE MIDI Optimization (v1.0.4)
The `.korgBLEMIDI` preset has been consolidated into `.explorer`:

```swift
// Before (v1.0.3 and earlier)
let client = MIDI2Client(configuration: .korgBLEMIDI)

// After (v1.0.4+) - Recommended
let client = MIDI2Client(configuration: .explorer)
```

`.korgBLEMIDI` is kept for compatibility, but `.explorer` is recommended.

## Source Code

For source code and detailed documentation, see the main repository:
https://github.com/hakaru/MIDI2Kit

## License

MIT License - See LICENSE file in the main repository.
