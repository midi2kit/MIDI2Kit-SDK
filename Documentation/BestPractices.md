# MIDI2Kit Best Practices

## Request ID Leak Prevention

### The Problem

MIDI-CI Property Exchange uses 7-bit Request IDs (0-127). If IDs are not properly released:

1. IDs accumulate in "in-use" state
2. Eventually all 128 IDs are exhausted
3. `begin()` returns `nil`
4. PE becomes non-functional

**Common Leak Causes**:
- PE Reply with error status (`status >= 400`) returns early without cleanup
- Chunk timeout/loss leaves transaction orphaned
- Device disconnection abandons active transactions
- Exception/crash before completion

### The Solution: PETransactionManager

**Always use PETransactionManager** for PE transactions:

```swift
let manager = PETransactionManager()

// ✅ CORRECT: All paths release the ID
func getResource(resource: String, from device: MUID) async throws -> Data {
    guard let requestID = await manager.begin(
        resource: resource,
        destinationMUID: device,
        timeout: 5.0
    ) else {
        throw PEError.requestIDExhausted
    }
    
    defer {
        // Always release on any exit
        Task { await manager.cancel(requestID: requestID) }
    }
    
    // Send request...
    // Receive response...
    
    return responseData
}
```

### Device Disconnection

When a device disconnects, cancel all its transactions:

```swift
func handleDeviceDisconnected(muid: MUID) async {
    await manager.cancelAll(for: muid)
}
```

### Monitoring

Check for exhaustion warnings:

```swift
if await manager.isNearExhaustion {
    print("⚠️ Warning: Only \(await manager.availableIDs) Request IDs remaining")
}

// Full diagnostics
print(await manager.diagnostics)
```

---

## Per-Device Inflight Limiting

### The Problem

Some MIDI devices cannot handle many concurrent PE requests:

- KORG Module Pro: Drops chunks when >2 concurrent requests
- Some devices: Response corruption or timeout
- Generally: Lower-end implementations struggle with concurrency

### The Solution: Configure maxInflightPerDevice

```swift
// Default: 2 concurrent requests per device
let manager = PETransactionManager(maxInflightPerDevice: 2)

// For known-stable devices, can increase
let manager = PETransactionManager(maxInflightPerDevice: 8)

// For problematic devices, decrease to 1
let manager = PETransactionManager(maxInflightPerDevice: 1)
```

### How It Works

```swift
// With maxInflightPerDevice=2:

// Request 1 to Device A → starts immediately
// Request 2 to Device A → starts immediately  
// Request 3 to Device A → WAITS in queue
// Request 4 to Device B → starts immediately (different device)

// When Request 1 completes:
// Request 3 automatically starts
```

### Diagnostics

```swift
// Check device state
let inflight = await manager.inflightCount(for: deviceMUID)
let waiting = await manager.waiterCount(for: deviceMUID)
print("Device \(deviceMUID): \(inflight) active, \(waiting) waiting")

// Full diagnostics shows all devices
print(await manager.diagnostics)
// Device states:
//   MUID(0x01234567): inflight=2, waiting=3
//   MUID(0x07654321): inflight=1, waiting=0
```

---

## Preventing Duplicate MIDI Reception

### The Problem

Calling `MIDIPortConnectSource` multiple times for the same source causes:

1. **Double reception**: Every MIDI message received twice
2. **State corruption**: Note On/Off pairs become unbalanced
3. **SysEx corruption**: Fragmented messages interleaved incorrectly
4. **CI/PE failures**: Duplicate responses confuse state machines

**Common Cause**: Calling "connect all" on every `msgSetupChanged`:

```swift
// ❌ WRONG: Causes duplicates
for await _ in transport.setupChanged {
    let count = MIDIGetNumberOfSources()
    for i in 0..<count {
        MIDIPortConnectSource(port, MIDIGetSource(i), nil)  // Duplicate!
    }
}
```

### The Solution: Differential Connection

**Use CoreMIDITransport's built-in connection management**:

```swift
// ✅ CORRECT: Differential - only connects new sources
for await _ in transport.setupChanged {
    try await transport.connectToAllSources()
}
```

### How It Works

```
Before SetupChanged:
  Connected: {A, B, C}

After SetupChanged (device B removed, D added):
  Current sources: {A, C, D}
  
  Removed = Connected - Current = {B}  → Disconnect B
  New = Current - Connected = {D}      → Connect D
  
  Result: Connected = {A, C, D}  ✅ No duplicates
```

### When to Use Full Reconnection

Use `reconnectAllSources()` only when you need a clean slate:

