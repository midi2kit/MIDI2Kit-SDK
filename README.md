# MIDI2Kit

A modern Swift library for MIDI 2.0 / MIDI-CI / Property Exchange / UMP.

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20|%20macOS%2014-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- **MIDI2Core** - Foundation types (MUID, DeviceIdentity, Mcoded7, **UMP Builder/Parser**)
- **MIDI2CI** - Capability Inquiry (Discovery, Protocol Negotiation, Profiles)
- **MIDI2PE** - Property Exchange (Get/Set resources, Subscriptions, Transaction management)
- **MIDI2Transport** - CoreMIDI integration with duplicate connection prevention, **UMP support**
- **Per-device rate limiting** - Prevents overwhelming slow devices
- **Auto-reconnecting subscriptions** - Survives device disconnections

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/hakaru/MIDI2Kit.git", from: "0.1.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter repository URL.

## MIDI 2.0 UMP Support

MIDI2Kit provides full support for MIDI 2.0 Universal MIDI Packet (UMP) messages with high-resolution data.

### UMP Builder

Build MIDI 2.0 messages easily:

```swift
import MIDI2Core

// MIDI 2.0 Control Change (32-bit resolution)
let ccWords = UMPBuilder.midi2ControlChange(
    group: 0,
    channel: 0,
    controller: 74,  // Filter cutoff
    value: 0x80000000  // Full 32-bit value
)

// With normalized value (0.0-1.0)
let normalizedCC = UMPBuilder.midi2ControlChangeNormalized(
    group: 0,
    channel: 0,
    controller: 74,
    normalizedValue: 0.5
)

// MIDI 2.0 Note On (16-bit velocity)
let noteWords = UMPBuilder.midi2NoteOn(
    group: 0,
    channel: 0,
    note: 60,
    velocity: 0xC000,
    attributeType: .pitch7_9,
    attributeData: 0x1234
)

// Program Change with bank select
let pcWords = UMPBuilder.midi2ProgramChange(
    group: 0,
    channel: 0,
    program: 10,
    bank: ProgramBank(msb: 0, lsb: 32)
)

// Per-Note Pitch Bend (MPE)
let perNotePB = UMPBuilder.midi2PerNotePitchBend(
    group: 0,
    channel: 1,
    note: 60,
    value: PitchBendValue.center
)

// RPN with 32-bit value
let rpnWords = UMPBuilder.midi2RegisteredController(
    group: 0,
    channel: 0,
    address: RegisteredController.pitchBendSensitivity,
    value: 0x30000000
)

// MIDI 1.0 over UMP (for compatibility)
let midi1Words = UMPBuilder.midi1ControlChange(
    group: 0,
    channel: 0,
    controller: 1,
    value: 64
)
```

### UMP Parser

Parse received UMP messages:

```swift
import MIDI2Core

let words: [UInt32] = [0x40903C00, 0xC0000000]

if let message = UMPParser.parse(words) {
    switch message {
    case .midi2ChannelVoice(let cv):
        print("Status: \(cv.status)")
        print("Channel: \(cv.channel)")
        
        switch cv.status {
        case .noteOn:
            print("Note: \(cv.noteNumber), Velocity: \(cv.velocity16)")
        case .controlChange:
            print("CC \(cv.controllerNumber): \(cv.controllerValue32)")
        case .pitchBend:
            print("Pitch Bend: \(cv.pitchBendValue32)")
        default:
            break
        }
        
    case .midi1ChannelVoice(let cv):
        print("MIDI 1.0: \(cv.statusByte), \(cv.data1), \(cv.data2)")
        
    case .utility(let group, let status, let data):
        print("Utility message: \(status)")
        
    default:
        break
    }
}
```

### Sending UMP via Transport

```swift
import MIDI2Transport
import MIDI2Core

let transport = try CoreMIDITransport(clientName: "MyApp")

// Build MIDI 2.0 message
let words = UMPBuilder.midi2ControlChange(
    group: 0,
    channel: 0,
    controller: 74,
    value: 0x80000000
)

// Send via UMP
try await transport.sendUMP(words, to: destination)

// Check if destination supports MIDI 2.0
if transport.supportsMIDI2(destination) {
    try await transport.sendUMP(words, to: destination, protocol: ._2_0)
} else {
    // Fallback to MIDI 1.0
    let midi1Words = UMPBuilder.midi1ControlChange(
        group: 0, channel: 0, controller: 74, value: 64
    )
    try await transport.sendUMP(midi1Words, to: destination, protocol: ._1_0)
}
```

### Value Scaling Utilities

