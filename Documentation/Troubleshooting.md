# MIDI2Kit Troubleshooting Guide

## Common Issues

### 1. Request ID Exhaustion

**Symptoms:**
- `begin()` returns `nil`
- `PEError.requestIDExhausted` thrown
- PE operations stop working
- Warning: "Request ID near exhaustion"

**Causes:**
- Request IDs not released after completion
- Error paths skipping cleanup
- Device disconnection abandoning transactions
- Timeout handling not releasing IDs

**Solutions:**

```swift
// ✅ ALWAYS use defer for cleanup
func getResource(resource: String, device: PEDeviceHandle) async throws -> Data {
    guard let requestID = await transactionManager.begin(
        resource: resource,
        destinationMUID: device.muid
    ) else {
        throw PEError.requestIDExhausted
    }
    
    defer {
        Task { await transactionManager.cancel(requestID: requestID) }
    }
    
    // ... do work, may throw
    return data
}

// ✅ Cancel all on device disconnect
func handleDeviceDisconnected(_ muid: MUID) async {
    await transactionManager.cancelAll(for: muid)
}

// ✅ Monitor for leaks
if await transactionManager.isNearExhaustion {
    print("⚠️ Only \(await transactionManager.availableIDs) IDs remaining")
    print(await transactionManager.diagnostics)
}
```

---

### 2. Duplicate MIDI Reception

**Symptoms:**
- Messages received twice
- Note On/Off pairs unbalanced
- SysEx messages corrupted
- MIDI-CI state machine confused

**Causes:**
- Calling `MIDIPortConnectSource` multiple times for same source
- Not using differential connection
- Full reconnection on every setup change

**Solutions:**

```swift
// ✅ Use differential connection
for await _ in transport.setupChanged {
    try await transport.connectToAllSources()  // Only connects NEW sources
}

// ❌ WRONG: Manual connection without tracking
for await _ in transport.setupChanged {
    let count = MIDIGetNumberOfSources()
    for i in 0..<count {
        MIDIPortConnectSource(port, MIDIGetSource(i), nil)  // Duplicates!
    }
}

// Verify connection state
let count = await transport.connectedSourceCount
print("Connected to \(count) sources")
```
 
---

### 3. PE Chunk Assembly Failures

**Symptoms:**
- Partial responses
- Timeout waiting for chunks
- `PEChunkResult.timeout` returned
- Data corruption in multi-chunk responses

**Causes:**
- Device overwhelmed with concurrent requests
- Network/USB latency
- Chunk timeout too short
- Device drops chunks under load

**Solutions:**

```swift
// ✅ Reduce concurrent requests per device
let manager = PETransactionManager(
    maxInflightPerDevice: 1,  // Strict: one at a time
    logger: logger
)

// ✅ Increase chunk timeout
let assembler = PEChunkAssembler(timeout: 10.0)  // 10 seconds

// ✅ Check device diagnostics
print(await transactionManager.diagnostics)
// Shows: inflight=2, waiting=3 for each device
```

---

### 4. Device Not Found

**Symptoms:**
- `CIManager.destination(for:)` returns `nil`
- `PEError.deviceNotFound` thrown
- Discovery works but operations fail

**Causes:**
- MUID changed after reconnection (per MIDI-CI spec)
- Source-to-Destination mapping failed
- Device offline

**Solutions:**

```swift
// ✅ Use PESubscriptionManager for auto-reconnection
let subscriptionManager = PESubscriptionManager(
    peManager: peManager,
    ciManager: ciManager
)

// Subscribe with identity for MUID-independent tracking
try await subscriptionManager.subscribe(
    to: "ProgramList",
    on: device.muid,
    identity: device.identity  // Used for matching after MUID change
)

// ✅ Listen for device events
for await event in ciManager.events {
    switch event {
    case .deviceDiscovered(let device):
        print("New device: \(device.displayName) MUID=\(device.muid)")
    case .deviceLost(let muid):
        print("Device lost: \(muid)")
        await transactionManager.cancelAll(for: muid)
    default:
        break
    }
}

// ✅ Verify destination mapping
if let dest = await ciManager.destination(for: device.muid) {
    print("Destination found: \(dest)")
} else {
    print("No destination - check entity mapping")
}
```

---

### 5. SysEx Message Corruption

**Symptoms:**
- Invalid SysEx format errors
- Missing F0 or F7 bytes
- Parse failures
- Interleaved message data

**Causes:**
- Fragmented SysEx across packets
- Race condition in packet processing
- Out-of-order packet delivery

**Solutions:**

