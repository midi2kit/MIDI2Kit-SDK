# UMP Conversion Guide

Convert between MIDI 1.0 SysEx and UMP (Universal MIDI Packet) formats.

## Overview

MIDI2Core provides bidirectional conversion between traditional MIDI 1.0 SysEx messages
and MIDI 2.0 UMP Data 64 packets. This is essential for bridging MIDI 1.0 and 2.0 ecosystems.

## MIDI 1.0 SysEx to UMP Data 64

Convert a MIDI 1.0 SysEx byte sequence into one or more UMP Data 64 packets:

```swift
import MIDI2Core

let sysex: [UInt8] = [0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]
let packets = UMPTranslator.fromMIDI1SysEx(sysex)
```

The translator automatically chunks payloads into 6-byte segments, setting the
appropriate status (start, continue, end, or complete) for each packet.

### Factory API

Use the convenience factory for creating UMP packets directly:

```swift
// Single complete packet
let packet = UMP.sysEx7.complete(payload: [0x7E, 0x7F, 0x09, 0x01])

// From MIDI 1.0 SysEx (auto-chunked)
let packets = UMP.sysEx7.fromMIDI1(bytes: sysex)
```

## UMP Data 64 to MIDI 1.0 SysEx

Convert a UMP Data 64 packet back to MIDI 1.0 SysEx bytes:

```swift
let ump: UMPMessage = // ... received UMP packet
if let sysexBytes = UMPTranslator.data64ToMIDI1SysEx(ump) {
    // Includes 0xF0 start and 0xF7 end bytes
    print("SysEx: \(sysexBytes)")
}
```

## Multi-Packet Reassembly

For SysEx messages spanning multiple UMP packets, use ``UMPSysEx7Assembler``:

```swift
let assembler = UMPSysEx7Assembler()

for packet in receivedPackets {
    if let completeSysEx = await assembler.process(packet) {
        // Complete SysEx message reassembled
        print("Complete: \(completeSysEx)")
    }
}
```

The assembler is actor-based for thread safety and supports timeout detection
for incomplete messages:

```swift
if let timedOut = await assembler.popTimedOut() {
    print("Partial SysEx timed out")
}
```

## RPN/NRPN to MIDI 1.0 CC

Convert UMP RPN/NRPN messages to MIDI 1.0 Control Change approximations:

```swift
// RPN → CC sequence [CC#101, CC#100, CC#6, CC#38]
let ccMessages = UMPTranslator.rpnToMIDI1ControlChange(rpnMessage)

// NRPN → CC sequence [CC#99, CC#98, CC#6, CC#38]
let ccMessages = UMPTranslator.nrpnToMIDI1ControlChange(nrpnMessage)
```

> Note: RPN/NRPN conversion is an approximation. UMP uses 32-bit resolution
> while MIDI 1.0 uses 7-bit + 7-bit (14-bit total). The conversion preserves
> the 14-bit MSB value for compatibility.

## Value Scaling

Use ``UMPValueScaling`` for resolution conversion between MIDI 1.0 and 2.0:

| Conversion | Method |
|-----------|--------|
| 7-bit ↔ 32-bit | `scale7to32` / `scale32to7` |
| 14-bit ↔ 32-bit | `scale14to32` / `scale32to14` |
| 7-bit ↔ 16-bit (velocity) | `scale7to16` / `scale16to7` |
| Normalized (0.0-1.0) ↔ 32-bit | `normalizedTo32` / `scale32toNormalized` |
