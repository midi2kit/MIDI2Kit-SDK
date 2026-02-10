# MIDI2Kit-SDK

Pre-built XCFramework binaries for [MIDI2Kit](https://github.com/hakaru/MIDI2Kit) - A modern Swift library for MIDI 2.0 / MIDI-CI / Property Exchange on Apple platforms.

## Recent Updates

### v1.0.12 (2026-02-10)
- **PEResponder Enhancements**: Subscribe dedup, stale subscription cleanup, targeted reply destinations
- **UMP SysEx7 Bidirectional Conversion**: MIDI 1.0 SysEx ⇔ UMP Data 64 with multi-packet fragmentation
- **RPN/NRPN → MIDI 1.0 CC**: Approximation converters for MIDI 1.0 fallback
- **PE Notify Fix**: Correct handling for MIDI-CI v1.1 devices
- **SysEx7 Fragment Reassembly**: CoreMIDITransport receive path reassembly
- 564 tests passing

### v1.0.11 (2026-02-06)
- **Virtual MIDI Endpoint**: Inter-app MIDI communication support

### v1.0.10 (2026-02-06)
- **AnyCodableValue**: Type-safe container for heterogeneous JSON values
- **X-Resource Fallback**: Auto-try X-prefixed resources before standard resources

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/midi2kit/MIDI2Kit-SDK.git", from: "1.0.12")
]
```

Or in Xcode:
1. File > Add Package Dependencies...
2. Enter: `https://github.com/midi2kit/MIDI2Kit-SDK.git`
3. Select "Up to Next Major Version" starting from `1.0.9`

## Available Modules

| Module | Description |
|--------|-------------|
| `MIDI2Core` | Foundation types, UMP messages, constants |
| `MIDI2Transport` | CoreMIDI integration with connection management |
| `MIDI2CI` | MIDI Capability Inquiry protocol (device discovery) |
| `MIDI2PE` | Property Exchange (GET/SET device properties) |
| `MIDI2Kit` | High-level unified API (recommended) |

## Quick Start

```swift
import MIDI2Kit

// Create client with standard configuration
let client = try MIDI2Client(name: "MyApp")

// Start and wait for devices
try await client.start()

// Listen for device discovery
for await event in await client.makeEventStream() {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.displayName)")

        // Get device info via Property Exchange
        if device.supportsPropertyExchange {
            let info = try await client.getDeviceInfo(from: device.muid)
            print("Manufacturer: \(info.manufacturerName ?? "Unknown")")
        }

    case .deviceLost(let muid):
        print("Lost device: \(muid)")

    default:
        break
    }
}
```

## KORG Device Optimization (v1.0.8+)

For KORG BLE MIDI devices like KORG Module Pro, use the optimized preset:

```swift
// KORG BLE MIDI optimized preset
let client = try MIDI2Client(name: "MyApp", preset: .korgBLEMIDI)
```

### 99% Faster PE Operations

Use `getOptimizedResources()` for dramatically faster parameter fetching:

```swift
// Standard path: ~16.4 seconds (ResourceList → parameters)
// Optimized path: ~144ms (direct X-ParameterList)
let result = try await client.getOptimizedResources(from: device.muid)

for param in result.parameters {
    print("\(param.name): CC\(param.controlCC)")
}
```

### KORG-Specific APIs (v1.0.8+)

```swift
// Get X-ParameterList directly
let params = try await client.getXParameterList(from: device.muid)

// Get X-ProgramEdit (current program data)
let program = try await client.getXProgramEdit(from: device.muid)

// Get channel-specific program
let ch1Program = try await client.getXProgramEdit(channel: 0, from: device.muid)
```

### ChannelList / ProgramList with Auto-Conversion (v1.0.9+)

```swift
// Automatically detects KORG format and converts to standard format
let channels = try await client.getChannelList(from: device.muid)
for channel in channels {
    print("Channel: \(channel.title ?? "Unknown")")
    print("Bank MSB: \(channel.bankMSB ?? 0)")
    print("Bank LSB: \(channel.bankLSB ?? 0)")
    print("Program: \(channel.programNumber ?? 0)")
}

let programs = try await client.getProgramList(from: device.muid)
for program in programs {
    print("Program: \(program.name ?? "Unknown")")
}
```

## Adaptive WarmUp Strategy (v1.0.8+)

Configure warm-up behavior for optimal performance:

```swift
var config = MIDI2ClientConfiguration()

// Options: .always, .never, .adaptive (default), .vendorBased
config.warmUpStrategy = .adaptive  // Learns per-device

// For KORG devices with vendor-specific optimization
config.vendorOptimizations = VendorOptimizationConfig(
    vendor: .korg,
    skipResourceList: true,
    useXParameterListAsWarmup: true
)

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

## Configuration

```swift
var config = MIDI2ClientConfiguration()

// Discovery settings
config.discoveryInterval = .seconds(5)
config.deviceTimeout = .seconds(30)

// PE settings
config.peTimeout = .seconds(10)
config.maxRetries = 3

// WarmUp strategy (v1.0.8+)
config.warmUpStrategy = .adaptive

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

**Available Presets:**
- `.korgBLEMIDI` - Optimized for KORG Module Pro and BLE MIDI devices
- `.standard` - Default settings for standard MIDI 2.0 devices

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Migration Guides

### v1.0.8 → v1.0.9

No breaking changes. New APIs added:
- `getChannelList(from:timeout:)` - Auto-detects vendor and selects appropriate resource
- `getProgramList(from:timeout:)` - Auto-detects vendor for ProgramList

### v1.0.4 → v1.0.8

New configuration property:
```swift
// warmUpBeforeResourceList is deprecated
// Use warmUpStrategy instead
config.warmUpStrategy = .adaptive  // Default in v1.0.8+
```

### v1.0.0 → v1.0.4

#### Breaking Change (v1.0.1)
Module name changed:

```swift
// Before (v1.0.0)
import MIDI2Client

// After (v1.0.1+)
import MIDI2Kit
```

#### KORG BLE MIDI Optimization (v1.0.4)
The `.korgBLEMIDI` preset is consolidated:

```swift
// Recommended preset for KORG devices
let client = try MIDI2Client(name: "MyApp", preset: .korgBLEMIDI)
```

## Logging

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
}
```

## Known Limitations

### KORG Module Pro

- **DeviceInfo**: ✅ Works reliably
- **ResourceList**: ⚠️ May timeout due to BLE chunk loss (use `getOptimizedResources()` instead)
- **X-ParameterList**: ✅ Fast and reliable (recommended)

**Workaround** (if ResourceList fails):
```swift
// Use optimized path (v1.0.8+)
let result = try await client.getOptimizedResources(from: device.muid)

// Or access known resources directly
let response = try await client.get("CMList", from: device.muid)
let response = try await client.get("ChannelList", from: device.muid)
```

## Source Code

For source code and detailed documentation, see the main repository:
https://github.com/hakaru/MIDI2Kit

## License

MIT License - See LICENSE file in the main repository.
