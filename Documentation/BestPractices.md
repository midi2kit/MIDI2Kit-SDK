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
    
    // Send request...
    
    // Wait for result (auto-releases on completion)
    let result = await manager.waitForCompletion(requestID: requestID)
    
    switch result {
    case .success(_, let body):
        return body
    case .error(let status, let message):
        throw PEError.deviceError(status: status, message: message)
    case .timeout:
        throw PEError.timeout
    case .cancelled:
        throw PEError.cancelled
    }
}
```

### Timeout Management

Call `checkTimeouts()` periodically:

```swift
// Option 1: Timer
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    Task {
        await manager.checkTimeouts()
    }
}

// Option 2: In your run loop
func processLoop() async {
    while isRunning {
        await manager.checkTimeouts()
        try await Task.sleep(for: .seconds(1))
    }
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
    // Too many requests - slow down
case 500:
    // Internal device error
case 501:
    // Not implemented
default:
    // Unknown status
}
```

### Always Complete Transactions

Even on error, complete the transaction:

```swift
// ❌ WRONG: ID leaks on error
if status >= 400 {
    return  // ID never released!
}

// ✅ CORRECT: Always complete
if status >= 400 {
    await manager.completeWithError(requestID: id, status: status)
    return
}
await manager.complete(requestID: id, header: header, body: body)
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
    let muid = MUID.random()
    
    let id = await manager.begin(resource: "Test", destinationMUID: muid)
    #expect(await manager.availableIDs == 127)
    
    await manager.completeWithError(requestID: id!, status: 404)
    #expect(await manager.availableIDs == 128)  // ID released
}
```

### Test Timeout Behavior

```swift
@Test("Transaction timeout")
func testTimeout() async throws {
    let manager = PETransactionManager()
    
    let id = await manager.begin(
        resource: "Test",
        destinationMUID: MUID.random(),
        timeout: 0.01  // Very short
    )
    
    try await Task.sleep(for: .milliseconds(50))
    
    let timedOut = await manager.checkTimeouts()
    #expect(timedOut.contains(id!))
    #expect(await manager.availableIDs == 128)
}
```

---

## Performance Considerations

### Batch Operations

When querying multiple resources:

```swift
// ✅ GOOD: Parallel requests
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
    // Don't exceed this many concurrent transactions to this device
}
```

### SysEx Size Limits

For large payloads, chunk appropriately:

```swift
let maxChunkSize = min(deviceMaxSysEx, 4096)
let chunks = payload.chunked(into: maxChunkSize)
```
