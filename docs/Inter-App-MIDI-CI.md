# Inter-App MIDI-CI Communication on iOS

This document describes the technical limitations and alternatives for MIDI-CI (Capability Inquiry) and Property Exchange communication between apps on a single iOS device.

## Summary

**MIDI-CI communication between apps on the same iOS device is not possible with third-party apps like KORG Module Pro.**

This is due to how these apps implement MIDI-CI - they only process MIDI-CI messages received via BLE MIDI, not via CoreMIDI Virtual Ports.

---

## Technical Background

### iOS Inter-App MIDI Architecture

```
┌─────────────────────────────────────────────────────┐
│                    iOS Device                        │
│                                                      │
│  ┌──────────────┐          ┌──────────────────┐    │
│  │   App A      │          │      App B       │    │
│  │ (MIDI2Kit)   │          │  (KORG Module)   │    │
│  └──────┬───────┘          └────────┬─────────┘    │
│         │                           │              │
│         │    CoreMIDI Virtual Ports │              │
│         └───────────┬───────────────┘              │
│                     │                              │
│              ┌──────┴──────┐                       │
│              │   CoreMIDI   │                       │
│              └─────────────┘                       │
└─────────────────────────────────────────────────────┘
```

### What Works

- **MIDI 1.0 messages** (Note On/Off, CC, Program Change, etc.) can be exchanged between apps via Virtual Ports
- **SysEx messages** can technically be sent via Virtual Ports
- Apps like AUM can host Audio Units and route MIDI between them

### What Doesn't Work

- **MIDI-CI Discovery** - Third-party apps don't respond to Discovery Inquiry via Virtual Ports
- **Property Exchange** - Requires successful MIDI-CI discovery first

---

## Experiment Results (2026-02-05)

### Test Setup

- Device: iPhone with iOS 18
- Apps: SimpleMidiController (MIDI2Kit) + KORG Module Pro
- Method: Send MIDI-CI Discovery Inquiry via CoreMIDI Virtual Port

### Results

| Item | Result |
|------|--------|
| KORG Module Virtual Port visible | Yes (ID: 3547336) |
| Discovery Inquiry sent | Success |
| MIDI-CI response received | **No** |
| Wait time | 15 seconds |

### Conclusion

KORG Module Pro's MIDI-CI implementation is **tied to the BLE MIDI interface layer**. It does not process MIDI-CI SysEx messages received via Virtual Ports.

---

## Why This Limitation Exists

### KORG's Implementation Choice

KORG Module Pro implements MIDI-CI specifically for BLE MIDI connections. This is likely because:

1. **Use case focus**: BLE MIDI is the primary way to connect external controllers
2. **Resource optimization**: No need to run MIDI-CI responder for all MIDI sources
3. **Security/isolation**: Only respond to physical device connections

### CoreMIDI Limitations

- CoreMIDI Virtual Ports are designed for basic MIDI message routing
- There's no standard mechanism for MIDI-CI device discovery via Virtual Ports
- Each app would need to explicitly implement MIDI-CI response for Virtual Ports

---

## Available Alternatives

### Option 1: Two-Device Setup (Recommended for KORG Module)

```
┌──────────────┐     BLE MIDI     ┌──────────────┐
│   Device 1   │ ←───────────────→│   Device 2   │
│  MIDI2Kit    │                  │ KORG Module  │
│    App       │                  │    Pro       │
└──────────────┘                  └──────────────┘
```

**Pros:**
- Works with actual KORG Module Pro
- Real-world testing scenario
- Full MIDI-CI/PE functionality

**Cons:**
- Requires two iOS devices
- BLE MIDI latency

### Option 2: MIDI2Kit Apps (Same Device)

```
┌─────────────────────────────────────────────────────┐
│                    iOS Device                        │
│                                                      │
│  ┌──────────────┐   Virtual   ┌──────────────────┐ │
│  │   App A      │    Port     │      App B       │ │
│  │  (MIDI2Kit   │ ←─────────→ │   (MIDI2Kit      │ │
│  │   Initiator) │             │    Responder)    │ │
│  └──────────────┘             └──────────────────┘ │
└─────────────────────────────────────────────────────┘
```

If both apps use MIDI2Kit and implement MIDI-CI Responder functionality, they can communicate via Virtual Ports.

**Implementation:**
- App A: Uses `CIManager` + `PEManager` as Initiator
- App B: Uses `PEResponder` + Virtual Port to respond

**Pros:**
- Single device
- Full control over both ends
- Useful for testing and development

**Cons:**
- Requires implementing both apps yourself
- Cannot communicate with third-party apps

### Option 3: MockDevice (Development/Testing)

```swift
// In-process loopback for testing
let (initiator, responder) = await LoopbackTransport.createPair()
let mockDevice = MockDevice(preset: .korgModulePro, transport: responder)
await mockDevice.start()

let ciManager = CIManager(transport: initiator, muid: .random())
// Discovery will find the MockDevice
```

**Pros:**
- No external devices needed
- Fast iteration during development
- Predictable behavior for unit tests

**Cons:**
- Not real device communication
- Only useful for development/testing

---

## Recommendations

### For Development & Testing

Use **MockDevice** with KORG Module Pro preset:

```swift
import MIDI2Kit

let (initiator, responder) = await LoopbackTransport.createPair()
let mockDevice = MockDevice(preset: .korgModulePro, transport: responder)
await mockDevice.start()

// Your MIDI2Client code here...
```

### For Real KORG Module Communication

Use **two-device setup** with BLE MIDI:

1. Device A: Run your MIDI2Kit app
2. Device B: Run KORG Module Pro
3. Pair via BLE MIDI
4. Use `.korgBLEMIDI` configuration preset

```swift
let config = MIDI2ClientConfiguration.korgBLEMIDI
let client = try await MIDI2Client(configuration: config)
```

### For Custom App-to-App Communication

Implement **PEResponder** in your second app and expose a Virtual Port. This requires:

1. Creating a Virtual MIDI Source in the responder app
2. Implementing MIDI-CI message handling
3. Using `PEResponder` to handle Property Exchange

---

## Related Documentation

- [MIDI2Kit README](../README.md) - Library overview
- [API Reference](API_Reference.md) - Full API documentation
- [KORG BLE MIDI Guide](KORG-BLE-MIDI.md) - KORG-specific configuration

---

## Version History

| Date | Description |
|------|-------------|
| 2026-02-05 | Initial investigation and documentation |
