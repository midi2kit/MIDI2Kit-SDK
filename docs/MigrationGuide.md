# MIDI2Kit Migration Guide

This guide helps you migrate from the low-level APIs (CIManager, PEManager) to the recommended high-level MIDI2Client API.

## Why Migrate?

The MIDI2Client API provides:
- Simplified initialization and lifecycle management
- Automatic destination resolution with fallback
- Built-in caching for device info and resource lists
- Type-safe property access
- Better error handling and diagnostics

## Migration Steps

### 1. Client Initialization

**Before** (CIManager + PEManager):
```swift
let transport = CoreMIDITransport()
let ciManager = CIManager(
    name: "MyApp",
    transport: transport
)
let peManager = PEManager(ciManager: ciManager)

await ciManager.start()
await peManager.startReceiving()
await ciManager.startDiscovery()
```

**After** (MIDI2Client):
```swift
let client = MIDI2Client(name: "MyApp")
try await client.start()
// Discovery starts automatically
```

### 2. Event Handling

**Before** (CIManager.events):
```swift
for await event in ciManager.events {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.displayName)")
    case .deviceLost(let muid):
        print("Lost: \(muid)")
    // ...
    }
}
```

**After** (MIDI2Client.makeEventStream):
```swift
for await event in client.makeEventStream() {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.displayName)")
        // device is MIDI2Device, not DiscoveredDevice
    case .deviceLost(let muid):
        print("Lost: \(muid)")
    // ...
    }
}
```

### 3. Getting Device Info

**Before** (Manual destination resolution):
```swift
guard let destination = await ciManager.destination(for: muid) else {
    throw MyError.noDestination
}
let handle = PEDeviceHandle(muid: muid, destination: destination)
let info = try await peManager.getDeviceInfo(from: handle)
```

**After** (Automatic resolution with fallback):
```swift
let info = try await client.getDeviceInfo(from: muid)
// Automatically resolves destination and retries on timeout
```

### 4. Getting Resource List

**Before** (Manual retry logic):
```swift
let handle = PEDeviceHandle(muid: muid, destination: destination)
var result: [PEResourceEntry]?
for attempt in 0...maxRetries {
    do {
        result = try await peManager.getResourceList(from: handle)
        break
    } catch {
        if attempt == maxRetries { throw error }
        try? await Task.sleep(for: .seconds(1))
    }
}
```

**After** (Built-in retry and fallback):
```swift
let resources = try await client.getResourceList(from: muid)
// Includes warm-up, destination fallback, and better error messages
```

### 5. Using MIDI2Device

**Before** (Working with DiscoveredDevice):
```swift
case .deviceDiscovered(let discovered):
    if discovered.categorySupport.contains(.propertyExchange) {
        // Manually resolve destination and call PE methods
        guard let dest = await ciManager.destination(for: discovered.muid) else { return }
        let handle = PEDeviceHandle(muid: discovered.muid, destination: dest)
        let info = try await peManager.getDeviceInfo(from: handle)
    }
```

**After** (Using MIDI2Device actor):
```swift
case .deviceDiscovered(let device):
    if device.supportsPropertyExchange {
        // Direct property access with caching
        if let info = try await device.deviceInfo {
            print("Product: \(info.productName ?? "Unknown")")
        }

        // Type-safe property access
        struct CustomProp: Codable {
            let value: String
        }
        if let prop = try await device.getProperty("X-Custom", as: CustomProp.self) {
            print("Custom: \(prop.value)")
        }
    }
```

### 6. Cleanup

**Before** (Manual cleanup):
```swift
await peManager.stopReceiving()
await ciManager.stop()
await ciManager.stopDiscovery()
```

**After** (Single stop call):
```swift
await client.stop()
// Automatically stops all subsystems
```

## Configuration Options

MIDI2Client supports flexible configuration:

```swift
// Preset configurations
let client = MIDI2Client(name: "MyApp", preset: .korgBLEMIDI)

// Custom configuration
var config = MIDI2ClientConfiguration()
config.destinationStrategy = .preferModule
config.warmUpBeforeResourceList = true
config.peTimeout = .seconds(10)
let client = MIDI2Client(name: "MyApp", configuration: config)
```

## Deprecated APIs

The following APIs are deprecated and will be removed in a future version:

### CIManager
- `start()`, `stop()` → Use `MIDI2Client.start()`, `MIDI2Client.stop()`
- `startDiscovery()`, `stopDiscovery()` → Use `MIDI2Client` (automatic)
- `events` → Use `MIDI2Client.makeEventStream()`
- `destination(for:)` → Use `MIDI2Client` (automatic resolution)
- `makeDestinationResolver()` → Use `MIDI2Client` (integrated)

### PEManager
- `startReceiving()`, `stopReceiving()` → Use `MIDI2Client.start()`, `stop()`
- `destinationResolver` → Use `MIDI2Client` (integrated)
- `get(_:from:PEDeviceHandle)`, `set(_:to:PEDeviceHandle)` → Use `MIDI2Client.get()`, `set()`

## Benefits Summary

| Feature | Low-Level API | MIDI2Client |
|---------|---------------|-------------|
| Initialization | Manual setup of multiple managers | Single client initialization |
| Destination Resolution | Manual with `destination(for:)` | Automatic with fallback |
| Error Handling | Manual retry logic | Built-in retry and fallback |
| Caching | Manual implementation | Built-in device info/resource list cache |
| Type Safety | Raw Data handling | Generic `getProperty<T>` |
| Diagnostics | Limited | `lastDestinationDiagnostics` |
| Discovery | Manual start/stop | Automatic lifecycle |

## Need Help?

- Check the [MIDI2Client Guide](MIDI2ClientGuide.md) for detailed usage examples
- See [API Reference](API_Reference.md) for complete API documentation
- Report issues at https://github.com/hakaru/MIDI2Kit/issues
