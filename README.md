# MIDI2Kit

A modern Swift library for MIDI 2.0 / MIDI-CI / Property Exchange.

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20|%20macOS%2014-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- **MIDI2Core** - Foundation types (MUID, DeviceIdentity, Mcoded7)
- **MIDI2CI** - Capability Inquiry (Discovery, Protocol Negotiation, Profiles)
- **MIDI2PE** - Property Exchange (Get/Set resources, Subscriptions, Transaction management)
- **MIDI2Transport** - CoreMIDI integration with duplicate connection prevention
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

CoreMIDI abstraction with connection management.

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

### Latest (2026-01-10)

- Added `PESubscriptionManager` for auto-reconnecting subscriptions
- Added per-device inflight limiting (`maxInflightPerDevice`)
- Added `CIManagerEvent` for event-driven device discovery
- Fixed Source-to-Destination mapping via Entity
- Improved responsibility separation between `PETransactionManager` and `PEManager`
- 150 tests passing
