# MIDI2Kit

A Swift library for MIDI 2.0 / MIDI-CI / Property Exchange on Apple platforms.

## Features

- **MIDI-CI Device Discovery** - Automatically discover MIDI 2.0 capable devices
- **Property Exchange** - Get and set device properties via PE protocol
- **High-Level API** - Simple `MIDI2Client` actor for common use cases
- **KORG Compatibility** - Works with KORG Module Pro and similar devices
- **Swift Concurrency** - Built with async/await and Sendable types

## Requirements

- iOS 16.0+ / macOS 13.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/hakaru/MIDI2Kit.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL.

## Quick Start

```swift
import MIDI2Kit

// Create and start the client
let client = try MIDI2Client(name: "MyApp")
try await client.start()

// Listen for device discovery
Task {
    for await event in await client.makeEventStream() {
        switch event {
        case .deviceDiscovered(let device):
            print("Found: \(device.displayName)")
            
            // Get device info if PE is supported
            if device.supportsPropertyExchange {
                let info = try await client.getDeviceInfo(from: device.muid)
                print("Product: \(info.productName ?? "Unknown")")
            }
            
        case .deviceLost(let muid):
            print("Lost: \(muid)")
            
        default:
            break
        }
    }
}

// Later: clean shutdown
await client.stop()
```

## Configuration

Customize behavior with `MIDI2ClientConfiguration`:

```swift
var config = MIDI2ClientConfiguration()

// Discovery settings
config.discoveryInterval = .seconds(5)
config.deviceTimeout = .seconds(30)

// PE settings
config.peTimeout = .seconds(10)
config.maxRetries = 3

// Create client with custom config
let client = try MIDI2Client(name: "MyApp", configuration: config)
```

Or use presets:

```swift
let client = try MIDI2Client(name: "MyApp", preset: .explorer)  // Longer timeouts
let client = try MIDI2Client(name: "MyApp", preset: .minimal)   // Short timeouts
```

## API Reference

### MIDI2Client

The main entry point for MIDI 2.0 operations.

| Method | Description |
|--------|-------------|
| `start()` | Start discovery and event processing |
| `stop()` | Stop and clean up all resources |
| `makeEventStream()` | Get an AsyncStream of events |
| `getDeviceInfo(from:)` | Get DeviceInfo from a device |
| `getResourceList(from:)` | Get available PE resources |
| `get(_:from:)` | Get a PE resource |
| `set(_:data:to:)` | Set a PE resource |

### MIDI2Device

Represents a discovered MIDI 2.0 device.

| Property | Description |
|----------|-------------|
| `muid` | Unique MIDI ID |
| `displayName` | Human-readable name |
| `supportsPropertyExchange` | PE capability |
| `manufacturerName` | Manufacturer (if known) |

### MIDI2ClientEvent

Events emitted by the client.

| Event | Description |
|-------|-------------|
| `.deviceDiscovered(device)` | New device found |
| `.deviceLost(muid)` | Device disconnected |
| `.deviceUpdated(device)` | Device info updated |
| `.notification(notification)` | PE subscription notification |
| `.started` / `.stopped` | Client lifecycle |

## Logging

MIDI2Kit uses `os.Logger` for efficient logging:

```swift
// Disable all logs
MIDI2Logger.isEnabled = false

// Enable verbose logging
MIDI2Logger.isVerbose = true
```

Filter logs in Console.app:
```
subsystem == "com.midi2kit"
```

## Known Limitations

### KORG Module Pro

- **DeviceInfo**: ✅ Works reliably
- **ResourceList**: ⚠️ May timeout due to chunk loss (KORG-side issue)

KORG devices use a non-standard PE format. MIDI2Kit handles this automatically, but multi-chunk responses (like ResourceList) may be unreliable due to CoreMIDI virtual port buffering issues.

**Workaround**: Access known resources directly instead of using ResourceList:
```swift
// Instead of:
let resources = try await client.getResourceList(from: device.muid)

// Access directly if you know the resource name:
let response = try await client.get("CMList", from: device.muid)
```

## Architecture

MIDI2Kit is organized into layers:

```
MIDI2Kit (High-Level API)
├── MIDI2Client      - Unified async client
├── MIDI2Device      - Device representation
└── Configuration    - Settings & presets

MIDI2PE (Property Exchange)
├── PEManager        - Request/response handling
└── PETransactionManager

MIDI2CI (Capability Inquiry)
├── CIManager        - Discovery protocol
└── CIMessageParser  - Message parsing

MIDI2Transport
└── CoreMIDITransport - Apple MIDI integration

MIDI2Core
└── Types, protocols, utilities
```

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions welcome! Please open an issue first to discuss proposed changes.
