# MIDI2Kit-SDK

Pre-built XCFramework binaries for [MIDI2Kit](https://github.com/hakaru/MIDI2Kit) - A modern Swift library for MIDI 2.0 / MIDI-CI / Property Exchange on Apple platforms.

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/midi2kit/MIDI2Kit-SDK.git", from: "1.0.0")
]
```

Or in Xcode:
1. File > Add Package Dependencies...
2. Enter: `https://github.com/midi2kit/MIDI2Kit-SDK.git`
3. Select "Up to Next Major Version" starting from `1.0.0`

## Available Modules

| Module | Description |
|--------|-------------|
| `MIDI2Core` | Foundation types, UMP messages, constants |
| `MIDI2Transport` | CoreMIDI integration with connection management |
| `MIDI2CI` | MIDI Capability Inquiry protocol (device discovery) |
| `MIDI2PE` | Property Exchange (GET/SET device properties) |
| `MIDI2Client` | High-level unified API (recommended) |
| `MIDI2Kit` | Umbrella library (alias for MIDI2Client) |

## Usage

### Quick Start

```swift
import MIDI2Client

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

```swift
// Use optimized configuration for KORG devices
let client = MIDI2Client(configuration: .korgBLEMIDI)
```

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Source Code

For source code and detailed documentation, see the main repository:
https://github.com/hakaru/MIDI2Kit

## License

MIT License - See LICENSE file in the main repository.
