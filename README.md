# MIDI2Kit

A modern Swift library for MIDI 2.0 / MIDI-CI / Property Exchange.

## Features

- **MIDI2Core** - Foundation types (MUID, UMP, DeviceIdentity)
- **MIDI2CI** - Capability Inquiry (Discovery, Protocol Negotiation, Profiles)
- **MIDI2PE** - Property Exchange (Get/Set resources, Subscriptions)
- **MIDI2Transport** - CoreMIDI integration

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/hakaru/MIDI2Kit.git", from: "1.0.0")
]
```

## Usage

```swift
import MIDI2Kit

// Create a session
let session = try await MIDI2Session(clientName: "MyApp")

// Start discovery
session.startDiscovery()

// Get device info
for device in session.discoveredDevices {
    let info = try await session.getDeviceInfo(from: device.id)
    print("\(info.productName) by \(info.manufacturerName)")
}
```

## Modules

### MIDI2Core

```swift
import MIDI2Core

let muid = MUID.random()
let identity = DeviceIdentity(
    manufacturerID: .standard(0x42),  // KORG
    familyID: 0x0001,
    modelID: 0x0001,
    versionID: 0x00010000
)
```

### MIDI2CI

```swift
import MIDI2CI

let manager = CIManager(muid: .random())
let devices = try await manager.startDiscovery()

for await device in devices {
    print("Found: \(device.identity)")
}
```

### MIDI2PE

```swift
import MIDI2PE

let pe = PEManager(ciManager: manager)
let controllers: [PEControllerDef] = try await pe.get(
    resource: "ChCtrlList",
    from: device.id
)
```

## License

MIT License
