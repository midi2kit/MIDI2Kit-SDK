# KORG Module Pro - Known Limitations

## Overview

KORG Module Pro is an iOS synthesizer app that supports MIDI 2.0 / MIDI-CI including Property Exchange (PE). This document describes known limitations when using MIDI2Kit with KORG Module Pro.

## Test Environment

- Device: iPhone (iOS)
- KORG Module Pro version: Latest as of January 2026
- Connection: CoreMIDI virtual port ("Module")

## Working Features

### ✅ Discovery
- MIDI-CI Discovery works reliably
- Device is discovered with correct identity (KORG, 374:4)
- PE capability is correctly reported

### ✅ DeviceInfo (Single-Chunk Response)
- DeviceInfo retrieval works reliably
- Response format: KORG-specific (non-standard PE format)
- Product name "Module Pro" is correctly retrieved

## Limitations

### ❌ ResourceList (Multi-Chunk Response)

**Problem**: ResourceList requests result in random packet loss, causing timeouts.

**Symptoms**:
- ResourceList response consists of 3 chunks
- Random chunks are lost during transmission
- Different chunks are lost on each retry attempt
- Pattern is unpredictable (sometimes chunk 1 missing, sometimes chunk 2, etc.)

**Example from testing**:
```
reqID=3: chunk 1, 2 received → chunk 3 lost
reqID=4: chunk 1, 3 received → chunk 2 lost
reqID=5: chunk 1, 3 received → chunk 2 lost
reqID=6: chunk 2, 3 received → chunk 1 lost
```

**Root Cause**: 
- Likely a CoreMIDI virtual port buffering issue
- KORG Module Pro runs as a separate iOS app, communicating via virtual MIDI ports
- High-speed multi-chunk responses may overwhelm the inter-app MIDI buffer

### KORG-Specific PE Format

KORG Module Pro uses a non-standard PE Reply format that differs from MIDI-CI 1.2 specification:

**Standard CI 1.2 Format**:
```
requestID(1) + headerSize(2) + numChunks(2) + thisChunk(2) + dataSize(2) + headerData + propertyData
```

**KORG Format (Chunk 1)**:
```
requestID(1) + headerSize(2) + headerData + numChunks(2) + thisChunk(2) + dataSize(2) + propertyData
```
Note: Chunk fields come AFTER headerData, unlike standard format.

**KORG Format (Chunk 2, 3, ...)**:
Standard CI 1.2 format with headerSize=0.

## Workarounds

### Warm-up Strategy

Fetching DeviceInfo before ResourceList can improve reliability:
- DeviceInfo is single-chunk and stable
- May help "wake up" the CoreMIDI connection

Implementation in MIDI2Client:
```swift
// Warm-up: fetch DeviceInfo first
_ = try await peManager.getDeviceInfo(from: handle)
// Then fetch ResourceList
return try await peManager.getResourceList(from: handle)
```

### Destination Resolution

KORG Module Pro exposes multiple MIDI destinations:
- **Module** - Main virtual port (recommended)
- **Session 1** - Alternative (may work when Module unavailable)
- **Bluetooth** - BLE MIDI (not recommended for PE)

MIDI2Kit's DestinationResolver automatically selects "Module" when available.

## Recommendations

1. **Use DeviceInfo** - Single-chunk responses are reliable
2. **Avoid ResourceList** - Multi-chunk responses have reliability issues
3. **Direct Resource Access** - If you know the resource name, access it directly instead of using ResourceList
4. **Retry with patience** - Multiple retries may eventually succeed

## Future Improvements

Potential solutions to investigate:
1. Inter-chunk delay to reduce buffer overflow
2. Request chunk-by-chunk with ACK
3. Report issue to KORG for firmware/app fix

## Version History

- 2026-01-28: Initial documentation based on Phase 1-1 testing
