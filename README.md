# MIDI2Kit

A Swift library for MIDI 2.0 / MIDI-CI / Property Exchange on Apple platforms.

## Features

- **MIDI-CI Device Discovery** - Automatically discover MIDI 2.0 capable devices
- **Property Exchange** - Get and set device properties via PE protocol
- **Advanced SET Operations** - Payload validation, batch SET, and pipeline workflows
- **High-Level API** - Simple `MIDI2Client` actor for common use cases
- **KORG Optimization** - 99% faster PE operations with KORG devices (v1.0.8+)
- **Adaptive Warm-Up** - Automatic connection optimization with device learning
- **Swift Concurrency** - Built with async/await and Sendable types

## Requirements

- iOS 17.0+ / macOS 14.0+ / tvOS 17.0+ / watchOS 10.0+ / visionOS 1.0+
- Xcode 16.0+
- Swift 6.0+

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
// KORG BLE MIDI devices (warm-up enabled, longer timeouts)
let client = try MIDI2Client(name: "MyApp", preset: .korgBLEMIDI)

// Standard MIDI 2.0 devices (default settings)
let client = try MIDI2Client(name: "MyApp", preset: .standard)
```

**Available presets:**
- `.korgBLEMIDI` - Optimized for KORG Module Pro and BLE MIDI devices
- `.standard` - Default settings for standard MIDI 2.0 devices

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

Represents a discovered MIDI 2.0 device with cached property access.

| Property/Method | Description |
|----------|-------------|
| `muid` | Unique MIDI ID |
| `displayName` | Human-readable name |
| `supportsPropertyExchange` | PE capability |
| `manufacturerName` | Manufacturer (if known) |
| `deviceInfo` | Cached DeviceInfo (auto-fetched) |
| `resourceList` | Cached resource list (auto-fetched) |
| `getProperty<T>(_:as:)` | Type-safe property decoding |
| `invalidateCache()` | Force fresh fetch on next access |

**Example:**
```swift
let device: MIDI2Device = // from .deviceDiscovered event

// Cached access (auto-fetches on first call)
if let info = try await device.deviceInfo {
    print("Product: \(info.productName ?? "Unknown")")
}

// Type-safe property access
struct CustomProperty: Codable {
    let value: String
}
if let prop = try await device.getProperty("X-Custom", as: CustomProperty.self) {
    print("Custom: \(prop.value)")
}
```

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

## Debugging & Diagnostics

MIDI2Client provides diagnostic tools for troubleshooting:

```swift
// Get comprehensive diagnostics
let diag = await client.diagnostics
print(diag)

// Check destination resolution details
if let destDiag = await client.lastDestinationDiagnostics {
    print("Tried destinations: \(destDiag.triedOrder)")
    print("Resolved to: \(destDiag.resolvedDestination)")
}

// View last communication trace
if let trace = await client.lastCommunicationTrace {
    print(trace.description)
    // Shows: operation, MUID, resource, duration, result, errors
}
```

## Migration from Low-Level API

If you're using `CIManager` or `PEManager` directly, see the [Migration Guide](docs/MigrationGuide.md) for step-by-step instructions to migrate to `MIDI2Client`.

## Recent Updates

### v1.0.9 (2026-02-06)
- **KORG ChannelList/ProgramList Auto-Conversion**: Auto-convert KORG proprietary format (`bankPC: [Int]` array) to standard format
- **New APIs**: `getChannelList()`, `getProgramList()` - Auto-detect vendor and select appropriate resource

### v1.0.8 (2026-02-06)
- **KORG Optimization**: Skip ResourceList, directly fetch X-ParameterList (99% faster, 16.4s → 144ms)
- **Adaptive WarmUp Strategy**: Learn success/failure per device, auto-select optimal warmup strategy
- **KORG Extension APIs**: `getOptimizedResources()`, `getXParameterList()`, `getXProgramEdit()`

### v1.0.7 (2026-02-06)
- **AsyncStream fixes**: Race condition fixes in CoreMIDITransport, MockMIDITransport, LoopbackTransport, PESubscriptionManager

### v1.0.6 (2026-02-06)
- **Critical bug fix**: Fixed CIManager.events not firing (AsyncStream continuation race condition)

See [CHANGELOG.md](CHANGELOG.md) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and recent updates.

## Known Limitations

### KORG Module Pro

- **DeviceInfo**: ✅ Works reliably
- **ResourceList**: ⚠️ May timeout due to chunk loss (physical layer limitation)
- **Auto-Retry**: ✅ MIDI2Client automatically retries with fallback destinations

KORG devices use a non-standard PE format. MIDI2Kit handles this automatically, but multi-chunk responses (like ResourceList) may be unreliable over BLE MIDI due to packet loss.

**Built-in optimizations** (when using `.korgBLEMIDI` preset):
- Warm-up request before ResourceList to establish stable BLE connection
- Automatic destination fallback on timeout
- Extended timeout for multi-chunk responses

**Workaround** (if ResourceList still fails):
```swift
// Access known resources directly instead of using ResourceList:
let response = try await client.get("CMList", from: device.muid)
let response = try await client.get("ChannelList", from: device.muid)
```

## Architecture

MIDI2Kit is organized into 5 modular Swift Package Manager targets with clear dependency hierarchy:

```
MIDI2Core (Foundation - no dependencies)
    ↑
    ├─ MIDI2Transport (CoreMIDI abstraction)
    ├─ MIDI2CI (Capability Inquiry / Discovery)
    ├─ MIDI2PE (Property Exchange)
    └─ MIDI2Kit (High-Level API)
