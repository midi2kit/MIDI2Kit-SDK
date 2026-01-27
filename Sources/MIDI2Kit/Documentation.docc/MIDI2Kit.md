# ``MIDI2Kit``

A Swift library for implementing MIDI 2.0 (UMP, MIDI-CI, Property Exchange) in macOS and iOS applications.

## Overview

MIDI2Kit provides a comprehensive, type-safe API for working with MIDI 2.0 protocols. It handles device discovery, capability inquiry, and property exchange with modern Swift concurrency patterns.

```swift
import MIDI2Kit

// Create transport and managers
let transport = try CoreMIDITransport(clientName: "MyApp")
let ciManager = CIManager(transport: transport)

// Start discovery
try await ciManager.start()

// Listen for devices
for await event in ciManager.events {
    if case .deviceDiscovered(let device) = event {
        print("Found: \(device.displayName)")
    }
}
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:BasicConcepts>

### Device Discovery

- ``CIManager``
- ``CIManagerConfiguration``
- ``CIManagerEvent``
- ``DiscoveredDevice``

### Property Exchange

- ``PEManager``
- ``PERequest``
- ``PEResponse``
- ``PEError``

### Core Types

- ``MUID``
- ``DeviceIdentity``
- ``UMPMessageType``
- ``UMPGroup``
- ``MIDIChannel``

### Transport

- ``MIDITransport``
- ``CoreMIDITransport``
- ``MockMIDITransport``

### Modules

- <doc:MIDI2Core>
- <doc:MIDI2CI>
- <doc:MIDI2PE>
- <doc:MIDI2Transport>
