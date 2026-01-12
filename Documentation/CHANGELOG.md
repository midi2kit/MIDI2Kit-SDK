# MIDI2Kit Changelog

## 2026-01-12

### Documentation

#### Doc Comment `await` Cleanup (v4)
Removed unnecessary `await` keywords from doc comments in `CIManagerPEExtension.swift`.
The actual implementations are non-async, so sample code in documentation should match.

**Changes:**
- `await ciManager.peDeviceHandle(for: device.muid)` → `ciManager.peDeviceHandle(for: device.muid)`
- `await ciManager.peCapableDevices` → `ciManager.peCapableDevices`
- `await ciManager.peDeviceHandles` → `ciManager.peDeviceHandles`

**File:** `Sources/MIDI2Kit/CIManagerPEExtension.swift`

### Fixed

#### UMPGroup / UMPMessageType Ambiguous Type Error
**Problem:** Xcode reported ambiguous type lookup errors:
- `'UMPGroup' is ambiguous for type lookup in this context`
- `'UMPMessageType' is ambiguous for type lookup in this context`

**Root Cause:** Duplicate type definitions in same module (MIDI2Core):
- `Sources/MIDI2Core/UMPTypes.swift` - canonical definitions
- `Sources/MIDI2Core/UMP/UMPMessage.swift` - duplicate definitions

**Fix:**
1. Removed duplicate `UMPMessageType` enum from `UMPMessage.swift`
2. Removed duplicate `UMPGroup` struct from `UMPMessage.swift`
3. Replaced all `group.value` → `group.rawValue` for API compatibility
4. Added comment noting types are defined in `UMPTypes.swift`

**Files Changed:**
- `Sources/MIDI2Core/UMP/UMPMessage.swift` - removed duplicates
- `Sources/MIDI2Core/UMP/UMPSystemMessages.swift` - `.value` → `.rawValue`
- `Sources/MIDI2Core/UMP/UMPMIDI1ChannelVoice.swift` - `.value` → `.rawValue`

### Added

#### Batch Request API - Parallel PE Operations
**Fetch multiple resources concurrently with configurable limits:**

```swift
// Basic batch GET
let response = await peManager.batchGet(
    ["DeviceInfo", "ResourceList", "ProgramList"],
    from: device
)

// Check results
if let info = response["DeviceInfo"]?.response {
    print("Status: \(info.status)")
}
print("Success: \(response.successCount)/\(response.results.count)")

// With options
let response = await peManager.batchGet(
    resources,
    from: device,
    options: PEBatchOptions(maxConcurrency: 4, continueOnFailure: true)
)

// Typed batch (type-safe parallel fetch)
let (deviceInfo, resourceList) = try await peManager.batchGetTyped(
    from: device,
    ("DeviceInfo", PEDeviceInfo.self),
    ("ResourceList", [PEResourceEntry].self)
)

// Channel-specific batch
let response = await peManager.batchGetChannels(
    "ProgramInfo",
    channels: Array(0..<16),
    from: device
)
```

**Files:**
- `Sources/MIDI2PE/Batch/PEBatchRequest.swift`
- `Sources/MIDI2PE/Batch/PEManager+Batch.swift`

#### UMP Type-Safe API - MIDI 2.0 Message Construction
**Type-safe Universal MIDI Packet (UMP) message creation:**

```swift
// MIDI 2.0 Channel Voice (64-bit, high resolution)
try await transport.send(
    UMP.noteOn(channel: 0, note: 60, velocity: 0x8000),
    to: destination
)
try await transport.send(
    UMP.controlChange(channel: 0, controller: 74, value: 0x80000000),
    to: destination
)

// MIDI 1.0 Channel Voice (32-bit, compatible)
try await transport.send(
    UMP.midi1.volume(channel: 0, value: 100),
    to: destination
)

// Convenience methods on transport
try await transport.sendNoteOn(channel: 0, note: 60, velocity: 0x8000, to: dest)
try await transport.sendAllNotesOff(channel: 0, to: dest)

// Value conversion helpers
let velocity16 = UMP.velocity7to16(100)  // 7-bit → 16-bit
let cc32 = UMP.cc7to32(64)               // 7-bit → 32-bit
let pb32 = UMP.pitchBend14to32(8192)     // 14-bit → 32-bit
```