```swift
// ✅ MIDI2Kit handles this internally
// CoreMIDITransport processes packets sequentially in single Task

// If using raw CoreMIDI:
// ❌ WRONG: Spawning separate Tasks per packet
MIDIInputPortCreateWithBlock(...) { packetList, _ in
    for packet in packets {
        Task { await process(packet) }  // Race condition!
    }
}

// ✅ CORRECT: Process sequentially
MIDIInputPortCreateWithBlock(...) { packetList, _ in
    var allData: [[UInt8]] = []
    for packet in packets {
        allData.append(Array(packet.data))
    }
    Task {
        for data in allData {
            await process(data)  // Order preserved
        }
    }
}
```

---

### 6. MIDI 2.0 UMP Issues

**Symptoms:**
- Device doesn't respond to UMP messages
- Wrong values received/sent
- Protocol mismatch

**Causes:**
- Device doesn't support MIDI 2.0
- Wrong protocol setting
- Value scaling errors

**Solutions:**

```swift
// ✅ Check protocol support
if transport.supportsMIDI2(destination) {
    // Use MIDI 2.0
    let words = UMPBuilder.midi2ControlChange(...)
} else {
    // Fallback to MIDI 1.0
    let words = UMPBuilder.midi1ControlChange(...)
}

// ✅ Verify value scaling
let value7: UInt8 = 64
let value32 = UMPValueScaling.scale7To32(value7)
print("7-bit \(value7) → 32-bit 0x\(String(format: "%08X", value32))")
// Output: 7-bit 64 → 32-bit 0x80000000

// ✅ Parse received UMP to verify
if let message = UMPParser.parse(receivedWords) {
    switch message {
    case .midi2ChannelVoice(let cv):
        print("CC \(cv.controllerNumber): \(cv.controllerValue32)")
    default:
        break
    }
}
```

---

### 7. Subscription Not Receiving Notifications

**Symptoms:**
- Subscribe succeeds but no notifications
- Notifications stop after reconnection
- `subscribeId` invalid error

**Causes:**
- Device reconnected with new MUID
- Subscription not restored
- Notification stream not started

**Solutions:**

```swift
// ✅ Use PESubscriptionManager for automatic handling
let subscriptionManager = PESubscriptionManager(
    peManager: peManager,
    ciManager: ciManager
)
await subscriptionManager.start()

// Start notification stream BEFORE subscribing
Task {
    for await event in subscriptionManager.events {
        switch event {
        case .notification(let n):
            print("Notification: \(n.resource)")
        case .suspended(let id, let reason):
            print("Subscription \(id) suspended: \(reason)")
        case .restored(let id, _):
            print("Subscription \(id) restored!")
        default:
            break
        }
    }
}

// Subscribe with identity for reconnection
try await subscriptionManager.subscribe(
    to: "ProgramList",
    on: device.muid,
    identity: device.identity
)
```

---

### 8. Memory Leaks

**Symptoms:**
- Memory usage grows over time
- App becomes slow
- System warnings

**Causes:**
- MIDITracer not cleared
- AsyncStream continuations not finished
- Task references held

**Solutions:**

**Tip: Ensure deterministic cleanup**

`PEManager` does not automatically stop its receive loop when it is deallocated. Always call `await peManager.stopReceiving()` before releasing it (and call `await transport.shutdown()` in tests to terminate AsyncStreams). If you want a single place to manage this lifecycle, use `PEManagerSession` and call `await session.stop()`.


```swift
// ✅ Clear tracer periodically
Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
    MIDITracer.shared.clear()
}

// ✅ Proper cleanup on deinit
class MIDIController {
    private var receiveTask: Task<Void, Never>?
    
    deinit {
        receiveTask?.cancel()
    }
    
    func stop() async {
        receiveTask?.cancel()
        receiveTask = nil
        await peManager.stopReceiving()
        await subscriptionManager.stop()
    }
}

// ✅ Use weak self in closures
peManager.destinationResolver = { [weak ciManager] muid in
    await ciManager?.destination(for: muid)
}
```

---

### 9. Test Failures

**Symptoms:**
- Tests hang indefinitely
- MUID validation crashes
- Inconsistent test results

**Causes:**
- Invalid test MUID values (exceeds 28-bit)
- Uncancelled async tasks
- Missing cleanup
- AsyncStream not terminated (for await loops stuck)
- RequestID exhaustion with high maxInflightPerDevice

**Solutions:**
If your tests still hang, prefer wrapping setup in `PEManagerSession` and call `await session.stop()` in teardown so `stopReceiving()` and `shutdown()` are not forgotten.