```

### Module Details

| Module | Purpose | Key Types |
|--------|---------|-----------|
| **MIDI2Core** | Foundation types, UMP messages, constants | `MUID`, `DeviceIdentity`, `UMPMessage`, `Mcoded7` |
| **MIDI2Transport** | CoreMIDI integration with connection management | `CoreMIDITransport`, `MIDITransport`, `SysExAssembler` |
| **MIDI2CI** | MIDI Capability Inquiry protocol (device discovery) | `CIManager`, `DiscoveredDevice`, `CIMessageParser` |
| **MIDI2PE** | Property Exchange (GET/SET device properties) | `PEManager`, `PETransactionManager`, `PESubscriptionManager` |
| **MIDI2Kit** | High-Level API - unified client for common use cases | `MIDI2Client`, `MIDI2Device`, `MIDI2ClientConfiguration` |

**Actor-Based Concurrency**: All managers are `actor` types for thread-safe isolation. All data types are `Sendable`. Swift Concurrency (async/await) is used throughout.

**Request ID Management**: PE supports max 128 concurrent requests (0-127) with automatic ID allocation, per-device inflight limiting, and request ID cooldown to prevent delayed response mismatches.

## Testing

MIDI2Kit includes comprehensive tests covering:

- **Unit Tests**: 196+ tests for individual components
- **Integration Tests**: End-to-end workflow tests including discovery, PE operations, error recovery
- **Real Device Tests**: Verified with KORG Module Pro and BLE MIDI devices

Run tests with:
```bash
swift test
```

## Security

MIDI2Kit follows secure coding practices:

- ✅ Swift 6 strict concurrency mode
- ✅ Actor isolation for thread safety
- ✅ Input validation (MUID, Mcoded7, PE requests)
- ✅ Buffer size limits (DoS prevention)
- ✅ Structured error handling with classification
- ✅ Minimal external dependencies

See [docs/security-audit-20260204.md](docs/security-audit-20260204.md) for detailed security audit report.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please open an issue first to discuss proposed changes.

## Additional Resources

- **KORG Optimization Guide**: [docs/KORG-Optimization.md](docs/KORG-Optimization.md) - 99% faster PE operations with KORG devices (v1.0.8+)
- **Migration Guide**: [docs/MigrationGuide.md](docs/MigrationGuide.md) - Migrate from low-level API to MIDI2Client
- **MIDI-CI Ecosystem Analysis**: [docs/MIDI-CI-Ecosystem-Analysis.md](docs/MIDI-CI-Ecosystem-Analysis.md) - Comparison with other MIDI-CI implementations
- **KORG Compatibility Notes**: [docs/KORG-Module-Pro-Limitations.md](docs/KORG-Module-Pro-Limitations.md) - Known issues and workarounds
- **Code Review Reports**: [docs/code-review-*.md](docs/) - Detailed code quality reviews
