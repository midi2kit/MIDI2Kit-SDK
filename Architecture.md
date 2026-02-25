# MIDI2Kit Architecture

## Overview

MIDI2Kit is a modular Swift library for MIDI 2.0, MIDI-CI, and Property Exchange. It's designed with Swift 6 concurrency in mind, using actors for thread safety and async/await for clean asynchronous code.

```
┌─────────────────────────────────────────────────────────────┐
│                        MIDI2Kit                              │
│  (Umbrella module - re-exports all sub-modules)             │
└─────────────────────────────────────────────────────────────┘
        │           │           │           │
        ▼           ▼           ▼           ▼
┌───────────┐ ┌───────────┐ ┌───────────┐ ┌─────────────────┐
│ MIDI2Core │ │ MIDI2CI   │ │ MIDI2PE   │ │ MIDI2Transport  │
│           │ │           │ │           │ │                 │
│ • MUID    │ │ • Message │ │ • Resource│ │ • CoreMIDI      │
│ • Device  │ │   Builder │ │   Types   │ │   Integration   │
│   Identity│ │ • Message │ │ • Chunk   │ │ • Connection    │
│ • Mcoded7 │ │   Parser  │ │   Assembly│ │   Management    │
│ • Consts  │ │ • CI      │ │ • Trans-  │ │ • SysEx         │
│ • Logger  │ │   Manager │ │   action  │ │   Assembly      │
│           │ │           │ │   Manager │ │                 │
└───────────┘ └───────────┘ └───────────┘ └─────────────────┘
```

## Module Dependencies

```
MIDI2Kit ──────┬──────────────────────────────────────┐
               │                                       │
               ▼                                       ▼
         MIDI2Transport                           MIDI2PE
               │                                       │
               ▼                                       ▼
         MIDI2Core ◄────────────────────────────── MIDI2CI
                                                       │
                                                       ▼
                                                  MIDI2Core
```

## Module Details

### MIDI2Core

**Purpose**: Foundation types used throughout the library.

**Key Types**:

| Type | Description |
|------|-------------|
| `MUID` | 28-bit MIDI Unique Identifier (0x0000_0000 - 0x0FFF_FFFF) |
| `DeviceIdentity` | Manufacturer, family, model, version |
| `ManufacturerID` | Standard (1-byte) or Extended (3-byte) |
| `Mcoded7` | 8-bit ↔ 7-bit SysEx encoding |
| `CIMessageType` | All MIDI-CI message types |
| `CategorySupport` | Protocol/Profile/PE/Process flags |
| `MIDI2Logger` | Configurable logging protocol |
| `MIDI2LogUtils` | Safe formatting utilities |

**Logging System**:

```
┌─────────────────────────────────────────────────────────────┐
│                     MIDI2Logger                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Protocol: MIDI2Logger                                       │
│    func log(_ level: MIDI2LogLevel, _ message, category)    │
│                                                              │
│  Built-in Implementations:                                   │
│    ├─ NullMIDI2Logger      (silent, default)                │
│    ├─ StdoutMIDI2Logger    (development)                    │
│    ├─ OSLogMIDI2Logger     (production, Apple os.log)       │
│    └─ CompositeMIDI2Logger (forward to multiple)            │
│                                                              │
│  Levels: debug < info < notice < warning < error < fault    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Design Notes**:
- All types are `Sendable` for Swift 6 concurrency
- `MUID` validates 28-bit constraint (0x0000_0000 - 0x0FFF_FFFF)
- `Mcoded7` handles encoding in 7-byte groups

**UMP (MIDI 2.0) Support**:

```
┌─────────────────────────────────────────────────────────────┐
│                     UMP Components                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  UMPBuilder                                                  │
│    • Build MIDI 2.0 messages (64-bit high resolution)       │
│    • Build MIDI 1.0 wrapped in UMP (32-bit)                 │
│    • Build Utility messages (NOOP, JR Clock/Timestamp)      │
│                                                              │
│  UMPParser                                                   │
│    • Parse UMP words into structured messages               │
│    • Extract message type, group, channel                   │
│    • Convenience properties for note/velocity/CC values     │
│                                                              │
│  UMPTypes                                                    │
│    • Message type definitions (0x0-0xF)                     │
│    • Channel Voice status codes                              │
│    • Note attributes, Bank/Address types                     │
│                                                              │
│  UMPValueScaling                                             │
│    • 7-bit ↔ 32-bit scaling                                 │
│    • 14-bit ↔ 32-bit scaling (pitch bend)                   │
│    • Velocity scaling (7-bit ↔ 16-bit)                      │
│    • Normalized (0.0-1.0) ↔ 32-bit                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**MIDITracer (Diagnostics)**:

