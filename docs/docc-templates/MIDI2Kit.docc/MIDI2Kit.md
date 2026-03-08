# ``MIDI2Kit``

A Swift library for MIDI 2.0, MIDI-CI, and Property Exchange on Apple platforms.

@Metadata {
    @DisplayName("MIDI2Kit")
}

## Overview

MIDI2Kit provides a high-level, Swift-native API for working with MIDI 2.0 devices. Built on Swift 6 strict concurrency with actor-based isolation, it handles device discovery, property exchange, subscription management, and UMP conversion.

```
MIDI2Core (Foundation - no dependencies)
    ^
    +-- MIDI2Transport (CoreMIDI abstraction)
    +-- MIDI2CI (Capability Inquiry / Discovery)
    +-- MIDI2PE (Property Exchange)
    +-- MIDI2Kit (High-Level API)
```

### Quick Start

```swift
import MIDI2Kit

let client = try MIDI2Client(name: "MyApp")
try await client.start()

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
```

### Modules

| Module | Purpose |
|--------|---------|
| ``MIDI2Core`` | Foundation types, UMP, constants |
| ``MIDI2Transport`` | CoreMIDI integration |
| ``MIDI2CI`` | Device discovery (MIDI-CI) |
| ``MIDI2PE`` | Property Exchange |
| ``MIDI2Kit`` | High-level unified API |

## Topics

### Essentials

- <doc:GettingStarted>
- ``MIDI2Client``
- ``MIDI2Device``
- ``MIDI2ClientEvent``
- ``MIDI2ClientConfiguration``

### Configuration

- ``MIDI2ClientConfiguration``
- ``MIDI2ConnectionPolicy``
- ``ClientPreset``
- ``DestinationStrategy``
- ``WarmUpStrategy``

### Error Handling

- ``MIDI2Error``

### Logging and Diagnostics

- ``MIDI2Logger``
- ``CommunicationTrace``

### Responder API

- ``MIDI2ResponderClient``

### Mock / Testing

- ``MockDevice``
- ``MockDevicePreset``

### Tutorials

- <doc:DeviceDiscovery>
- <doc:PropertyExchange>
- <doc:CreatingResponder>