```swift
import MIDI2Core

// 7-bit ↔ 32-bit scaling
let value32 = UMPValueScaling.scale7To32(64)    // 0x80000000
let value7 = UMPValueScaling.scale32To7(0x80000000)  // 64

// 14-bit ↔ 32-bit scaling (for pitch bend)
let pb32 = UMPValueScaling.scale14To32(8192)   // Center
let pb14 = UMPValueScaling.scale32To14(0x80000000)

// Velocity scaling
let vel16 = UMPValueScaling.scaleVelocity7To16(100)
let vel7 = UMPValueScaling.scaleVelocity16To7(0xC000)

// Normalized values
let normalized = UMPValueScaling.normalizedTo32(0.5)  // ~2^31
```

---

## Minimal Example

A complete, working example that discovers MIDI-CI devices and fetches DeviceInfo via Property Exchange:

```swift
import MIDI2Kit

@MainActor
class MIDIController {
    private var transport: CoreMIDITransport?
    private var ciManager: CIManager?
    private var peManager: PEManager?
    
    func start() async throws {
        // 1. Create transport
        transport = try CoreMIDITransport(clientName: "MyApp")
        try await transport?.connectToAllSources()
        
        // 2. Create CI manager for device discovery
        ciManager = CIManager(transport: transport!)
        try await ciManager?.start()
        
        // 3. Handle setup changes
        Task {
            guard let transport else { return }
            for await _ in transport.setupChanged {
                try? await transport.connectToAllSources()
            }
        }
        
        // 4. Handle device discovery
        Task {
            guard let ciManager else { return }
            for await event in ciManager.events {
                switch event {
                case .deviceDiscovered(let device):
                    print("Found: \(device.displayName)")
                    if device.supportsPropertyExchange {
                        await fetchDeviceInfo(device)
                    }
                case .deviceLost(let muid):
                    print("Lost: \(muid)")
                default:
                    break
                }
            }
        }
    }
    
    private func fetchDeviceInfo(_ device: DiscoveredDevice) async {
        guard let ciManager, let transport,
              let destination = await ciManager.destination(for: device.muid) else {
            return
        }
        
        // Create PE manager on first use
        if peManager == nil {
            peManager = PEManager(
                transport: transport,
                sourceMUID: ciManager.muid
            )
            await peManager?.startReceiving()
        }
        
        // Fetch DeviceInfo
        let handle = PEDeviceHandle(muid: device.muid, destination: destination)
        
        do {
            let response = try await peManager!.get("DeviceInfo", from: handle)
            if let info = try? JSONDecoder().decode(PEDeviceInfo.self, from: response.body) {
                print("✅ Product: \(info.productName ?? "Unknown")")
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }
}
```

## Quick Start

### Basic Usage

```swift
import MIDI2Kit

// Create transport
let transport = try CoreMIDITransport(clientName: "MyApp")

// Connect to all MIDI sources (differential - prevents duplicates)
try await transport.connectToAllSources()

// Listen for MIDI data
Task {
    for await data in transport.received {
        print("Received: \(data.data.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }
}

// Handle setup changes
Task {
    for await _ in transport.setupChanged {
        try await transport.connectToAllSources()
    }
}
```

### MIDI-CI Discovery

```swift
import MIDI2CI

// Create and start CI manager
let ciManager = CIManager(transport: transport)
try await ciManager.start()

// Listen for device events
for await event in ciManager.events {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.displayName)")
        print("Supports PE: \(device.supportsPropertyExchange)")
    case .deviceLost(let muid):
        print("Lost: \(muid)")
    default:
        break
    }
}

// Get destination for sending to a device
if let destination = await ciManager.destination(for: device.muid) {
    try await transport.send(message, to: destination)
}
```

### Property Exchange

```swift
import MIDI2PE

// Create PE manager
let peManager = PEManager(
    transport: transport,
    sourceMUID: ciManager.muid
)
await peManager.startReceiving()

// Create handle for target device
let handle = PEDeviceHandle(
    muid: device.muid,
    destination: destination
)

// GET request
let response = try await peManager.get("DeviceInfo", from: handle)
let deviceInfo = try JSONDecoder().decode(PEDeviceInfo.self, from: response.body)

// GET with timeout
let response = try await peManager.get(
    "ChCtrlList",
    from: handle,
    timeout: .seconds(10)
)

// Channel-specific GET
let response = try await peManager.get(
    "ProgramInfo",
    channel: 0,
    from: handle
)
```

### Auto-Reconnecting Subscriptions

```swift
import MIDI2PE

// Create subscription manager
let subscriptionManager = PESubscriptionManager(
    peManager: peManager,
    ciManager: ciManager
)
await subscriptionManager.start()

// Subscribe with device identity for matching after MUID changes
try await subscriptionManager.subscribe(
    to: "ProgramList",
    on: device.muid,
    identity: device.identity  // Used for matching after reconnection
)

// Handle events (survives device reconnections)
for await event in subscriptionManager.events {
    switch event {
    case .notification(let notification):
        print("Data changed: \(notification.resource)")
        
    case .suspended(let intentID, let reason):
        print("Subscription suspended: \(reason)")
        
    case .restored(let intentID, let newSubscribeId):
        print("Subscription restored!")
        
    case .failed(let intentID, let reason):
        print("Subscription failed: \(reason)")
        
    case .subscribed(let intentID, let subscribeId):
        print("Initial subscription established")
    }
}
```

