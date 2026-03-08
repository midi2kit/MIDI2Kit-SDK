# Getting Started with MIDI2Kit

Set up MIDI2Kit in your project and discover your first MIDI 2.0 device.

## Overview

This guide walks you through adding MIDI2Kit to your project, creating a client, discovering devices, and performing a basic Property Exchange operation. By the end, you'll have a working MIDI 2.0 integration that discovers devices and reads their properties.

## Installation

Add MIDI2Kit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/hakaru/MIDI2Kit.git", from: "1.0.0")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "MIDI2Kit", package: "MIDI2Kit")
    ]
)
```

Or in Xcode, go to **File → Add Package Dependencies** and enter the repository URL.

### Choosing Modules

For most applications, import `MIDI2Kit` — it re-exports all sub-modules:

```swift
import MIDI2Kit
```

For fine-grained control, import individual modules:

```swift
import MIDI2Core      // Foundation types (MUID, UMP, Mcoded7)
import MIDI2Transport // CoreMIDI access
import MIDI2CI        // Discovery only
import MIDI2PE        // Property Exchange only
```

## Creating a Client

``MIDI2Client`` is the main entry point. It wraps all sub-modules into a single actor:

```swift
import MIDI2Kit

let client = try MIDI2Client(name: "MyApp")
try await client.start()
```

### Configuration

Customize behavior with ``MIDI2ClientConfiguration``:

```swift
var config = MIDI2ClientConfiguration()
config.discoveryInterval = .seconds(5)   // How often to broadcast discovery
config.deviceTimeout = .seconds(30)      // When to consider a device lost
config.peTimeout = .seconds(10)          // Property Exchange timeout
config.maxRetries = 3                    // Retry count for failed PE requests

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

Or use built-in presets for specific device types:

```swift
// Optimized for KORG BLE MIDI devices (warm-up enabled, longer timeouts)
let client = try MIDI2Client(name: "MyApp", preset: .korgBLEMIDI)

// Standard MIDI 2.0 devices (default settings)
let client = try MIDI2Client(name: "MyApp", preset: .standard)
```

## Listening for Events

Use ``MIDI2Client/makeEventStream()`` to receive events via `AsyncStream`:

```swift
Task {
    for await event in await client.makeEventStream() {
        switch event {
        case .deviceDiscovered(let device):
            print("Found: \(device.displayName)")
            print("  MUID: \(device.muid)")
            print("  PE support: \(device.supportsPropertyExchange)")

        case .deviceLost(let muid):
            print("Lost: \(muid)")

        case .deviceUpdated(let device):
            print("Updated: \(device.displayName)")

        case .notification(let notification):
            print("PE subscription notification received")

        case .started:
            print("Client started, discovery running")

        case .stopped:
            print("Client stopped")
        }
    }
}
```

## Reading Device Properties

When a device supports Property Exchange, you can read its properties:

```swift
case .deviceDiscovered(let device):
    guard device.supportsPropertyExchange else { return }

    // 1. Get device information (typed response)
    let info = try await client.getDeviceInfo(from: device.muid)
    print("Manufacturer: \(info.manufacturerName ?? "Unknown")")
    print("Product: \(info.productName ?? "Unknown")")

    // 2. Get available resources
    let resources = try await client.getResourceList(from: device.muid)
    print("Available resources: \(resources.count)")

    // 3. Get a specific resource by name
    let response = try await client.get("CMList", from: device.muid)
    print("Status: \(response.status)")
```

### Using Cached Device Properties

``MIDI2Device`` provides cached property access that auto-fetches on first call:

```swift
let device: MIDI2Device = // from .deviceDiscovered event

// Cached access (auto-fetches on first call, returns cached on subsequent calls)
if let info = try await device.deviceInfo {
    print("Product: \(info.productName ?? "Unknown")")
}

// Force refresh from device
device.invalidateCache()
let freshInfo = try await device.deviceInfo
```

### Type-Safe Property Access

Decode device properties directly into your own types:

```swift
struct MyParameter: Codable {
    let name: String
    let value: Int
}

if let param = try await device.getProperty("X-MyParam", as: MyParameter.self) {
    print("\(param.name): \(param.value)")
}
```

## Writing Device Properties

Use PE SET to write data to a device:

```swift
let jsonData = #"{"channel": 1, "program": 42}"#.data(using: .utf8)!
try await client.set("CurrentProgram", data: jsonData, to: device.muid)
```

## Filtering Connections

Use ``MIDI2ConnectionPolicy`` to selectively connect to specific devices:

```swift
var config = MIDI2ClientConfiguration()
config.connectionPolicy = MIDI2ConnectionPolicy(
    allowedNames: [
        .prefix("iPad"),        // Names starting with "iPad"
        .contains("Pro"),       // Names containing "Pro"
        .exact("My Synth"),     // Exact match
        .suffix("BLE MIDI")    // Names ending with "BLE MIDI"
    ]
)

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

## Logging and Diagnostics

Enable logging to troubleshoot issues:

```swift
// Enable verbose logging
MIDI2Logger.isEnabled = true
MIDI2Logger.isVerbose = true

// Runtime diagnostics
let diag = await client.diagnostics
print(diag)

// Check last communication trace
if let trace = await client.lastCommunicationTrace {
    print(trace.description)
}
```

Filter logs in Console.app with `subsystem == "com.midi2kit"`.

## Clean Shutdown

Always stop the client when done:

```swift
await client.stop()
```

## Complete Example

Here's a minimal app that discovers devices and reads their info:

```swift
import MIDI2Kit

@main
struct MyMIDIApp {
    static func main() async throws {
        let client = try MIDI2Client(name: "MyMIDIApp")
        try await client.start()

        for await event in await client.makeEventStream() {
            switch event {
            case .deviceDiscovered(let device):
                print("Found: \(device.displayName)")
                if device.supportsPropertyExchange {
                    let info = try await client.getDeviceInfo(from: device.muid)
                    print("  Product: \(info.productName ?? "Unknown")")
                }
            case .deviceLost(let muid):
                print("Lost: \(muid)")
            default:
                break
            }
        }
    }
}
```

## Next Steps

- <doc:DeviceDiscovery> — Deep dive into MIDI-CI discovery with connection filtering
- <doc:PropertyExchange> — Working with PE GET/SET operations and subscriptions
- <doc:CreatingResponder> — Build a MIDI-CI Responder device