```
┌─────────────────────────────────────────────────────────────┐
│                     MIDITracer                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Ring buffer for MIDI message tracing                        │
│    • Thread-safe (NSLock based)                             │
│    • Configurable capacity (default: 200 entries)           │
│    • Enable/disable at runtime                               │
│                                                              │
│  Recording:                                                  │
│    • record(direction, endpoint, data, label)               │
│    • recordSend() / recordReceive()                         │
│                                                              │
│  Retrieval:                                                  │
│    • entries / lastEntries(n)                               │
│    • entries(direction:) / entries(endpoint:)               │
│    • entries(from:to:) for time range                       │
│                                                              │
│  Output:                                                     │
│    • dump() / dump(last:) / dumpFull()                      │
│    • exportJSON() for external analysis                     │
│                                                              │
│  Auto-label detection:                                       │
│    • Recognizes MIDI-CI message types                       │
│    • "Discovery", "PE GET", "PE SET Reply", etc.           │
│                                                              │
│  Shared instance: MIDITracer.shared                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### MIDI2CI

**Purpose**: MIDI Capability Inquiry message building, parsing, and device management.

**Key Types**:

| Type | Description |
|------|-------------|
| `CIManager` | Central manager for CI devices, events, and MUID lifecycle |
| `DiscoveredDevice` | Device found via Discovery |
| `CIMessageBuilder` | Builds CI SysEx messages |
| `CIMessageParser` | Parses CI SysEx messages |
| `CIManagerEvent` | Device discovery and lifecycle events |

**CIManager**:

```
┌─────────────────────────────────────────────────────────────┐
│                      CIManager (actor)                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Responsibilities:                                           │
│    • Generate and manage local MUID                         │
│    • Track discovered devices                               │
│    • Handle device invalidation                             │
│    • Provide device lookup by MUID                          │
│    • Map Source endpoint to Destination (via Entity)        │
│    • Emit discovery events via AsyncStream                  │
│                                                              │
│  Key Methods:                                                │
│    start() / stop()                                         │
│    device(for: MUID) → DiscoveredDevice?                    │
│    destination(for: MUID) → MIDIDestinationID?              │
│    handleDiscoveryReply(payload:) → DiscoveredDevice        │
│    handleInvalidateMUID(payload:)                           │
│    clearAllDevices()                                        │
│                                                              │
│  Events:                                                     │
│    deviceDiscovered, deviceLost, deviceUpdated             │
│    discoveryStarted, discoveryStopped                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Source-to-Destination Mapping**:

CoreMIDI uses separate endpoints for input (Source) and output (Destination). They belong to the same Entity:

```
Physical Device
  └── Entity (MIDIEntityRef)
       ├── Source (MIDIEndpointRef A) ← CI replies come FROM here
       └── Destination (MIDIEndpointRef B) ← CI requests go TO here
```

`CIManager.destination(for:)` uses `MIDIEndpointGetEntity` and `MIDIEntityGetDestination` to find the correct destination for a device.

**Message Flow**:

```
App                     MIDI2CI                    Device
 │                         │                         │
 │  discoveryInquiry()     │                         │
 │────────────────────────▶│                         │
 │                         │   [F0 7E 7F 0D 70...]   │
 │                         │────────────────────────▶│
 │                         │                         │
 │                         │   [F0 7E 7F 0D 71...]   │
 │                         │◀────────────────────────│
 │  parse() → Reply        │                         │
 │◀────────────────────────│                         │
```

### MIDI2PE

**Purpose**: Property Exchange with transaction lifecycle management.

