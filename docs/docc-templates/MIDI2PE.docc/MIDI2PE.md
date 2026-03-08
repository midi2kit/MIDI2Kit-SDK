# ``MIDI2PE``

Property Exchange: transaction management, chunk assembly, and subscriptions.

@Metadata {
    @DisplayName("MIDI2PE")
}

## Overview

MIDI2PE implements the MIDI-CI Property Exchange protocol, which allows reading
and writing structured data (typically JSON) on MIDI 2.0 devices via SysEx.

The module is organized into three layers of responsibility:

| Component | Responsibility |
|-----------|---------------|
| ``PETransactionManager`` | Request ID allocation, chunk assembly, per-device inflight limiting |
| ``PEManager`` | Timeout scheduling, continuation management, high-level GET/SET API |
| ``PESubscriptionManager`` | Auto-reconnecting subscription management |

### Request ID Management

PE uses 7-bit Request IDs (0-127). ``PETransactionManager`` ensures proper
lifecycle management to prevent ID exhaustion:

1. `begin()` allocates an ID (waits if device is at capacity)
2. Chunks are processed and assembled
3. `cancel()` releases the ID and slot, resuming the next waiter

### Per-Device Inflight Limiting

Some devices cannot handle many concurrent PE requests. The `maxInflightPerDevice`
setting (default: 2) limits concurrent requests per device while allowing
different devices to operate in parallel.

### Chunk Assembly

Large PE responses are split into multiple chunks. ``PEChunkAssembler`` tracks
received chunks and signals completion:

```swift
public enum PEChunkResult {
    case incomplete(received: Int, total: Int)
    case complete(header: Data, body: Data)
    case timeout(requestID: UInt8, received: Int, total: Int, partial: Data?)
    case unknownRequestID(requestID: UInt8)
}
```

### Subscription Auto-Reconnection

``PESubscriptionManager`` tracks subscription intent by device identity
(not just MUID). When a device disconnects and reconnects with a new MUID,
the manager automatically re-subscribes.

## Topics

### High-Level API

- ``PEManager``
- ``PEManagerSession``
- ``PEDeviceHandle``
- ``PEError``

### Requests and Responses

- ``PERequest``
- ``PEResponse``
- ``PEHeader``
- ``PEStatusCode``
- ``PEStatus``
- ``PEOperation``

### Transaction Management

- ``PETransactionManager``
- ``PETransaction``
- ``PERequestIDManager``
- ``PEChunkAssembler``
- ``PEChunkResult``
- ``PESendStrategy``

### Subscriptions

- ``PESubscriptionManager``
- ``PESubscriptionIntent``
- ``PESubscriptionEvent``
- ``PESubscription``
- ``PESubscribeResponse``
- ``PENotification``
- ``PENotifyAssemblyManager``

### Resource Types

- ``PEResource``
- ``PEResourceEntry``
- ``PEDeviceInfo``
- ``PEControllerDef``
- ``PEProgramDef``
- ``PEChannelInfo``

### Batch Operations

- ``PEBatchResult``
- ``PEBatchResponse``
- ``PEBatchOptions``
- ``PESetItem``
- ``PEBatchSetOptions``
- ``PEBatchSetResponse``

### Responder API

- ``PEResponder``
- ``PEResponderResource``
- ``PEResponderError``
- ``PERequestHeader``
- ``ComputedResource``
- ``StaticResource``
- ``InMemoryResource``
- ``ListResource``

### Validation

- ``PESchemaValidator``
- ``PESchemaValidationResult``
- ``PEPayloadValidator``
- ``PEPayloadValidatorRegistry``

### Conditional Operations

- ``PEConditionalSet``
- ``PEConditionalResult``
- ``PEPipeline``

### Error Types

- ``PENAKDetails``
- ``NAKStatusCode``
- ``NAKDetailCode``
- ``PERequestError``

### Vendor Extensions

- ``MIDIVendor``
- ``VendorOptimization``
- ``VendorOptimizationConfig``
- ``PEResourceFallbackPath``
