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
│ • Consts  │ │ • Device  │ │ • Trans-  │ │ • SysEx         │
│           │ │   Info    │ │   action  │ │   Assembly      │
└───────────┘ └───────────┘ │   Manager │ └─────────────────┘
                            └───────────┘
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

**Design Notes**:
- All types are `Sendable` for Swift 6 concurrency
- `MUID` validates 28-bit constraint (0x0000_0000 - 0x0FFF_FFFF)
- `Mcoded7` handles encoding in 7-byte groups

### MIDI2CI

**Purpose**: MIDI Capability Inquiry message building and parsing.

**Key Types**:

| Type | Description |
|------|-------------|
| `DiscoveredDevice` | Device found via Discovery |
| `CIMessageBuilder` | Builds CI SysEx messages |
| `CIMessageParser` | Parses CI SysEx messages |

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
| `PERequestIDManager` | Manages 7-bit Request IDs (0-127) |
| `PETransactionManager` | **Critical**: Prevents Request ID leaks |

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
| `ConnectionState` | Actor managing connected sources |

**Connection Management**:

```
┌─────────────────────────────────────────────────────────────┐
│                   CoreMIDITransport                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────┐               │
│  │         ConnectionState (actor)           │               │
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
| `PETransactionManager` | `actor` |
| `ConnectionState` | `private actor` |
| `SysExAssembler` | `actor` |
| `MockMIDITransport` | `actor` |
| Data types | `Sendable struct/enum` |
| `CoreMIDITransport` | `@unchecked Sendable` (uses internal actor) |

## Error Handling

```swift
public enum MIDITransportError: Error {
    case clientCreationFailed(Int32)
    case portCreationFailed(Int32)
    case sendFailed(Int32)
    case connectionFailed(Int32)
    case destinationNotFound(UInt32)
    case sourceNotFound(UInt32)
}

public enum PETransactionResult {
    case success(header: Data, body: Data)
    case error(status: Int, message: String?)
    case timeout
    case cancelled
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
| MIDI2CI | Unit tests for message building/parsing |
| MIDI2PE | Unit tests for transaction lifecycle |
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
