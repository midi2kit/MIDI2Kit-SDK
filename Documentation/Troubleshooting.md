# MIDI2Kit Troubleshooting Guide

## Common Issues

### 1. Request ID Exhaustion

**Symptoms:**
- `begin()` returns `nil`
- `PEError.requestIDExhausted` thrown
- PE operations stop working

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
```

---

### 2. PE Chunk Assembly Failures

**Symptoms:**
- Partial responses
- Timeout waiting for chunks
- Data corruption in multi-chunk responses

**Solutions:**

```swift
// ✅ Reduce concurrent requests per device
let manager = PETransactionManager(
    maxInflightPerDevice: 1,  // Strict: one at a time
    logger: logger
)

// ✅ Increase chunk timeout
let assembler = PEChunkAssembler(timeout: 10.0)  // 10 seconds
```

---

### 3. Device Not Found

**Symptoms:**
- `CIManager.destination(for:)` returns `nil`
- `PEError.deviceNotFound` thrown

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
    identity: device.identity
)

// ✅ Listen for device events
for await event in ciManager.events {
    switch event {
    case .deviceLost(let muid):
        await transactionManager.cancelAll(for: muid)
    default:
        break
    }
}
```

---

### 4. Test Failures

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

### 5. Test Hangs at "Exhaustion returns nil"

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
```

### MIDITracer Dump

```swift
print(MIDITracer.shared.dump(last: 10))
print(MIDITracer.shared.dumpFull())
```

---

## Getting Help

1. **Check Diagnostics First**: Use the built-in diagnostic tools above
2. **Enable Verbose Logging**: Use `StdoutMIDI2Logger(minLevel: .debug)`
3. **Use MIDITracer**: Record message flow for analysis
4. **Isolate with MockMIDITransport**: Test without hardware
5. **Check CHANGELOG**: Known issues may already be fixed