**Key Types**:

| Type | Description |
|------|-------------|
| `PEResource` | Standard resource names (DeviceInfo, ChCtrlList, etc.) |
| `PEDeviceInfo` | Device information from DeviceInfo resource |
| `PEControllerDef` | Controller definition from ChCtrlList |
| `PEChunkAssembler` | Assembles multi-chunk responses |
| `PEChunkResult` | Result of chunk processing |
| `PERequestIDManager` | Manages 7-bit Request IDs (0-127) |
| `PETransactionManager` | Request ID lifecycle, chunk assembly, per-device limiting |
| `PEManager` | High-level PE API with timeout and continuation management |
| `PESubscriptionManager` | Auto-reconnecting subscription management |

**Responsibility Separation**:

```
┌─────────────────────────────────────────────────────────────┐
│                  Component Responsibilities                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PETransactionManager:                                       │
│    ✅ Request ID allocation/release                         │
│    ✅ Chunk assembly                                        │
│    ✅ Transaction state tracking                            │
│    ✅ Per-device inflight limiting                          │
│    ❌ Timeout scheduling                                    │
│    ❌ Continuation management                               │
│                                                              │
│  PEManager:                                                  │
│    ❌ Request ID management                                 │
│    ❌ Chunk assembly                                        │
│    ✅ Timeout scheduling (per-request Tasks)               │
│    ✅ Continuation management                               │
│    ✅ Response delivery                                     │
│    ✅ High-level get/set/subscribe API                     │
│                                                              │
│  PESubscriptionManager:                                      │
│    ✅ Auto-reconnection handling                            │
│    ✅ Device identity matching                              │
│    ✅ Subscription intent tracking                          │
│    ✅ Unified event stream                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Per-Device Inflight Limiting**:

```
┌─────────────────────────────────────────────────────────────┐
│                Per-Device Inflight Limiting                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Problem: Some devices can't handle many concurrent PE      │
│  requests (e.g., KORG Module Pro drops chunks)              │
│                                                              │
│  Solution: Limit concurrent requests per device             │
│                                                              │
│  Configuration:                                              │
│    maxInflightPerDevice: Int (default: 2)                   │
│                                                              │
│  Behavior:                                                   │
│    • begin() waits if device is at capacity                 │
│    • Waiters queued in FIFO order                           │
│    • cancel() resumes next waiter automatically             │
│    • Different devices can have concurrent requests         │
│                                                              │
│  Example with maxInflightPerDevice=2:                       │
│                                                              │
│    Request 1 → [ACTIVE] ─────────────┐                      │
│    Request 2 → [ACTIVE] ────────────┐│                      │
│    Request 3 → [WAITING] ───────────┼┤ Device A             │
│    Request 4 → [WAITING] ───────────┼┘                      │
│    Request 5 → [ACTIVE] ────────────┘   Device B            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Chunk Processing Results**:

```swift
public enum PEChunkResult {
    case incomplete(received: Int, total: Int)
    case complete(header: Data, body: Data)
    case timeout(requestID: UInt8, received: Int, total: Int, partial: Data?)
    case unknownRequestID(requestID: UInt8)  // Distinct from timeout!
}
```

> **Important**: `unknownRequestID` vs `timeout`:
> - `timeout`: Transaction existed but didn't complete in time
> - `unknownRequestID`: No active transaction found
>   - Late response (transaction already completed)
>   - Duplicate response
>   - Response for cancelled transaction
>   - Misrouted message / ID collision

**Subscription Management**:

