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
    private let transactionManager = PETransactionManager()
    private let myMUID = MUID.random()
    
    private var discoveredDevices: [MUID: (identity: DeviceIdentity, destination: MIDIDestinationID)] = [:]
    private var receiveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    
    func start() async throws {
        // 1. Create transport and connect to all sources
        transport = try CoreMIDITransport(clientName: "MyApp")
        try await transport?.connectToAllSources()
        
        // 2. Start receive loop
        receiveTask = Task { await receiveLoop() }
        
        // 3. Start timeout checker
        timeoutTask = Task { await timeoutLoop() }
        
        // 4. Handle setup changes (device connect/disconnect)
        Task {
            guard let transport else { return }
            for await _ in transport.setupChanged {
                try? await transport.connectToAllSources()
            }
        }
        
        // 5. Send Discovery Inquiry to all destinations
        await sendDiscovery()
    }
    
    func stop() {
        receiveTask?.cancel()
        timeoutTask?.cancel()
        transport = nil
    }
    
    // MARK: - Receive Loop
    
    private func receiveLoop() async {
        guard let transport else { return }
        
        for await received in transport.received {
            // Parse as CI message
            guard let parsed = CIMessageParser.parse(received.data) else {
                continue  // Not a CI message
            }
            
            switch parsed.messageType {
            case .discoveryReply:
                await handleDiscoveryReply(parsed)
                
            case .peGetReply, .peSetReply:
                await handlePEReply(parsed)
                
            default:
                break
            }
        }
    }
    
    // MARK: - Timeout Loop
    
    private func timeoutLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            await transactionManager.checkTimeouts()
        }
    }
    
    // MARK: - Discovery
    
    private func sendDiscovery() async {
        guard let transport else { return }
        
        let message = CIMessageBuilder.discoveryInquiry(
            sourceMUID: myMUID,
            categorySupport: .propertyExchange
        )
        
        for dest in await transport.destinations {
            try? await transport.send(message, to: dest.destinationID)
        }
    }
    
    private func handleDiscoveryReply(_ parsed: CIMessageParser.ParsedMessage) async {
        guard let reply = CIMessageParser.parseDiscoveryReply(parsed.payload) else { return }
        
        // Find destination for this device
        guard let transport,
              let dest = (await transport.destinations).first else { return }
        
        discoveredDevices[parsed.sourceMUID] = (reply.identity, dest.destinationID)
        
        print("Discovered: \(reply.identity.manufacturerID.name ?? "Unknown") (MUID: \(parsed.sourceMUID))")
        
        // If device supports PE, fetch DeviceInfo
        if reply.categorySupport.contains(.propertyExchange) {
            await fetchDeviceInfo(from: parsed.sourceMUID, destination: dest.destinationID)
        }
    }
    
    // MARK: - Property Exchange
    
    private func fetchDeviceInfo(from deviceMUID: MUID, destination: MIDIDestinationID) async {
        guard let transport else { return }
        
        // Begin transaction
        guard let requestID = await transactionManager.begin(
            resource: "DeviceInfo",
            destinationMUID: deviceMUID,
            timeout: 5.0
        ) else {
            print("❌ Request ID exhausted")
            return
        }
        
        // Build PE Get message
        let header = CIMessageBuilder.resourceRequestHeader(resource: "DeviceInfo")
        let message = CIMessageBuilder.peGetInquiry(
            sourceMUID: myMUID,
            destinationMUID: deviceMUID,
            requestID: requestID,
            headerData: header
        )
        
        // Send request
        do {
            try await transport.send(message, to: destination)
        } catch {
            await transactionManager.cancel(requestID: requestID)
            return
        }
        
        // Wait for completion
        let result = await transactionManager.waitForCompletion(requestID: requestID)
        
        switch result {
        case .success(_, let body):
            if let deviceInfo = try? JSONDecoder().decode(PEDeviceInfo.self, from: body) {
                print("✅ DeviceInfo: \(deviceInfo.productName ?? "Unknown")")
            }
        case .error(let status, let message):
            print("❌ PE Error: \(status) - \(message ?? "")")
        case .timeout:
            print("⏱️ Timeout")
        case .cancelled:
            print("🚫 Cancelled")
        }
    }
    
    private func handlePEReply(_ parsed: CIMessageParser.ParsedMessage) async {
        guard let reply = CIMessageParser.parsePEReply(parsed.payload) else { return }
        
        // Process chunk (auto-completes transaction when all chunks received)
        _ = await transactionManager.processChunk(
            requestID: reply.requestID,
            thisChunk: reply.thisChunk,
            numChunks: reply.numChunks,
            headerData: reply.headerData,
            propertyData: reply.propertyData
        )
    }
}

