# MIDI2PE

Property Exchange for reading and writing device properties.

## Overview

MIDI2PE provides a high-level async/await API for MIDI 2.0 Property Exchange operations:

- GET: Read property values
- SET: Write property values  
- Subscribe: Receive change notifications

The main entry point is ``PEManager``.

## Example

```swift
let peManager = PEManager(transport: transport, sourceMUID: ciManager.muid)
peManager.destinationResolver = ciManager.makeDestinationResolver()
await peManager.startReceiving()

// Get device info
let deviceInfo = try await peManager.getDeviceInfo(from: device.muid)

// Subscribe to changes
let response = try await peManager.subscribe(to: "CurrentProgram", on: device.muid)
for await notification in peManager.startNotificationStream() {
    print("Changed: \(notification.resource)")
}
```

## Topics

### Property Exchange Manager

- ``PEManager``
- ``PEDeviceHandle``

### Requests and Responses

- ``PERequest``
- ``PEResponse``
- ``PEHeader``

### Standard Resources

- ``PEDeviceInfo``
- ``PEResourceEntry``

### Subscriptions

- ``PENotification``
- ``PESubscription``

### Errors

- ``PEError``
- ``PENAKDetails``