```
┌─────────────────────────────────────────────────────────────┐
│               PESubscriptionManager                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Subscription Intent (what user wants):                      │
│    • Resource name                                           │
│    • Device MUID (may change)                               │
│    • Device Identity (for matching after MUID change)       │
│                                                              │
│  States:                                                     │
│    .active(subscribeId, muid) - Subscription is live        │
│    .pending - Waiting for device                            │
│    .failed(reason) - Subscription failed                    │
│                                                              │
│  Events:                                                     │
│    .subscribed - Initial subscription established           │
│    .suspended - Device disconnected                         │
│    .restored - Device reconnected, re-subscribed            │
│    .failed - Subscription failed                            │
│    .notification - Received PE notification                 │
│                                                              │
│  Auto-Reconnection Flow:                                     │
│    1. Device disconnects → .suspended                       │
│    2. Same device reconnects (matched by identity)          │
│    3. Wait resubscribeDelay                                 │
│    4. Re-subscribe (up to maxRetryAttempts)                 │
│    5. Success → .restored, Fail → .failed                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Transaction Lifecycle**:

```
┌─────────────────────────────────────────────────────────────┐
│                  PETransactionManager                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  begin() ─────────────┬─────────────────────────────────────│
│      │                │                                      │
│      ▼                ▼                                      │
│  [WAIT for slot] → [ALLOCATE ID] → [TRACK]                  │
│                                       │                      │
│              ┌────────────────────────┘                     │
│              │                                              │
│              ▼                                              │
│     [PROCESS CHUNKS] ─────┐                                 │
│              │            │                                 │
│              ▼            ▼                                 │
│     [.complete]    [.timeout / cancel()]                    │
│              │            │                                 │
│              └────────────┘                                 │
│                    │                                        │
│                    ▼                                        │
│           [RELEASE ID + SLOT]                               │
│                    │                                        │
│                    ▼                                        │
│           [RESUME NEXT WAITER]                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Why PETransactionManager is Critical**:

Request IDs are 7-bit (0-127). Without proper lifecycle management:
- Leaked IDs accumulate
- Eventually all 128 IDs are exhausted
- PE becomes non-functional
- Device requires reconnection

### MIDI2Transport

**Purpose**: CoreMIDI abstraction with connection state management.

**Key Types**:

| Type | Description |
|------|-------------|
| `MIDITransport` | Protocol for transport implementations |
| `CoreMIDITransport` | CoreMIDI implementation |
| `MockMIDITransport` | Testing without hardware |
| `SysExAssembler` | Assembles fragmented SysEx |
| `ConnectionState` | Thread-safe connection tracking |

**Connection Management**:

```
┌─────────────────────────────────────────────────────────────┐
│                   CoreMIDITransport                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────┐               │
│  │     ConnectionState (thread-safe)         │               │
│  │  ┌────────────────────────────────────┐  │               │
│  │  │ connectedSources: Set<Endpoint>    │  │               │
│  │  └────────────────────────────────────┘  │               │
│  └──────────────────────────────────────────┘               │
│                                                              │
│  connectToAllSources():                                      │
│    1. Get current sources from CoreMIDI                     │
│    2. Disconnect removed (Set difference)                   │
│    3. Connect new only (Set difference)                     │
│    → No duplicates, no missed disconnects                   │
│                                                              │
│  reconnectAllSources():                                      │
│    1. Disconnect all                                         │
│    2. Connect all                                            │
│    → Clean slate when needed                                 │
│                                                              │
│  Source ID Tracking:                                         │
│    • connRefCon passed to MIDIPortConnectSource             │
│    • Extracted in callback to populate sourceID             │
│                                                              │
│  Packet Order Guarantee:                                     │
│    • All packets collected first                            │
│    • Processed sequentially in single Task                  │
│    → Prevents SysEx corruption from race conditions         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Concurrency Model

MIDI2Kit uses Swift 6 strict concurrency:

| Component | Isolation |
|-----------|-----------|
| `CIManager` | `actor` |
| `PETransactionManager` | `actor` |
| `PEManager` | `actor` |
| `PESubscriptionManager` | `actor` |
| `SysExAssembler` | `actor` |
| `MockMIDITransport` | `actor` |
| Data types | `Sendable struct/enum` |
| `CoreMIDITransport` | `@unchecked Sendable` (uses internal locking) |
| `ConnectionState` | `@unchecked Sendable` (NSLock for sync access) |

**CoreMIDITransport locking**

`CoreMIDITransport` is marked `@unchecked Sendable` and protects its CoreMIDI client/ports with `shutdownLock`.
`send()` performs the `MIDISend` call while holding `shutdownLock`, so a concurrent `shutdownSync()` cannot dispose the
output port mid-send (prevents use-after-dispose crashes). If shutdown has started, `send()` throws
`MIDITransportError.notInitialized`.



## Error Handling

```swift
public enum MIDITransportError: Error, CustomStringConvertible {
    case notInitialized
    case clientCreationFailed(Int32)
    case portCreationFailed(Int32)
    case sendFailed(Int32)
    case connectionFailed(Int32)
    case destinationNotFound(UInt32)
    case sourceNotFound(UInt32)
    case packetListAddFailed(dataSize: Int, bufferSize: Int)
    case packetListEmpty
}