**Message Types:**
- `UMPMIDI2ChannelVoice` - Note On/Off, CC, Program, Pitch Bend, RPN/NRPN (64-bit)
- `UMPMIDI1ChannelVoice` - Legacy MIDI 1.0 messages (32-bit)
- `UMPSystemRealTime` - Clock, Start, Stop, Continue
- `UMPSystemCommon` - MTC, Song Position, Song Select
- `UMPUtility` - JR Clock, JR Timestamp

**Files:**
- `Sources/MIDI2Core/UMP/UMPMessage.swift`
- `Sources/MIDI2Core/UMP/UMPMIDI1ChannelVoice.swift`
- `Sources/MIDI2Core/UMP/UMPSystemMessages.swift`
- `Sources/MIDI2Core/UMP/UMP.swift`
- `Sources/MIDI2Transport/MIDITransport+UMP.swift`

#### MIDITransport.shutdown() - Stream Termination API
**New protocol method for clean shutdown of transport streams:**

```swift
public protocol MIDITransport: Sendable {
    /// Shut down the transport and finish all streams
    func shutdown() async
}

// Default no-op implementation provided
public extension MIDITransport {
    func shutdown() async { }
}
```

**Usage:**
```swift
// In tests - ensure async loops terminate
func tearDown() async throws {
    await transport.shutdown()
}

// In production - clean resource cleanup
func disconnect() async {
    await transport.shutdown()
}
```

#### Duration.asTimeInterval Extension
**Utility for converting Swift `Duration` to `TimeInterval`:**

```swift
extension Duration {
    var asTimeInterval: TimeInterval {
        let c = self.components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1e18
    }
}
```

### Fixed

#### CoreMIDITransport - Proper Shutdown with Resource Cleanup
**Problem:** `deinit` only disconnected sources and disposed client. Ports were not disposed, streams could leak.

**Fix:** New `shutdown()` / `shutdownSync()` implementation:
- Idempotent (safe to call multiple times)
- Thread-safe via `NSLock`
- Proper cleanup order: disconnect sources → dispose ports → dispose client → finish streams
- Clears continuation references to prevent leaks

#### MockMIDITransport.shutdown() - Async Protocol Conformance
`shutdown()` signature changed from sync to `async` for protocol conformance.

#### PETransactionManager - RequestID Exhaustion Hang Fix
**Problem:** `swift test --no-parallel` hung at "Exhaustion returns nil" test.

**Root Cause:**
- With `maxInflightPerDevice: 128`, calling `begin()` 128 times fills all slots
- 129th call enters `waitForDeviceSlot()` waiting for a slot to free
- Nothing releases slots → infinite wait

**Fix:** Fail-fast guard before waiting:
```swift
public func begin(...) async -> UInt8? {
    guard await requestIDManager.availableCount > 0 else {
        return nil  // Fail fast
    }
    await waitForDeviceSlot(destinationMUID)
    // ...
}
```

### Changed

#### PEManager - Duration to TimeInterval Conversion
Updated `transactionManager.begin()` calls to use `timeout.asTimeInterval`.

### Fixed

#### CoreMIDITransport.send() - Race Condition with shutdown()
**Problem:** `send()` did not check `didShutdown` flag before using `outputPort`, risking use of disposed port.

**Fix:** Thread-safe check using `withLock` closure (Swift 6 async-compatible):
```swift
public func send(_ data: [UInt8], to destination: MIDIDestinationID) async throws {
    let (isShutdown, port) = shutdownLock.withLock {
        (didShutdown, outputPort)
    }
    guard !isShutdown, port != 0 else {
        throw MIDITransportError.notInitialized
    }
    // ... send using captured port
}
```

#### PEManager deinit - Incomplete Cleanup
**Problem:** `deinit` only cancelled `receiveTask`, leaving `pendingContinuations`, `timeoutTasks`, and `sendTasks` potentially leaked.

**Fix:** Added comprehensive cleanup with documentation:
```swift
deinit {
    // Note: Callers should ensure stopReceiving() before releasing PEManager
    receiveTask?.cancel()
    for task in timeoutTasks.values { task.cancel() }
    for task in sendTasks.values { task.cancel() }
    notificationContinuation?.finish()
}
```

