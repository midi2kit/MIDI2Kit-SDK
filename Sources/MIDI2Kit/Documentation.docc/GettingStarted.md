# Getting Started with MIDI2Kit

Learn how to set up MIDI2Kit and discover your first MIDI 2.0 device.

## Overview

This guide walks you through the basic setup of MIDI2Kit, from installation to discovering your first MIDI-CI compatible device.

## Installation

Add MIDI2Kit to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/midi2kit/midi2kit-core.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["MIDI2Kit"]
)
```

## Setting Up the Transport

MIDI2Kit uses a transport abstraction for MIDI I/O. For production apps, use `CoreMIDITransport`:

```swift
import MIDI2Kit

let transport = try CoreMIDITransport(clientName: "MyApp")
```

## Creating the CI Manager

The `CIManager` handles MIDI-CI device discovery:

```swift
let ciManager = CIManager(transport: transport)
try await ciManager.start()
```

## Discovering Devices

Listen for discovery events using Swift's async/await:

```swift
for await event in ciManager.events {
    switch event {
    case .deviceDiscovered(let device):
        print("Found device: \(device.displayName)")
        print("MUID: \(device.muid)")
        print("Supports PE: \(device.supportsPropertyExchange)")
        
    case .deviceLost(let muid):
        print("Device lost: \(muid)")
        
    default:
        break
    }
}
```

## Next Steps

- Learn about <doc:BasicConcepts> to understand UMP, MUID, and MIDI-CI
- Explore Property Exchange with ``PEManager``
- Check out the ``CIManager`` reference for advanced configuration
