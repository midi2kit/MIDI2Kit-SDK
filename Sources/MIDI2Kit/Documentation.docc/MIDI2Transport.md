# MIDI2Transport

MIDI I/O abstraction layer.

## Overview

MIDI2Transport provides a protocol-based abstraction for MIDI input/output:

- ``MIDITransport``: Protocol defining the transport interface
- ``CoreMIDITransport``: Production implementation using Apple's CoreMIDI
- ``MockMIDITransport``: Test implementation for unit testing without hardware

## Example

```swift
// Production
let transport = try CoreMIDITransport(clientName: "MyApp")
try await transport.connectToAllSources()

// Send data
try await transport.send(data, to: destinationID)

// Receive data
for await received in transport.received {
    print("Received \(received.data.count) bytes")
}
```

## Topics

### Transport Protocol

- ``MIDITransport``

### Implementations

- ``CoreMIDITransport``
- ``MockMIDITransport``

### Endpoint Types

- ``MIDISourceID``
- ``MIDIDestinationID``
- ``MIDISourceInfo``
- ``MIDIDestinationInfo``
- ``MIDIReceivedData``

### Errors

- ``MIDITransportError``