#### CIManager deinit - Missing Device Lost Events
**Problem:** `deinit` cleared devices without emitting `deviceLost` events.

**Fix:** Added documentation noting proper cleanup pattern:
```swift
// For proper cleanup with events, call stop() before releasing CIManager
```

#### MockMIDITransport.withKORGDevice() - Async Race Condition
**Problem:** Method returned before async `setupKORGDevice()` completed, causing test failures.

**Fix:** Changed to fully async API:
```swift
// Before (race condition)
public static func withKORGDevice() -> MockMIDITransport {
    let transport = MockMIDITransport()
    Task { await transport.setupKORGDevice() }  // Returns before setup!
    return transport
}

// After (properly awaited)
public static func withKORGDevice() async -> MockMIDITransport {
    let transport = MockMIDITransport()
    await transport.setupKORGDevice()
    return transport
}
```

Also added:
- `setupKORGDevice()` now public
- `withDevice(name:manufacturer:) async` generic helper
- `setSourceToDestinationMapping(_:to:)` for explicit routing

#### PETransactionManager.begin() - TOCTOU Race Condition
**Problem:** `availableCount > 0` check followed by `waitForDeviceSlot()` allowed IDs to be exhausted during the wait.

**Fix:** Acquire Request ID first (atomic), then wait for device slot:
```swift
// Before (TOCTOU vulnerable)
guard await requestIDManager.availableCount > 0 else { return nil }
await waitForDeviceSlot(destinationMUID)
guard let requestID = requestIDManager.acquire() else { ... }

// After (atomic acquisition first)
guard let requestID = requestIDManager.acquire() else { return nil }
await waitForDeviceSlot(destinationMUID)
if isStopped || generation != startGeneration {
    requestIDManager.release(requestID)  // Release if cancelled
    return nil
}
```

#### PEManager.startNotificationStream() - Continuation Race
**Problem:** `finish()` called on old continuation, then new AsyncStream created - gap allowed yield to finishing continuation.

**Fix:** Clear reference before finishing:
```swift
// Before
notificationContinuation?.finish()
return AsyncStream { continuation in
    self.notificationContinuation = continuation
}

// After
let oldContinuation = notificationContinuation
notificationContinuation = nil  // Clear first
oldContinuation?.finish()       // Then finish
return AsyncStream { continuation in
    self.notificationContinuation = continuation
}
```

---

## 2026-01-11

### Added

#### MIDI 2.0 UMP Support
**Full support for MIDI 2.0 Universal MIDI Packet messages:**

- **UMPBuilder**: Build MIDI 2.0 and MIDI 1.0 UMP messages
  - MIDI 2.0 Channel Voice (64-bit): Control Change, Note On/Off, Pitch Bend, Program Change, etc.
  - Per-Note controllers for MPE: Per-Note Pitch Bend, Per-Note Management
  - RPN/NRPN with 32-bit resolution
  - MIDI 1.0 over UMP (32-bit): Wrapped MIDI 1.0 messages
  - Utility messages: NOOP, JR Clock, JR Timestamp

- **UMPParser**: Parse received UMP messages
  - Parse into structured `ParsedUMPMessage` enum
  - Convenience properties for note/velocity/CC values
  - Automatic value scaling to different resolutions

- **UMPTypes**: Type definitions
  - `UMPMessageType`: Message types with word counts
  - `MIDI2ChannelVoiceStatus`: Status codes
  - `NoteAttributeType`: Note attributes
  - `ProgramBank`, `ControllerAddress`: Bank/controller types
  - `RegisteredController`: Common RPN addresses
  - `PitchBendValue`: Constants for pitch bend

- **UMPValueScaling**: Value conversion utilities
  - 7-bit ↔ 32-bit scaling
  - 14-bit ↔ 32-bit scaling
  - Velocity scaling (7-bit ↔ 16-bit)
  - Normalized (0.0-1.0) ↔ 32-bit