```swift
// ✅ Use valid 28-bit MUIDs in tests
let muid = MUID(rawValue: 0x01234567)!  // ≤ 0x0FFFFFFF

// ❌ WRONG: Exceeds 28-bit limit
// let muid = MUID(rawValue: 0x12345678)!  // Crashes!

// ✅ Call shutdown() in test teardown to terminate streams
func tearDown() async throws {
    await transport.shutdown()  // Finishes AsyncStreams
    await manager.cancelAll()
}

// ✅ Use MockMIDITransport for isolation
let mock = MockMIDITransport()
await mock.shutdown()  // Call when done
```

---

### 10. Test Hangs at "Exhaustion returns nil"

**Symptoms:**
- `swift test --no-parallel` hangs at PETransactionManager exhaustion test
- Test never completes
- No error output

**Causes:**
- `maxInflightPerDevice` set to 128 (equal to total RequestID count)
- All 128 IDs allocated
- 129th `begin()` call waits in `waitForDeviceSlot()`
- Nothing releases slots → infinite wait

**Solutions:**

```swift
// ✅ MIDI2Kit v2026-01-12+ includes fail-fast fix:
// begin() now returns nil immediately if no RequestIDs available
guard await requestIDManager.availableCount > 0 else {
    return nil  // Fail fast, don't wait
}

// ✅ For older versions, ensure something releases IDs
// or use lower maxInflightPerDevice in tests
let manager = PETransactionManager(
    maxInflightPerDevice: 2,  // Don't use 128 in exhaustion tests
    logger: logger
)
```

---

## Diagnostic Tools

### PETransactionManager Diagnostics

```swift
print(await transactionManager.diagnostics)
```

Output:
```
=== PETransactionManager ===
Max inflight per device: 2
Active transactions: 3
Available IDs: 125
Device states:
  MUID(0x01234567): inflight=2, waiting=1
Transactions:
  [0] DeviceInfo -> MUID(0x01234567) (1.2s)
  [1] ChCtrlList -> MUID(0x01234567) (0.8s)
  [2] ProgramList -> MUID(0x07654321) (0.3s)
```

### PEManager Diagnostics

```swift
print(await peManager.diagnostics)
```

### MIDITracer Dump

```swift
// Quick view
print(MIDITracer.shared.dump(last: 10))

// Full hex dump
print(MIDITracer.shared.dumpFull())

// Export for analysis
let json = try MIDITracer.shared.exportJSON()
```

### CIManager State

```swift
let devices = await ciManager.discoveredDevices
for device in devices {
    print("\(device.displayName): \(device.muid)")
    print("  PE: \(device.supportsPropertyExchange)")
    print("  Dest: \(await ciManager.destination(for: device.muid) ?? "nil")")
}
```

---

### 9. Ambiguous Type Lookup Errors

**Symptoms:**
- Xcode error: `'UMPGroup' is ambiguous for type lookup in this context`
- Xcode error: `'UMPMessageType' is ambiguous for type lookup in this context`
- Build fails with ambiguous type errors

**Causes:**
- Duplicate type definitions in same module
- Both `UMPTypes.swift` and `UMPMessage.swift` defining same types

**Solutions:**

1. **Apply the fix patch**: The canonical definitions are in `UMPTypes.swift`. Remove any duplicate definitions from `UMPMessage.swift`.

2. **Check for `.value` vs `.rawValue`**:
   ```swift
   // Wrong (old duplicate struct had .value)
   let grp = UInt32(group.value) << 24
   
   // Correct (UMPTypes.swift uses .rawValue)
   let grp = UInt32(group.rawValue) << 24
   ```

3. **Verify single definition**: Ensure `UMPGroup` and `UMPMessageType` are only defined in `UMPTypes.swift`.

**Prevention:**
- When adding new types, always check if they already exist in `UMPTypes.swift`
- Use `// Note: Type defined in UMPTypes.swift` comments for clarity

---

## Getting Help

1. **Check Diagnostics First**: Use the built-in diagnostic tools above
2. **Enable Verbose Logging**: Use `StdoutMIDI2Logger(minLevel: .debug)`
3. **Use MIDITracer**: Record message flow for analysis
4. **Isolate with MockMIDITransport**: Test without hardware
5. **Check CHANGELOG**: Known issues may already be fixed

### Reporting Issues

When reporting issues, include:
- MIDI2Kit version
- iOS/macOS version
- Device make/model
- Diagnostic output
- MIDITracer dump (sanitized if needed)
- Minimal reproduction code
