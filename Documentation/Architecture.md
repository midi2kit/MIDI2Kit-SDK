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
| `MUID` | 28-bit MIDI Unique Identifier |
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

┌─────────────────────────────────────────────────────────────┐
│                     MIDI2LogUtils                            │
├─────────────────────────────────────────────────────────────┤
│  Safe Formatting (prevents log bloat & sensitive data leak) │
│                                                              │
│  hexPreview(data, limit: 32)                                │
│    → "F0 7E 7F... (32 of 128 bytes)"                        │
│                                                              │
│  transactionInfo(requestID, resource, muid)                 │
│    → "[42] DeviceInfo -> 0x12345678"                        │
│                                                              │
│  chunkProgress(received, total)                             │
│    → "3/5 chunks"                                           │
│                                                              │
│  responseSummary(status, headerSize, bodySize)              │
│    → "status=200, header=45B, body=1024B"                   │
│                                                              │
│  timeoutInfo(elapsedSeconds, receivedChunks, totalChunks)   │
│    → "timeout after 5.0s (received 2/4 chunks)"             │
│                                                              │
│  Extensions: Data.logPreview, [UInt8].logPreview            │
│                                                              │
│  Guidelines:                                                 │
│    ✅ Log: requestID, MUID, chunk progress, status, size    │
│    ❌ Avoid: Full SysEx dumps, complete bodies, raw binary  │
└─────────────────────────────────────────────────────────────┘
```

**Design Notes**:
- All types are `Sendable` for Swift 6 concurrency
- `MUID` validates 28-bit constraint (0x0000_0000 - 0x0FFF_FFFF)
- `Mcoded7` handles encoding in 7-byte groups

### MIDI2CI

**Purpose**: MIDI Capability Inquiry message building, parsing, and device management.

**Key Types**:

| Type | Description |
|------|-------------|
| `CIManager` | Central manager for CI devices and MUID lifecycle |
| `DiscoveredDevice` | Device found via Discovery |
| `CIMessageBuilder` | Builds CI SysEx messages |
| `CIMessageParser` | Parses CI SysEx messages |

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
│                                                              │
│  Key Methods:                                                │
│    generateMUID() → MUID                                    │
│    device(for: MUID) → DiscoveredDevice?                    │
│    handleDiscoveryReply(payload:) → DiscoveredDevice        │
│    handleInvalidateMUID(payload:)                           │
│    clearAllDevices()                                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

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
| `PETransactionManager` | **Critical**: Prevents Request ID leaks |
| `PEMonitorHandle` | Handle for automatic timeout monitoring |
| `PEMonitoringConfiguration` | Configuration for monitoring behavior |

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

**Monitoring System**:

```
┌─────────────────────────────────────────────────────────────┐
│                PEMonitoringConfiguration                     │
├─────────────────────────────────────────────────────────────┤
│  checkInterval: TimeInterval (default: 1.0s)                │
│  autoStart: Bool (default: false)                           │
│                                                              │
│  Presets:                                                    │
│    .default         → manual startMonitoring() required     │
│    .autoStartEnabled → monitoring starts on first begin()   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  PEMonitorHandle Pattern                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  startMonitoring()                                           │
│        │                                                     │
│        ▼                                                     │
│  ┌───────────────────────────────────────────────────┐      │
│  │ PEMonitorHandle                                    │      │
│  │   ├─ Task (background timeout checking)           │      │
│  │   ├─ MonitorRunningState (shared state)           │      │
│  │   └─ stopCallback                                 │      │
│  └───────────────────────────────────────────────────┘      │
│        │                                                     │
│        │ Task runs: while !cancelled && manager alive       │
│        │   → checkTimeouts()                                │
│        │   → sleep(checkInterval)                           │
│        │                                                     │
│        ├─── stop() called ──▶ Task cancelled, state marked  │
│        │                                                     │
│        ├─── Handle released ──▶ deinit cancels Task         │
│        │                                                     │
│        └─── Manager deallocated ──▶ weak self nil,          │
│                                      Task exits cleanly     │
│                                                              │
│  Auto-Start Mode (autoStart: true):                         │
│    • No need to call startMonitoring()                      │
│    • Monitoring starts automatically on first begin()       │
│    • Manager holds internal strong reference to handle      │
│    • Use stopMonitoring() to stop                           │
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
│                       │                                      │
│                       ▼                                      │
│              ┌─────────────────┐                            │
│              │   ACTIVE        │                            │
│              │   Transaction   │                            │
│              └────────┬────────┘                            │
│                       │                                      │
│     ┌─────────────────┼─────────────────┐                   │
│     │                 │                 │                   │
│     ▼                 ▼                 ▼                   │
│ complete()    completeWithError()   checkTimeouts()         │
│     │                 │                 │                   │
│     └─────────────────┴─────────────────┘                   │
│                       │                                      │
│                       ▼                                      │
│              ┌─────────────────┐                            │
│              │ Request ID      │ ◀── ALWAYS released        │
│              │ RELEASED        │                            │
│              └─────────────────┘                            │
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
└─────────────────────────────────────────────────────────────┘
```

## Concurrency Model

MIDI2Kit uses Swift 6 strict concurrency:

| Component | Isolation |
|-----------|-----------|
| `CIManager` | `actor` |
| `PETransactionManager` | `actor` |
| `SysExAssembler` | `actor` |
| `MockMIDITransport` | `actor` |
| Data types | `Sendable struct/enum` |
| `CoreMIDITransport` | `@unchecked Sendable` (uses internal locking) |
| `ConnectionState` | `@unchecked Sendable` (NSLock for sync access) |

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
    case packetListAddFailed(dataSize: Int, bufferSize: Int)  // MIDIPacketListAdd returned nil
    case packetListEmpty  // Unexpected empty packet list
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

Complete PE Get flow:

```
┌──────┐    ┌────────────┐    ┌─────────────┐    ┌──────────┐
│ App  │    │ MIDI2PE    │    │ MIDI2CI     │    │ Transport│
└──┬───┘    └─────┬──────┘    └──────┬──────┘    └────┬─────┘
   │              │                  │                 │
   │ begin()      │                  │                 │
   │─────────────▶│                  │                 │
   │              │                  │                 │
   │ requestID    │                  │                 │
   │◀─────────────│                  │                 │
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
   │◀─────────────│ (ID released)    │                 │
   │              │                  │                 │
```

## Testing Strategy

| Layer | Test Approach |
|-------|---------------|
| MIDI2Core | Unit tests for encoding/decoding |
| MIDI2CI | Unit tests for message building/parsing, CIManager lifecycle |
| MIDI2PE | Unit tests for transaction lifecycle, chunk assembly |
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

- **2025-01-10**: Added `unknownRequestID` to `PEChunkResult`, `autoStart` monitoring option, `MIDI2LogUtils`, improved `MIDITransportError` with explicit `packetListAddFailed`
- **2025-01-09**: Unified `CIManager` implementations (MIDI2CI + MIDI2Kit → single implementation)
