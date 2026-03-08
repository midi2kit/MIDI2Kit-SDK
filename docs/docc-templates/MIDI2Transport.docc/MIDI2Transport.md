# ``MIDI2Transport``

CoreMIDI abstraction with connection state management and SysEx assembly.

@Metadata {
    @DisplayName("MIDI2Transport")
}

## Overview

MIDI2Transport provides a protocol-based abstraction over CoreMIDI, enabling
testable MIDI communication with proper connection lifecycle management.

### Transport Protocol

``MIDITransport`` defines the interface for sending and receiving MIDI data.
Multiple implementations are provided:

- ``CoreMIDITransport``: Production implementation using CoreMIDI APIs
- ``MockMIDITransport``: Test implementation for unit testing without hardware
- ``LoopbackTransport``: Loopback transport for integration testing

### Connection Management

``CoreMIDITransport`` tracks connected sources using thread-safe state
to prevent duplicate connections and missed disconnects:

```
connectToAllSources():
  1. Get current sources from CoreMIDI
  2. Disconnect removed (Set difference)
  3. Connect new only (Set difference)
  -> No duplicates, no missed disconnects
```

### Thread Safety

``CoreMIDITransport`` is `@unchecked Sendable` and protects CoreMIDI
client/ports with `shutdownLock`. The `send()` method holds this lock to
prevent concurrent `shutdownSync()` from disposing the output port mid-send.

### SysEx Assembly

``SysExAssembler`` is an `actor` that reassembles fragmented SysEx messages
from CoreMIDI packet streams. All packets are collected first and processed
sequentially in a single Task to guarantee ordering and prevent corruption.

### Packet Order Guarantee

CoreMIDI callbacks may deliver packets out of order across concurrent calls.
``CoreMIDITransport`` collects all packets first, then processes them
sequentially in a single Task to prevent SysEx corruption from race conditions.

## Topics

### Transport Protocol

- ``MIDITransport``
- ``MIDITransportError``
- ``MIDITransportType``

### Implementations

- ``CoreMIDITransport``
- ``MockMIDITransport``
- ``LoopbackTransport``

### Endpoint Types

- ``MIDISourceID``
- ``MIDIDestinationID``
- ``MIDISourceInfo``
- ``MIDIDestinationInfo``
- ``MIDIReceivedData``

### Connection Management

- ``ConnectionPolicy``
- ``CIRoutingPolicy``

### SysEx

- ``SysExAssembler``

### Virtual Endpoints

- ``VirtualEndpointCapable``
- ``VirtualDevice``

### Utilities

- ``SyncBroadcastHub``
