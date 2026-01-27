# MIDI2Kit Known Issues & Status

## Overview

This document tracks known issues, their status, and workarounds for MIDI2Kit.

*Last updated: 2026-01-27*

---

## Critical Issues

### 1. BLE MIDI Multi-Chunk Packet Loss

**Status:** 🔴 Unresolved (Physical Layer Limitation)

**Description:**
When communicating with KORG Module Pro over BLE MIDI, multi-chunk PE responses (like ResourceList) frequently fail due to chunk 2/3 being lost in transit.

**Affected Operations:**
- ResourceList retrieval (~90% failure rate)
- Any PE response requiring 3+ chunks

**Root Cause:**
BLE MIDI physical layer reliability issues, not a software bug.

**Workarounds:**
1. Use USB connection instead of BLE
2. Retry multiple times (may eventually succeed)
3. Use single-chunk operations (DeviceInfo works reliably)

**See:** [BLE-MIDI-PacketLoss-Analysis.md](technical/BLE-MIDI-PacketLoss-Analysis.md)

---

## Resolved Issues

### 2. CI11 Parser Misidentification ✅

**Status:** 🟢 Resolved (2026-01-27)

**Description:**
CI11 parser incorrectly identified chunk 2/3 (with headerSize=0) as a single-chunk CI11 response.

**Fix:**
```swift
// CIMessageParser.parsePEReplyCI11()
guard headerSize > 0 else { return nil }
```

**Commit:** (pending)

---

### 3. KORG Destination Routing ✅

**Status:** 🟢 Resolved (2026-01-27)

**Description:**
KORG devices respond via Bluetooth port even when requests are sent to Module port.

**Fix:**
Implemented broadcast send for PE requests.

**See:** [KORG-PE-Communication-Debug-Report.md](technical/KORG-PE-Communication-Debug-Report.md)

---

### 4. AsyncStream Single-Consumer Conflict ✅

**Status:** 🟢 Resolved via ReceiveHub

**Description:**
Swift's AsyncStream only supports single consumer, causing conflicts between CIManager and PEManager.

**Fix:**
Implemented ReceiveHub for multicast event distribution.

---

## Known Limitations

### 1. KORG-Specific PE Format

**Status:** ⚠️ Workaround Implemented

**Description:**
KORG uses non-standard PE Reply format with header before chunk fields.

**Workaround:**
CIMessageParser implements KORG-specific parsing (parsePEReplyKORG).

---

### 2. BLE MIDI Reliability

**Status:** ⚠️ Physical Limitation

**Description:**
BLE MIDI has inherent reliability issues due to:
- MTU limitations
- No guaranteed delivery at MIDI level
- Packet fragmentation

**Recommendation:**
Use USB/wired connection for reliable multi-chunk operations.

---

## Compatibility Matrix

| Device | Discovery | DeviceInfo | ResourceList | Notes |
|--------|-----------|------------|--------------|-------|
| KORG Module Pro (BLE) | ✅ | ✅ | ⚠️ | Packet loss issues |
| KORG Module Pro (USB) | ❓ | ❓ | ❓ | Not tested |

---

## Implementation Status

### High-Level API

| Component | Status | Notes |
|-----------|--------|-------|
| MIDI2Client | ✅ | Core client implementation |
| MIDI2Device | ✅ | Device model |
| DestinationResolver | ✅ | KORG-aware routing |
| ReceiveHub | ✅ | Multicast event distribution |
| RobustJSONDecoder | ✅ | Non-standard JSON handling |

### Low-Level Components

| Component | Status | Notes |
|-----------|--------|-------|
| CIMessageParser | ✅ | CI11/CI12/KORG formats |
| PEChunkAssembler | ✅ | Multi-chunk assembly |
| PEManager | ✅ | Transaction management |
| CoreMIDITransport | ✅ | Broadcast support |

---

## Test Results Summary (2026-01-27)

### Auto-fetch at Startup
- DeviceInfo: ✅ Success
- ResourceList: ⚠️ Succeeded on 5th retry

### Manual GET Operations
- DeviceInfo: ✅ Always succeeds
- ResourceList: ❌ Failed after 5 retries (BLE packet loss)

---

## Next Steps

1. **USB Testing:** Verify reliability with wired connection
2. **Retry Enhancement:** Consider more aggressive retry strategy
3. **Documentation:** User-facing docs about BLE limitations
4. **Other Devices:** Test with non-KORG MIDI 2.0 devices

---

## References

- [ClaudeWorklog20260127.md](ClaudeWorklog20260127.md) - Development log
- [KORG-PE-Compatibility.md](KORG-PE-Compatibility.md) - KORG-specific notes
- [PE_Stability_Roadmap.md](PE_Stability_Roadmap.md) - Improvement roadmap