public enum PEError: Error {
    case requestIDExhausted
    case timeout(resource: String)
    case cancelled
    case deviceError(status: Int, message: String?)
    case transportError(Error)
    case invalidResponse
}

public enum PETransactionResult {
    case success(header: Data, body: Data)
    case error(status: Int, message: String?)
    case timeout
    case cancelled
}

public enum PEChunkResult: CustomStringConvertible {
    case incomplete(received: Int, total: Int)
    case complete(header: Data, body: Data)
    case timeout(requestID: UInt8, received: Int, total: Int, partial: Data?)
    case unknownRequestID(requestID: UInt8)
}
```

## Data Flow Example

Complete PE Get flow with per-device limiting:

```
┌──────┐    ┌────────────┐    ┌─────────────┐    ┌──────────┐
│ App  │    │ MIDI2PE    │    │ MIDI2CI     │    │ Transport│
└──┬───┘    └─────┬──────┘    └──────┬──────┘    └────┬─────┘
   │              │                  │                 │
   │ get()        │                  │                 │
   │─────────────▶│                  │                 │
   │              │                  │                 │
   │              │ begin() (may wait for slot)       │
   │              │─────────────────▶│                 │
   │              │                  │                 │
   │              │ requestID        │                 │
   │              │◀─────────────────│                 │
   │              │                  │                 │
   │              │ peGetInquiry()   │                 │
   │──────────────┼─────────────────▶│                 │
   │              │                  │                 │
   │              │                  │  [SysEx bytes]  │
   │──────────────┼──────────────────┼────────────────▶│
   │              │                  │                 │
   │              │                  │  [Response]     │
   │◀─────────────┼──────────────────┼─────────────────│
   │              │                  │                 │
   │              │ parse()          │                 │
   │──────────────┼─────────────────▶│                 │
   │              │                  │                 │
   │ processChunk()                  │                 │
   │─────────────▶│                  │                 │
   │              │                  │                 │
   │ .complete    │                  │                 │
   │◀─────────────│                  │                 │
   │              │                  │                 │
   │              │ cancel() (release ID + slot)      │
   │              │─────────────────▶│ (resumes waiter)│
   │              │                  │                 │
```

## Testing Strategy

| Layer | Test Approach |
|-------|---------------|
| MIDI2Core | Unit tests for encoding/decoding |
| MIDI2CI | Unit tests for message building/parsing, CIManager lifecycle |
| MIDI2PE | Unit tests for transaction lifecycle, chunk assembly, inflight limiting |
| MIDI2Transport | MockMIDITransport for integration tests |

Mock transport enables testing without hardware:

```swift
let mock = MockMIDITransport()

// Inject simulated device responses
await mock.injectReceived(discoveryReplyBytes)

// Verify sent messages
let sent = await mock.sentMessages
XCTAssert(await mock.wasSent(ciMessageType: 0x70))
```

## Version History

- **2026-01-11**: Added MIDI 2.0 UMP support (`UMPBuilder`, `UMPParser`, `UMPTypes`, `UMPValueScaling`), `MIDITracer` for diagnostics
- **2026-01-10**: Added per-device inflight limiting, `PESubscriptionManager`, `CIManagerEvent`, fixed Source-to-Destination mapping via Entity
- **2025-01-10**: Added `unknownRequestID` to `PEChunkResult`, improved `MIDITransportError`, responsibility separation between `PETransactionManager` and `PEManager`
- **2025-01-09**: Initial release with MIDI2Core, MIDI2CI, MIDI2PE, MIDI2Transport