```swift
// After detecting corruption or state issues
try await transport.reconnectAllSources()
```

### Verifying Connection State

```swift
// Check specific source
let isConnected = await transport.isConnected(to: sourceID)

// Check count
let count = await transport.connectedSourceCount
print("Connected to \(count) sources")
```

---

## Auto-Reconnecting Subscriptions

### The Problem

PE subscriptions are tied to a device's MUID, but:

1. Device disconnects → Subscription lost
2. Device reconnects with **new MUID** (per MIDI-CI spec)
3. App needs to re-subscribe manually
4. Notifications missed during reconnection

### The Solution: PESubscriptionManager

```swift
let subscriptionManager = PESubscriptionManager(
    peManager: peManager,
    ciManager: ciManager
)
await subscriptionManager.start()

// Subscribe with device identity for tracking across MUID changes
try await subscriptionManager.subscribe(
    to: "ProgramList",
    on: device.muid,
    identity: device.identity  // Used for matching after MUID change
)

// Handle all events (survives reconnections)
for await event in subscriptionManager.events {
    switch event {
    case .notification(let notification):
        // Handle notification
        updateUI(with: notification.data)
        
    case .suspended(let intentID, let reason):
        // Device disconnected
        showReconnectingUI()
        
    case .restored(let intentID, let newSubscribeId):
        // Device reconnected, subscription restored!
        hideReconnectingUI()
        
    case .failed(let intentID, let reason):
        // Subscription permanently failed
        showError(reason)
        
    case .subscribed(let intentID, let subscribeId):
        // Initial subscription established
        break
    }
}
```

### Key Concepts

**Subscription Intent** vs **Active Subscription**:
- Intent: What you *want* to subscribe to (persists across disconnections)
- Active: The actual subscription on the device (recreated on reconnection)

**Device Matching**:
- Primary: Match by MUID (fastest)
- Fallback: Match by DeviceIdentity (survives MUID change)

### Configuration

```swift
// Customize reconnection behavior
subscriptionManager.resubscribeDelay = .milliseconds(500)  // Wait before re-subscribing
subscriptionManager.maxRetryAttempts = 3  // Give up after 3 failures
```

---

## Chunk Assembly Best Practices

### Preserve Header from First Chunk

Some devices only send header data in chunk 1:

```
Chunk 1: header={"status":200,"resource":"ChCtrlList"}, data=[...]
Chunk 2: header=<empty>, data=[...]
Chunk 3: header=<empty>, data=[...]
```

**PEChunkAssembler handles this automatically**:

```swift
// Header from first non-empty chunk is preserved
let result = assembler.addChunk(
    requestID: id,
    thisChunk: 2,
    numChunks: 3,
    headerData: Data(),  // Empty - but original header preserved
    propertyData: chunkData
)

if case .complete(let header, let body) = result {
    // header contains data from chunk 1
}
```

### Handle Out-of-Order Chunks

Chunks may arrive out of order. The assembler handles this:

```swift
// Chunks arrive: 3, 1, 2
assembler.addChunk(requestID: id, thisChunk: 3, ...)  // → .incomplete
assembler.addChunk(requestID: id, thisChunk: 1, ...)  // → .incomplete
assembler.addChunk(requestID: id, thisChunk: 2, ...)  // → .complete (assembled in order)
```

---

## Source-to-Destination Mapping

### The Problem

CoreMIDI uses separate endpoints for input and output:

```
Physical Device
  └── Entity
       ├── Source (endpoint A) ← MIDI IN (receive)
       └── Destination (endpoint B) ← MIDI OUT (send)
```

**Wrong approach** (will fail):
```swift
// ❌ Source and Destination refs are NOT the same!
let destinationID = MIDIDestinationID(sourceID.value)
```

### The Solution: Entity-Based Lookup

Use `CIManager.destination(for:)`:

```swift
// ✅ Find destination on same entity as source
guard let destination = await ciManager.destination(for: device.muid) else {
    throw MIDIError.destinationNotFound
}
try await transport.send(message, to: destination)
```

### How It Works Internally

```swift
// Find entity containing this source
var entity: MIDIEntityRef = 0
MIDIEndpointGetEntity(sourceRef, &entity)

// Get destination from same entity
let destinationRef = MIDIEntityGetDestination(entity, 0)
```

---

## Error Handling Patterns

### PE Status Codes

```swift
switch status {
case 200:
    // Success
case 202:
    // Accepted (async processing)
case 400:
    // Bad request - check your header format
case 401:
    // Unauthorized
case 404:
    // Resource not found - device doesn't support this resource
case 429:
    // Too many requests - slow down (use inflight limiting!)
case 500:
    // Internal device error
case 501:
    // Not implemented
default:
    // Unknown status
}
```