```swift
// Build MIDI 2.0 Control Change
let words = UMPBuilder.midi2ControlChange(
    group: 0, channel: 0, controller: 74, value: 0x80000000
)

// Parse received UMP
if let message = UMPParser.parse(words),
   case .midi2ChannelVoice(let cv) = message {
    print("CC \(cv.controllerNumber): \(cv.controllerValue32)")
}
```

#### MIDITracer - Diagnostics System
**Ring buffer for MIDI message tracing:**

- Thread-safe recording (NSLock based)
- Configurable capacity (default: 200 entries)
- Enable/disable at runtime
- Auto-detect MIDI-CI message labels
- Multiple output formats: `dump()`, `dumpFull()`, `exportJSON()`
- Time-based and endpoint-based filtering
- Shared global instance: `MIDITracer.shared`

```swift
let tracer = MIDITracer(capacity: 100)
tracer.recordSend(to: destination, data: message)
tracer.recordReceive(from: source, data: response)
print(tracer.dump(last: 20))
```

### Documentation

- Added `Troubleshooting.md` with common issues and solutions
- Updated API.md with UMP and MIDITracer documentation
- Updated Architecture.md with UMP component overview
- Updated BestPractices.md with UMP and MIDITracer guidance

---

## 2026-01-10 (Session 4-6)

### Added

#### PESubscriptionManager - Auto-Reconnection Support
**New component for managing PE subscriptions with automatic reconnection:**

```swift
let subscriptionManager = PESubscriptionManager(
    peManager: peManager,
    ciManager: ciManager
)
await subscriptionManager.start()

// Subscribe with auto-reconnect capability
let intentID = try await subscriptionManager.subscribe(
    to: "ProgramList",
    on: device.muid,
    identity: device.identity  // Used for matching after MUID changes
)

// Handle events (survives device reconnections)
for await event in subscriptionManager.events {
    switch event {
    case .notification(let n):
        print("Data: \(n.data)")
    case .suspended(let id, let reason):
        print("Subscription \(id) suspended: \(reason)")
    case .restored(let id, let newSubscribeId):
        print("Subscription \(id) restored!")
    case .failed(let id, let reason):
        print("Subscription \(id) failed: \(reason)")
    case .subscribed(let id, let subscribeId):
        print("Subscribed \(id) -> \(subscribeId)")
    }
}
```

**Features:**
- Automatic re-subscription when devices reconnect
- Device matching by identity (survives MUID changes)
- Configurable retry attempts and delays
- Unified event stream for subscription lifecycle

#### Per-Device Inflight Limiting
**Prevents overwhelming slow devices with concurrent requests:**

```swift
let manager = PETransactionManager(
    maxInflightPerDevice: 2,  // Max 2 concurrent requests per device
    logger: logger
)
```

**Behavior:**
- Excess requests wait in FIFO queue
- Waiters automatically resume when slots become available
- Per-device tracking (different devices can have concurrent requests)
- Default limit: 2 requests per device

#### CIManager Events
**Event-driven device lifecycle monitoring:**

```swift
public enum CIManagerEvent: Sendable {
    case deviceDiscovered(DiscoveredDevice)
    case deviceLost(MUID)
    case deviceUpdated(DiscoveredDevice)
    case discoveryStarted
    case discoveryStopped
}

for await event in ciManager.events {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.displayName)")
    case .deviceLost(let muid):
        print("Lost: \(muid)")
    // ...
    }
}
```

### Fixed

#### CIManager - Source-to-Destination Mapping
**Problem:** `findDestination(for:)` assumed source endpoint ref == destination endpoint ref, which rarely holds true in CoreMIDI.

**Solution:** Use Entity-based mapping via `MIDIEndpointGetEntity` and `MIDIEntityGetDestination`:

```swift
// Find destination on same entity as source
public func destination(for muid: MUID) async -> MIDIDestinationID? {
    guard let entry = devices[muid],
          let sourceID = entry.sourceID else { return nil }
    
    // Find entity containing this source
    var entity: MIDIEntityRef = 0
    guard MIDIEndpointGetEntity(sourceID.value, &entity) == noErr else { return nil }
    
    // Get destination from same entity
    if MIDIEntityGetNumberOfDestinations(entity) > 0 {
        return MIDIDestinationID(MIDIEntityGetDestination(entity, 0))
    }
    
    return nil
}
```

