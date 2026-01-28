# ``MIDI2Kit``

A Swift library for MIDI 2.0 / MIDI-CI / Property Exchange on Apple platforms.

## Overview

MIDI2Kit provides both high-level and low-level APIs for MIDI 2.0 communication.

### High-Level API (Recommended)

The `MIDI2Client` actor provides a unified, easy-to-use interface:

```swift
import MIDI2Kit

// Create and start
let client = try MIDI2Client(name: "MyApp")
try await client.start()

// Listen for devices
for await event in await client.makeEventStream() {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.displayName)")
        
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

// Clean shutdown
await client.stop()
```

### Low-Level API

For advanced use cases, use the individual managers directly:

```swift
let transport = try CoreMIDITransport(clientName: "MyApp")
let ciManager = CIManager(transport: transport)
let peManager = PEManager(transport: transport, sourceMUID: myMUID)
```

## Topics

### High-Level API

- ``MIDI2Client``
- ``MIDI2ClientConfiguration``
- ``MIDI2ClientEvent``
- ``MIDI2Device``
- ``MIDI2Error``
- ``MIDI2Logger``
- ``DestinationStrategy``
- ``ClientPreset``

### Guides

- <doc:GettingStarted>
- <doc:BasicConcepts>

### Device Discovery (Low-Level)

- ``CIManager``
- ``CIManagerConfiguration``
- ``CIManagerEvent``
- ``DiscoveredDevice``

### Property Exchange (Low-Level)

- ``PEManager``
- ``PERequest``
- ``PEResponse``
- ``PEError``
- ``PEDeviceHandle``
- ``PEDeviceInfo``
- ``PEResourceEntry``

### Core Types

- ``MUID``
- ``DeviceIdentity``
- ``CategorySupport``
- ``ManufacturerID``

### Transport

- ``MIDITransport``
- ``CoreMIDITransport``

### Modules

- <doc:MIDI2Core>
- <doc:MIDI2CI>
- <doc:MIDI2PE>
- <doc:MIDI2Transport>