### Always Complete Transactions

Even on error, ensure cleanup:

```swift
let requestID = await manager.begin(resource: "Test", destinationMUID: muid)
defer {
    Task { await manager.cancel(requestID: requestID) }
}

// ... do work, throw errors, etc.
// ID is always released via defer
```

---

## Testing Best Practices

### Use MockMIDITransport

Test without hardware:

```swift
@Test("PE Get flow")
func testPEGet() async {
    let mock = MockMIDITransport()
    
    // Setup mock response
    let discoveryReply: [UInt8] = [0xF0, 0x7E, ...]
    await mock.injectReceived(discoveryReply)
    
    // Run your code
    // ...
    
    // Verify
    #expect(await mock.wasSent(ciMessageType: 0x70))
    let sent = await mock.lastSentMessage
    #expect(sent?.data[4] == 0x34)  // PE Get
}
```

### Test Transaction Lifecycle

```swift
@Test("Transaction cleanup on error")
func testErrorCleanup() async {
    let manager = PETransactionManager()
    let muid = MUID(rawValue: 0x01234567)!  // Valid 28-bit MUID
    
    let id = await manager.begin(resource: "Test", destinationMUID: muid)
    #expect(await manager.availableIDs == 127)
    
    await manager.cancel(requestID: id!)
    #expect(await manager.availableIDs == 128)  // ID released
}
```

### Test Inflight Limiting

```swift
@Test("Inflight limiting queues excess requests")
func testInflightLimiting() async {
    let manager = PETransactionManager(maxInflightPerDevice: 2)
    let muid = MUID(rawValue: 0x01234567)!
    
    // Start 3 requests
    async let id1 = manager.begin(resource: "R1", destinationMUID: muid)
    async let id2 = manager.begin(resource: "R2", destinationMUID: muid)
    
    // Third request will wait
    Task {
        let id3 = await manager.begin(resource: "R3", destinationMUID: muid)
        // This won't complete until id1 or id2 is cancelled
    }
    
    // Wait for first two to start
    let _ = await (id1, id2)
    
    #expect(await manager.inflightCount(for: muid) == 2)
    #expect(await manager.waiterCount(for: muid) == 1)
}
```

### MUID Validation

Always use valid 28-bit MUIDs in tests:

```swift
// ✅ Valid (within 0x00000000 - 0x0FFFFFFF)
let muid = MUID(rawValue: 0x01234567)!
let muid2 = MUID(rawValue: 0x0ABCDEF0)!

// ❌ Invalid (will crash on force unwrap!)
// let muid = MUID(rawValue: 0x12345678)!  // > 0x0FFFFFFF
// let muid = MUID(rawValue: 0xFFFFFFFF)!  // Way too large
```

---

## Performance Considerations

### Batch Operations

When querying multiple resources:

```swift
// ✅ GOOD: Parallel requests (respects inflight limit automatically)
async let info = getResource("DeviceInfo", from: device)
async let controllers = getResource("ChCtrlList", from: device)
async let programs = getResource("ProgramList", from: device)

let results = try await (info, controllers, programs)
```

### Respect Device Limits

Check `maxSysExSize` and `numSimultaneousRequests`:

```swift
if let reply = CIMessageParser.parsePECapabilityReply(payload) {
    let maxRequests = reply.numSimultaneousRequests
    // Use this to configure maxInflightPerDevice if needed
}
```

### SysEx Size Limits

For large payloads, chunk appropriately:

```swift
let maxChunkSize = min(deviceMaxSysEx, 4096)
let chunks = payload.chunked(into: maxChunkSize)
```

---

## Logging Best Practices

### Enable Logging for Debugging

```swift
// Development: verbose logging
let logger = StdoutMIDI2Logger(minLevel: .debug)
let manager = PETransactionManager(logger: logger)

// Production: warnings and above only
let logger = OSLogMIDI2Logger(subsystem: "com.myapp", minLevel: .warning)
```

### Use Safe Log Utilities

```swift
// Don't log raw binary data
logger.debug("Received: \(data)")  // ❌ Could be huge

// Use log utilities
logger.debug("Received: \(MIDI2LogUtils.hexPreview(data))")  // ✅ Truncated
// → "F0 7E 7F... (32 of 1024 bytes)"
```

### Log Categories

Organize logs by category:
- `PETransaction`: Transaction lifecycle
- `PEManager`: Request/response flow
- `CIManager`: Device discovery
- `CoreMIDI`: Low-level MIDI operations