#### MUID Validation in Tests
**Problem:** Test code used `MUID(rawValue: 0x12345678)!` which exceeded the 28-bit limit (0x0FFFFFFF), causing force unwrap crashes.

**Fix:** Changed test values to valid 28-bit MUIDs:
```swift
// Before (invalid - crashes)
let muid = MUID(rawValue: 0x12345678)!  // > 0x0FFFFFFF

// After (valid)
let muid = MUID(rawValue: 0x01234567)!  // <= 0x0FFFFFFF
```

#### stopReceiving Tests - Inflight Limiting Compatibility
**Problem:** Tests expected all requests to be "Pending", but per-device inflight limiting queues excess requests as "waiters".

**Fix:** Updated tests to verify correct inflight/waiting distribution:
```swift
// With maxInflightPerDevice=2, 5 requests become:
// 2 inflight (active) + 3 waiting
#expect(diagBefore.contains("inflight=2, waiting=3"))
```

### Changed

#### PETransactionManager - Responsibility Separation
**Simplified architecture with clear responsibility boundaries:**

| Responsibility | PETransactionManager | PEManager |
|----------------|:-------------------:|:---------:|
| Request ID allocation/release | ✅ | ❌ |
| Chunk assembly | ✅ | ❌ |
| Transaction state tracking | ✅ | ❌ |
| Per-device inflight limiting | ✅ | ❌ |
| **Timeout scheduling** | ❌ | ✅ |
| **Continuation management** | ❌ | ✅ |
| **Response delivery** | ❌ | ✅ |

**Removed from PETransactionManager:**
- `complete(requestID:header:body:)`
- `completeWithError(requestID:status:message:)`
- `checkTimeouts()`
- `startMonitoring()` / `stopMonitoring()`
- `waitForCompletion(requestID:)`
- `PEMonitoringConfiguration`
- `PEMonitorHandle`
- `completionHandlers` dictionary

### Test Coverage

**142+ tests total** (up from 121)

| Suite | Tests | Changes |
|-------|------:|---------|
| PETransactionManagerTests | 24 | Updated for simplified API |
| PEManagerTests | 15+ | Added inflight limiting tests |
| PESubscriptionManagerTests | New | Auto-reconnection tests |
| CIManagerTests | Updated | Event handling tests |
| PEDeviceHandleTests | Fixed | MUID validation |

---

## 2026-01-10 (Session 3)

### Fixed

#### PEManager.stopReceiving() - RequestID Leak & Unsafe Mutation
- **RequestID leak**: Now calls `transactionManager.cancelAll()` to release all Request IDs on stop
- **Unsafe dictionary mutation**: Fixed iterating `pendingContinuations` while mutating
  ```swift
  // Before (unsafe)
  for (requestID, continuation) in pendingContinuations {
      pendingContinuations.removeValue(forKey: requestID)  // ❌
  }
  
  // After (safe)
  for continuation in pendingContinuations.values {
      continuation.resume(throwing: PEError.cancelled)
  }
  pendingContinuations.removeAll()
  ```

#### CoreMIDITransport.handlePacketList() - Packet Order for SysEx Assembly
- **Problem**: Each packet spawned separate Task → order not guaranteed → SysEx corruption
- **Fix**: Collect all packets first, then process sequentially in single Task
  ```swift
  // Before (order not guaranteed)
  for packet in packets {
      Task { await processReceivedData(data) }  // ❌ Race condition
  }
  
  // After (order guaranteed)
  var allPacketData: [[UInt8]] = []
  for packet in packets { allPacketData.append(data) }
  Task {
      for data in allPacketData { await processReceivedData(data) }  // ✅
  }
  ```

#### PETransactionManager.waitForCompletion() - Double-Call Continuation Overwrite
- **Problem**: Multiple calls for same requestID would overwrite previous continuation
- **Fix**: Return `.cancelled` immediately if already waiting
  ```swift
  if completionHandlers[requestID] != nil {
      return .cancelled  // Prevent overwrite
  }
  ```