## Modules

### MIDI2Core

Foundation types used throughout the library.

```swift
import MIDI2Core

// MUID - 28-bit unique identifier (0x00000000 - 0x0FFFFFFF)
let muid = MUID.random()
let broadcast = MUID.broadcast

// Device Identity
let identity = DeviceIdentity(
    manufacturerID: .korg,
    familyID: 0x0001,
    modelID: 0x0001,
    versionID: 0x00010000
)

// Mcoded7 encoding (8-bit → 7-bit for SysEx)
let encoded = Mcoded7.encode(originalData)
let decoded = Mcoded7.decode(encodedData)

// UMP Message Building
let words = UMPBuilder.midi2ControlChange(group: 0, channel: 0, controller: 74, value: 0x80000000)

// UMP Message Parsing
if let message = UMPParser.parse(words) {
    // Handle parsed message
}
```

### MIDI2CI

MIDI Capability Inquiry protocol implementation.

```swift
import MIDI2CI

// Create manager
let ciManager = CIManager(transport: transport)
try await ciManager.start()

// Configure discovery
let config = CIManagerConfiguration(
    discoveryInterval: 5.0,
    deviceTimeout: 15.0,
    categorySupport: .propertyExchange
)
let ciManager = CIManager(transport: transport, configuration: config)

// Access discovered devices
let devices = await ciManager.discoveredDevices
let device = await ciManager.device(for: muid)

// Find destination for a device (via Entity mapping)
let destination = await ciManager.destination(for: device.muid)
```

### MIDI2PE

Property Exchange with transaction management and per-device rate limiting.

```swift
import MIDI2PE

// Transaction manager with per-device limiting
let transactionManager = PETransactionManager(
    maxInflightPerDevice: 2,  // Max 2 concurrent requests per device
    logger: logger
)

// High-level PE manager
let peManager = PEManager(
    transport: transport,
    sourceMUID: muid,
    transactionManager: transactionManager
)
await peManager.startReceiving()

// Device disconnection cleanup
await transactionManager.cancelAll(for: deviceMUID)

// Monitor state
print(await transactionManager.diagnostics)
// Active transactions: 3
// Available IDs: 125
// Device states:
//   MUID(0x01234567): inflight=2, waiting=1
```

### MIDI2Transport

CoreMIDI abstraction with connection management and UMP support.

```swift
import MIDI2Transport

let transport = try CoreMIDITransport(clientName: "MyApp")

// Differential connection (prevents duplicates)
try await transport.connectToAllSources()

// Check connection state
let isConnected = await transport.isConnected(to: sourceID)
let count = await transport.connectedSourceCount

// Full reconnection when needed
try await transport.reconnectAllSources()

// Send UMP messages (MIDI 2.0)
let words = UMPBuilder.midi2ControlChange(group: 0, channel: 0, controller: 74, value: 0x80000000)
try await transport.sendUMP(words, to: destination)

// Check MIDI 2.0 support
if transport.supportsMIDI2(destination) {
    // Use MIDI 2.0 features
}
```

## Architecture

See [Documentation/Architecture.md](Documentation/Architecture.md) for detailed architecture overview.

## Best Practices

See [Documentation/BestPractices.md](Documentation/BestPractices.md) for:
- Preventing Request ID leaks
- Per-device rate limiting
- Handling duplicate MIDI connections
- Auto-reconnecting subscriptions
- Error handling patterns

## Testing

```bash
swift test
```

Or in Xcode: `Cmd+U`

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please read the architecture documentation before submitting PRs.

---

## Changelog

See [Documentation/CHANGELOG.md](Documentation/CHANGELOG.md) for detailed version history.

### Latest (2026-01-11)

- **Added MIDI 2.0 UMP support**
  - `UMPBuilder` for constructing UMP messages
  - `UMPParser` for parsing received UMP messages
  - `UMPTypes` with message types, status codes, and value scaling
  - `CoreMIDITransport.sendUMP()` for UMP transmission
  - MIDI 2.0 protocol detection via `supportsMIDI2()`
- Added `PESubscriptionManager` for auto-reconnecting subscriptions
- Added per-device inflight limiting (`maxInflightPerDevice`)
- Added `CIManagerEvent` for event-driven device discovery
- Fixed Source-to-Destination mapping via Entity
- Improved responsibility separation between `PETransactionManager` and `PEManager`