// Usage
let controller = MIDIController()
try await controller.start()
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

// Build Discovery Inquiry
let myMUID = MUID.random()
let message = CIMessageBuilder.discoveryInquiry(
    sourceMUID: myMUID,
    categorySupport: .propertyExchange
)

// Send to all destinations
for dest in await transport.destinations {
    try await transport.send(message, to: dest.destinationID)
}

// Parse Discovery Reply
if let parsed = CIMessageParser.parse(receivedData),
   parsed.messageType == .discoveryReply,
   let reply = CIMessageParser.parseDiscoveryReply(parsed.payload) {
    print("Found: \(reply.identity)")
    print("Supports PE: \(reply.categorySupport.contains(.propertyExchange))")
}
```

### Property Exchange

```swift
import MIDI2PE

// Create transaction manager (prevents Request ID leaks)
let transactionManager = PETransactionManager()

// Begin transaction
guard let requestID = await transactionManager.begin(
    resource: "DeviceInfo",
    destinationMUID: deviceMUID,
    timeout: 5.0
) else {
    print("All Request IDs in use!")
    return
}

// Build and send PE Get
let header = CIMessageBuilder.resourceRequestHeader(resource: "DeviceInfo")
let getMessage = CIMessageBuilder.peGetInquiry(
    sourceMUID: myMUID,
    destinationMUID: deviceMUID,
    requestID: requestID,
    headerData: header
)
try await transport.send(getMessage, to: destination)

// Wait for completion (blocks until response or timeout)
let result = await transactionManager.waitForCompletion(requestID: requestID)

switch result {
case .success(let header, let body):
    let deviceInfo = try JSONDecoder().decode(PEDeviceInfo.self, from: body)
    print("Device: \(deviceInfo.productName ?? "Unknown")")
case .error(let status, let message):
    print("Error \(status): \(message ?? "")")
case .timeout:
    print("Transaction timed out")
case .cancelled:
    print("Transaction cancelled")
}
```

## Modules

### MIDI2Core

Foundation types used throughout the library.

```swift
import MIDI2Core

// MUID - 28-bit unique identifier
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

// Message building
let discovery = CIMessageBuilder.discoveryInquiry(sourceMUID: muid)
let peCapability = CIMessageBuilder.peCapabilityInquiry(
    sourceMUID: myMUID,
    destinationMUID: deviceMUID
)

// Message parsing
if let msg = CIMessageParser.parse(data) {
    switch msg.messageType {
    case .discoveryReply:
        let reply = CIMessageParser.parseDiscoveryReply(msg.payload)
    case .peGetReply:
        let reply = CIMessageParser.parsePEReply(msg.payload)
    default:
        break
    }
}
```

### MIDI2PE

Property Exchange with transaction management.

```swift
import MIDI2PE

// Transaction manager prevents Request ID leaks
let manager = PETransactionManager()

// Begin/complete lifecycle
let id = await manager.begin(resource: "ChCtrlList", destinationMUID: muid)
// ... send request, receive response ...
await manager.complete(requestID: id, header: header, body: body)

// Error handling
await manager.completeWithError(requestID: id, status: 404)

// Timeout management
await manager.checkTimeouts()

// Device disconnection cleanup
await manager.cancelAll(for: deviceMUID)
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
- Handling duplicate MIDI connections
- Timeout management
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