#### CoreMIDITransport - sourceID Always nil
- **Problem**: `MIDIReceivedData.sourceID` was never populated
- **Fix**: Pass source as `connRefCon` in `MIDIPortConnectSource`, extract in callback
  ```swift
  // Connect with source ref as connRefCon
  let connRefCon = UnsafeMutableRawPointer(bitPattern: UInt(sourceRef))
  MIDIPortConnectSource(inputPort, sourceRef, connRefCon)
  
  // Extract in callback
  MIDIInputPortCreateWithBlock(...) { packetList, srcConnRefCon in
      let sourceRef = MIDIEndpointRef(UInt(bitPattern: srcConnRefCon))
      ...
  }
  ```

### Changed

#### PEManager - Unified Timeout Management
- **Problem**: Dual timeout management (PETransactionManager.startMonitoring + per-request Task)
- **Fix**: Removed `monitorHandle`, centralized timeout in `PEManager.timeoutTasks`
- Responsibilities now clearly separated:
  - `PETransactionManager`: RequestID lifecycle, chunk assembly
  - `PEManager`: Response delivery, timeout-to-continuation mapping

### Added

#### SysExAssemblerTests (18 tests)
- Complete SysEx in single/multiple packets
- Fragmented SysEx across 2-3 packets
- Order sensitivity tests demonstrating corruption on wrong order
- Corruption handling (F0 before F7)
- Large SysEx message assembly (1000+ bytes)

#### PETransactionManager waitForCompletion Tests (4 tests)
- Returns result on complete
- Returns cancelled for unknown requestID
- Duplicate call returns cancelled
- Does not leak continuation on duplicate call

---

## 2026-01-10 (Session 1 & 2)

### Added

#### PEMonitorHandle - Automatic Timeout Monitoring
- New `PEMonitorHandle` class for lifecycle-based timeout monitoring
- `startMonitoring()` returns handle - **hold this handle to keep monitoring active**
- Handle deallocation automatically stops monitoring and cancels Task
- Eliminates need for manual `checkTimeouts()` timer setup
- Idempotent: calling `startMonitoring()` multiple times returns same handle

```swift
// Start monitoring - HOLD the handle!
let handle = await transactionManager.startMonitoring()

// Monitoring runs automatically in background...

// Stop explicitly
await handle.stop()

// Or just release handle - monitoring stops automatically
// handle = nil
```

#### MIDI2Logger - Configurable Logging System
- `MIDI2LogLevel`: debug, info, notice, warning, error, fault
- `MIDI2Logger` protocol with convenience methods
- Built-in implementations:
  - `NullMIDI2Logger`: Silent (default)
  - `StdoutMIDI2Logger`: Development/debugging
  - `OSLogMIDI2Logger`: Production (Apple's os.log)
  - `CompositeMIDI2Logger`: Forward to multiple loggers

```swift
// Enable logging for debugging
let logger = StdoutMIDI2Logger(minLevel: .debug)
let manager = PETransactionManager(logger: logger)
```

#### CIMessageParser Tests
- 24 new boundary condition tests for parseNAK, parseDiscoveryReply, parsePEReply, etc.
- Fixed parseNAK bounds check (payload[9] requires count >= 10)

### Fixed

#### PEMonitorHandle Lifecycle
- Fixed retain cycle: Task now uses `[weak self]` and shared `MonitorRunningState`
- `isActive` correctly reflects Task termination (not just cancellation)
- Manager can be deallocated while monitoring - Task exits cleanly

#### CoreMIDITransport
- Added `MIDITransportError.packetListFull` case
- Fixed MIDIPacketListAdd failure detection

### Changed

- `PEMonitoringConfiguration.autoStart` removed - use `startMonitoring()` explicitly
- `PEMonitoringConfiguration.checkInterval` is now `let` (immutable)

---

## 2026-01-09 (Initial Release)

### Added

- **MIDI2Core**: Foundation types (MUID, DeviceIdentity, Mcoded7, Constants)
- **MIDI2CI**: Message building and parsing, DiscoveredDevice, CIManager
- **MIDI2PE**: Transaction management, chunk assembly, resource types
- **MIDI2Transport**: CoreMIDI integration, MockMIDITransport, SysExAssembler
- **MIDI2Kit**: Umbrella module re-exporting all modules

### Documentation

- README with quick start guide
- Architecture documentation
- API reference
- Best practices guide
