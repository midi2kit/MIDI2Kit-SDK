# Basic Concepts

Understand the fundamental concepts of MIDI 2.0 and how MIDI2Kit implements them.

## Overview

MIDI 2.0 introduces several new concepts beyond traditional MIDI 1.0. This guide explains the key concepts you need to understand when working with MIDI2Kit.

## Universal MIDI Packet (UMP)

UMP is the new transport format for MIDI 2.0. Unlike MIDI 1.0's byte streams, UMP uses fixed-size packets (32, 64, or 128 bits) that include group information.

```swift
// UMP message types
enum UMPMessageType: UInt8 {
    case utility           = 0x0  // 32-bit
    case system            = 0x1  // 32-bit  
    case midi1ChannelVoice = 0x2  // 32-bit
    case data64            = 0x3  // 64-bit (SysEx7)
    case midi2ChannelVoice = 0x4  // 64-bit
    case data128           = 0x5  // 128-bit (SysEx8)
    case flexData          = 0xD  // 128-bit
    case umpStream         = 0xF  // 128-bit
}
```

## MUID (MIDI Unique Identifier)

Every MIDI-CI device has a 28-bit MUID that uniquely identifies it during a session:

```swift
let muid = MUID.random()        // Generate random MUID
let broadcast = MUID.broadcast  // 0x0FFFFFFF for broadcasts
```

> Important: MUIDs are session-scoped. They change when a device restarts.

## MIDI-CI (Capability Inquiry)

MIDI-CI allows devices to discover each other and negotiate capabilities:

- **Discovery**: Find devices on the MIDI bus
- **Protocol Negotiation**: Agree on MIDI 1.0 or 2.0
- **Profile Configuration**: Enable/disable device profiles
- **Property Exchange**: Read/write device properties

## Property Exchange (PE)

PE allows structured data exchange between devices using JSON:

```swift
// Get device information
let deviceInfo = try await peManager.getDeviceInfo(from: device.muid)
print("Product: \(deviceInfo.productName ?? "Unknown")")

// Get available resources
let resources = try await peManager.getResourceList(from: device.muid)
```

## Device Identity

Devices identify themselves with manufacturer, family, model, and version:

```swift
let identity = DeviceIdentity(
    manufacturerID: .standard(0x41),  // Roland
    familyID: 0x0001,
    modelID: 0x0015,
    versionID: 0x01500000
)
```

## Value Scaling

MIDI 2.0 uses 32-bit values instead of 7-bit. MIDI2Kit provides conversion utilities:

```swift
// Convert MIDI 1.0 velocity to MIDI 2.0
let velocity7: UInt8 = 100
let velocity32 = UMPValueScaling.scale7To32(velocity7)

// Normalized value (0.0-1.0) to 32-bit
let value32 = UMPValueScaling.normalizedTo32(0.75)
```

## See Also

- <doc:GettingStarted>
- ``MUID``
- ``DeviceIdentity``
- ``UMPMessageType``
