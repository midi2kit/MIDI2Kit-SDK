# ``MIDI2CI``

MIDI Capability Inquiry: device discovery, message building, and parsing.

@Metadata {
    @DisplayName("MIDI2CI")
}

## Overview

MIDI2CI implements the MIDI Capability Inquiry protocol, which enables automatic
discovery and capability negotiation between MIDI 2.0 devices.

The central type is ``CIManager``, an `actor` that manages MUID lifecycle,
tracks discovered devices, and emits events through `AsyncStream`.

### Discovery Flow

```
App -> CIManager -> [F0 7E 7F 0D 70...] -> Device
App <- CIManager <- [F0 7E 7F 0D 71...] <- Device
```

1. ``CIManager`` broadcasts a Discovery Inquiry (sub-ID 0x70) to all endpoints
2. Devices respond with Discovery Reply (sub-ID 0x71) containing their capabilities
3. ``CIManager`` creates a ``DiscoveredDevice`` and emits a `.deviceDiscovered` event
4. Periodic re-discovery detects new devices and lost connections

### Source-to-Destination Mapping

CoreMIDI uses separate endpoints for input (Source) and output (Destination).
``CIManager`` resolves the correct Destination for a device by traversing the
Entity hierarchy:

```
Physical Device
  +-- Entity (MIDIEntityRef)
       +-- Source      <- CI replies come FROM here
       +-- Destination <- CI requests go TO here
```

## Topics

### Device Management

- ``CIManager``
- ``CIManagerConfiguration``
- ``CIManagerEvent``
- ``DiscoveredDevice``

### Message Protocol

- ``CIMessageBuilder``
- ``CIMessageParser``

### Process Inquiry

- ``ProcessInquiryMessageType``
- ``ProcessInquiryCapabilities``
- ``ProcessInquiryCapabilitiesReply``
- ``MIDIMessageTypeFlags``
- ``MIDIMessageReportRequest``
- ``MIDIMessageReport``

### Supporting Types

- ``CIRole``
