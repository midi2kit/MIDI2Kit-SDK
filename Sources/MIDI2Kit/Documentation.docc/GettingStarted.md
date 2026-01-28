# Getting Started with MIDI2Kit

Learn how to set up MIDI2Kit and discover your first MIDI 2.0 device.

## Overview

This guide walks you through the basic setup of MIDI2Kit, from installation to discovering your first MIDI-CI compatible device and reading its properties.

## Installation

Add MIDI2Kit to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/hakaru/MIDI2Kit.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["MIDI2Kit"]
)
```

## Creating a Client

The recommended way to use MIDI2Kit is through `MIDI2Client`:

```swift
import MIDI2Kit

let client = try MIDI2Client(name: "MyApp")
try await client.start()
```

## Discovering Devices

Listen for device discovery events:

```swift
for await event in await client.makeEventStream() {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.displayName)")
        print("MUID: \(device.muid)")
        print("Supports PE: \(device.supportsPropertyExchange)")
        
    case .deviceLost(let muid):
        print("Lost: \(muid)")
        
    default:
        break
    }
}
```

## Reading Device Properties

If a device supports Property Exchange, you can read its properties:

```swift
if device.supportsPropertyExchange {
    // Get device information
    let info = try await client.getDeviceInfo(from: device.muid)
    print("Product: \(info.productName ?? "Unknown")")
    print("Manufacturer: \(info.manufacturer ?? "Unknown")")
    
    // Get available resources (may be unreliable on some devices)
    let resources = try await client.getResourceList(from: device.muid)
    for resource in resources {
        print("Resource: \(resource.resource)")
    }
}
```

## Configuration

Customize client behavior with configuration:

```swift
var config = MIDI2ClientConfiguration()
config.discoveryInterval = .seconds(5)  // Faster discovery
config.peTimeout = .seconds(10)         // Longer PE timeout
config.maxRetries = 3                   // More retries

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

Or use presets:

```swift
// For debugging/exploration
let client = try MIDI2Client(name: "MyApp", preset: .explorer)

// For quick testing
let client = try MIDI2Client(name: "MyApp", preset: .minimal)
```

## Cleaning Up

Always stop the client when done:

```swift
await client.stop()
```

## Next Steps

- Learn about <doc:BasicConcepts> to understand MUID, MIDI-CI, and Property Exchange
- See ``MIDI2Client`` for the full API reference
- Check ``MIDI2ClientConfiguration`` for all configuration options
