# MIDI2Kit API Reference

Complete API reference for MIDI2Kit. Covers major classes, structures, and methods.

---

## Table of Contents

- [MIDI2Client](#midi2client) - Main API
- [MIDI2ClientConfiguration](#midi2clientconfiguration) - Configuration
- [MIDI2Device](#midi2device) - Device Representation
- [KORG Extension API](#korg-extension-api) - KORG optimization features (v1.0.8+)
- [WarmUpStrategy](#warmupstrategy) - Adaptive warm-up strategy (v1.0.8+)
- [KORG PE Types](#korg-pe-types) - KORG-specific PE type definitions
- [PEProgramDef / PEChannelInfo](#peprogramdef--pechannelinfo) - Program/Channel information (v1.0.9+)

---

## MIDI2Client

High-level unified client providing full MIDI 2.0 / MIDI-CI / Property Exchange functionality.

### Initialization

```swift
// Basic initialization
let client = try MIDI2Client(name: "MyApp")

// Custom configuration
var config = MIDI2ClientConfiguration()
config.peTimeout = .seconds(10)
let client = try MIDI2Client(name: "MyApp", configuration: config)

// Preset-based initialization
let client = try MIDI2Client(name: "MyApp", preset: .explorer)
```

### Lifecycle

| Method | Description |
|--------|-------------|
| `start() async throws` | Start client (begin Discovery and PE reception) |
| `stop() async` | Stop client (release all resources) |
| `isRunning: Bool` | Whether the client is running |

### Event Stream

```swift
// Create event stream
for await event in await client.makeEventStream() {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.displayName)")
    case .deviceLost(let muid):
        print("Lost: \(muid)")
    case .notification(let notification):
        print("Notification: \(notification)")
    default:
        break
    }
}
```

#### Event Types (MIDI2ClientEvent)

- `.started` - Client started
- `.stopped` - Client stopped
- `.deviceDiscovered(device: MIDI2Device)` - Device discovered
- `.deviceLost(muid: MUID)` - Device lost
- `.deviceUpdated(device: MIDI2Device)` - Device info updated
- `.notification(notification: PENotification)` - PE Subscription notification

### Property Exchange Methods

#### Get DeviceInfo

```swift
let info = try await client.getDeviceInfo(from: muid)
print("Product: \(info.productName ?? "Unknown")")
```

#### Get ResourceList

```swift
let resources = try await client.getResourceList(from: muid)
for resource in resources {
    print("Resource: \(resource.resource)")
}
```

#### GET Operation

```swift
// Get raw data
let response = try await client.get("ChannelList", from: muid)

// Channel-specific
let response = try await client.get("ProgramName", channel: 0, from: muid)

// Custom timeout
let response = try await client.get("DeviceInfo", from: muid, timeout: .seconds(10))
```

#### SET Operation

```swift
// Set JSON data
let data = try JSONEncoder().encode(myData)
try await client.set("Volume", data: data, to: muid)

// Channel-specific
try await client.set("ProgramName", data: data, channel: 0, to: muid)
```

---

## MIDI2ClientConfiguration

Manages MIDI2Client configuration.

### Discovery Settings

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `discoveryInterval` | `Duration` | `.seconds(10)` | Discovery Inquiry send interval |
| `deviceTimeout` | `Duration` | `.seconds(60)` | Device timeout duration |
| `autoStartDiscovery` | `Bool` | `true` | Auto-start discovery on start() |
| `registerFromInquiry` | `Bool` | `true` | Register devices from Discovery Inquiry |

### Property Exchange Settings

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `peTimeout` | `Duration` | `.seconds(5)` | Default PE request timeout |
| `maxInflightPerDevice` | `Int` | `2` | Max concurrent PE requests per device |
| `warmUpStrategy` | `WarmUpStrategy` | `.adaptive` | Warm-up strategy |
| `peSendStrategy` | `PESendStrategy` | `.fallback` | PE send strategy |
| `multiChunkTimeoutMultiplier` | `Double` | `1.5` | Multi-chunk request timeout multiplier |

### Resilience Settings

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `maxRetries` | `Int` | `2` | Max retry count on timeout |
| `retryDelay` | `Duration` | `.milliseconds(100)` | Retry interval |

### Vendor Optimization (v1.0.8+)

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `vendorOptimizations` | `VendorOptimizationConfig` | `.default` | Vendor-specific optimization settings |

```swift
// Enable KORG optimization (default)
var config = MIDI2ClientConfiguration()
config.vendorOptimizations = .default

// Disable all optimizations
config.vendorOptimizations = .none

// Custom optimization
config.vendorOptimizations.enable(.skipResourceListWhenPossible, for: .korg)
```

### Presets

```swift
// Default settings
let config = MIDI2ClientConfiguration.default

// Explorer settings (debugging, longer timeouts)
let config = MIDI2ClientConfiguration.explorer

// Minimal settings (shorter timeouts)
let config = MIDI2ClientConfiguration.minimal
```

---

## MIDI2Device

Represents a discovered MIDI 2.0 device with caching capability.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `muid` | `MUID` | Device MUID |
| `displayName` | `String` | Human-readable name |
| `supportsPropertyExchange` | `Bool` | PE support status |
| `manufacturerName` | `String?` | Manufacturer name |
| `deviceInfo` | `PEDeviceInfo?` | Cached DeviceInfo (auto-fetched on first access) |
| `resourceList` | `[PEResourceEntry]?` | Cached ResourceList (auto-fetched on first access) |

### Methods

#### Type-Safe Property Access

```swift
struct CustomProperty: Codable {
    let value: String
}

if let prop = try await device.getProperty("X-Custom", as: CustomProperty.self) {
    print("Custom: \(prop.value)")
}
```

#### Cache Invalidation

```swift
// Clear cache and force re-fetch on next access
await device.invalidateCache()
```

---

## KORG Extension API

Optimized APIs for KORG products like KORG Module Pro (v1.0.8+).

### getOptimizedResources

Skips ResourceList and directly fetches X-ParameterList (99% faster).

```swift
let result = try await client.getOptimizedResources(from: muid)

if result.usedOptimizedPath {
    // KORG optimized path used (16.4s → 144ms)
    if let params = result.xParameterList {
        for param in params {
            print("CC\(param.controlCC): \(param.displayName)")
        }
    }
} else {
    // Standard path used
    if let resources = result.standardResourceList {
        for resource in resources {
            print("Resource: \(resource.resource)")
        }
    }
}
```

### getXParameterList

Get KORG X-ParameterList (CC number → parameter name mapping).

```swift
let params = try await client.getXParameterList(from: muid)
for param in params {
    print("\(param.displayName): CC\(param.controlCC)")
    print("  Range: \(param.effectiveMinValue)...\(param.effectiveMaxValue)")
    if let defaultValue = param.defaultValue {
        print("  Default: \(defaultValue)")
    }
}
```

### getXProgramEdit

Get KORG X-ProgramEdit (current program data).

```swift
let program = try await client.getXProgramEdit(from: muid)
print("Program: \(program.displayName)")

// Get parameter value
if let level = program.value(for: 11) {
    print("Inst Level (CC11): \(level)")
}

// Display all parameters
for (cc, value) in program.parameterValues {
    print("CC\(cc) = \(value)")
}
```

### getChannelList (v1.0.9+)

Get ChannelList (channel information). Auto-detects vendor and selects `X-ChannelList`/`ChannelList`.

```swift
let channels = try await client.getChannelList(from: muid)
for ch in channels {
    print("Ch \(ch.channel): \(ch.programTitle ?? "No Program")")
    if let bankMSB = ch.bankMSB, let bankLSB = ch.bankLSB, let program = ch.programNumber {
        print("  Bank: \(bankMSB)-\(bankLSB), Program: \(program)")
    }
}
```

### getProgramList (v1.0.9+)

Get ProgramList (program definition list). Auto-converts KORG format (`title`, `bankPC: [Int]`).

```swift
let programs = try await client.getProgramList(from: muid)
for prog in programs {
    print("\(prog.bankMSB)-\(prog.bankLSB)-\(prog.programNumber): \(prog.displayName)")
}
```

---

## WarmUpStrategy

Strategy for sending "warm-up" requests before first actual request on BLE MIDI connections (v1.0.8+).

### Strategies

| Strategy | Behavior | Use Case |
|----------|----------|----------|
| `.always` | Always warm-up | Most reliable but slower |
| `.never` | Never warm-up | Fastest but may fail |
| `.adaptive` | Warm-up on failure, remember result | **Recommended**: Balance of speed and reliability |
| `.vendorBased` | Use vendor-specific optimization | KORG: Use X-ParameterList as warmup |

### Usage Example

```swift
var config = MIDI2ClientConfiguration()

// Adaptive strategy (recommended)
config.warmUpStrategy = .adaptive

// Always warm-up (max reliability)
config.warmUpStrategy = .always

// Vendor-based optimization
config.warmUpStrategy = .vendorBased
```

### How Adaptive Works

```
First request:
  → Try without warm-up
  → Success → Next time no warm-up (fast)
  → Failure → Retry with warm-up → Next time with warm-up (reliable)
```

Device-specific success/failure patterns are remembered for optimal behavior during app runtime.

### Cache Diagnostics

```swift
// Cache diagnostic info
let diag = await client.warmUpCache?.diagnostics
print(diag.description)
// Output: "WarmUpCache: 2 need warm-up, 5 don't, 7 total"
```

---

## KORG PE Types

KORG-specific Property Exchange type definitions (v1.0.8+).

### PEXParameter

X-ParameterList entry (CC number → parameter name mapping).

```swift
struct PEXParameter {
    let controlCC: Int           // CC number (0-127)
    let name: String?            // Parameter name
    let defaultValue: Int?       // Default value
    let minValue: Int?           // Min value (default: 0)
    let maxValue: Int?           // Max value (default: 127)
    let category: String?        // Category

    var displayName: String      // Display name (name or "CC{number}")
    var effectiveMinValue: Int   // Effective min (0 if nil)
    var effectiveMaxValue: Int   // Effective max (127 if nil)
    var valueRange: ClosedRange<Int>  // Value range
}
```

### PEXParameterValue

Parameter value inside X-ProgramEdit.

```swift
struct PEXParameterValue {
    let controlCC: Int  // CC number
    let value: Int      // Current value (0-127)
}
```

### PEXProgramEdit

X-ProgramEdit (current program data).

```swift
struct PEXProgramEdit {
    let name: String?            // Program name
    let category: String?        // Category
    let bankMSB: Int?            // Bank MSB
    let bankLSB: Int?            // Bank LSB
    let programNumber: Int?      // Program number
    let params: [PEXParameterValue]?  // Parameter values

    var displayName: String      // Display name (name or "Unknown Program")
    var parameterValues: [Int: Int]  // CC → value dictionary

    func value(for cc: Int) -> Int?  // Get value for specified CC
}
```

### MIDIVendor

Vendor identification enum.

```swift
enum MIDIVendor {
    case korg
    case roland
    case yamaha
    case nativeInstruments
    case arturia
    case novation
    case akai
    case unknown

    static func detect(from manufacturerName: String?) -> MIDIVendor
}
```

### VendorOptimization

Vendor-specific optimization options.

```swift
enum VendorOptimization {
    case skipResourceListWhenPossible     // Skip ResourceList (KORG: 99% faster)
    case useXParameterListAsWarmup        // Use X-ParameterList as warmup
    case preferVendorResources            // Prefer vendor-specific resources
    case extendedMultiChunkTimeout        // Extended timeout for multi-chunk
}
```

### VendorOptimizationConfig

Vendor optimization configuration.

```swift
var config = VendorOptimizationConfig.default  // KORG optimization enabled
// or
var config = VendorOptimizationConfig.none     // All optimizations disabled

// Custom settings
config.enable(.skipResourceListWhenPossible, for: .korg)
config.disable(.preferVendorResources, for: .korg)

// Check status
if config.isEnabled(.skipResourceListWhenPossible, for: .korg) {
    print("KORG optimization enabled")
}
```

---

## PEProgramDef / PEChannelInfo

Program definition and channel information (v1.0.9+). Auto-converts KORG format.

### PEProgramDef

Program definition retrieved from ProgramList.

```swift
struct PEProgramDef {
    let programNumber: Int  // Program number (0-127)
    let bankMSB: Int        // Bank MSB (0-127)
    let bankLSB: Int        // Bank LSB (0-127)
    let name: String?       // Program name

    var id: String          // "\(bankMSB)-\(bankLSB)-\(programNumber)"
    var displayName: String // name or "Program \(programNumber)"
}
```

#### KORG Format Auto-Conversion

KORG devices use the following format:

```json
{
  "title": "Grand Piano",
  "bankPC": [0, 0, 0]
}
```

MIDI2Kit automatically converts to:

```json
{
  "name": "Grand Piano",
  "bankPC": 0,
  "bankCC": 0,
  "program": 0
}
```

### PEChannelInfo

Channel information retrieved from X-ChannelList/ChannelList.

```swift
struct PEChannelInfo {
    let channel: Int           // Channel number (0-15 or 0-255)
    let title: String?         // Channel name
    let programNumber: Int?    // Current program number
    let bankMSB: Int?          // Current Bank MSB
    let bankLSB: Int?          // Current Bank LSB
    let programTitle: String?  // Current program name
    let clusterType: String?   // Cluster type
    let clusterIndex: Int?     // Cluster index
    let clusterLength: Int?    // Channels in cluster
    let mute: Bool?            // Mute status
    let solo: Bool?            // Solo status

    var id: Int                // channel
    var displayName: String    // title or "Channel \(channel)"
}
```

#### KORG Format Auto-Conversion

KORG devices use `bankPC: [Int]` array, but MIDI2Kit automatically expands to individual properties.

```json
// KORG format
{
  "channel": 0,
  "title": "Piano",
  "programTitle": "Grand Piano",
  "bankPC": [0, 0, 10]
}

// Auto-converted
{
  "channel": 0,
  "title": "Piano",
  "programTitle": "Grand Piano",
  "bankPC": 0,
  "bankCC": 0,
  "program": 10
}
```

---

## Error Handling

MIDI2Kit provides detailed error information.

### MIDI2Error

```swift
enum MIDI2Error: Error {
    case deviceNotResponding(muid: MUID, resource: String?, timeout: Duration)
    case propertyNotSupported(resource: String)
    case communicationFailed(underlying: Error)
    case deviceNotFound(muid: MUID)
    case clientNotRunning
    case cancelled
    case invalidResponse(muid: MUID?, resource: String?, details: String)
}
```

### Error Handling Example

```swift
do {
    let info = try await client.getDeviceInfo(from: muid)
    print("DeviceInfo: \(info)")
} catch MIDI2Error.deviceNotResponding(let muid, let resource, let timeout) {
    print("Device \(muid) did not respond to \(resource ?? "request") within \(timeout)")
} catch MIDI2Error.communicationFailed(let error) {
    print("Communication failed: \(error)")
} catch {
    print("Unexpected error: \(error)")
}
```

---

## Logging

MIDI2Kit provides efficient logging using `os.Logger`.

### Enable/Disable Logging

```swift
// Disable all logs
MIDI2Logger.isEnabled = false

// Enable verbose logging
MIDI2Logger.isVerbose = true
```

### Filter in Console.app

```
subsystem == "com.midi2kit"
```

---

## Diagnostics

MIDI2Client provides detailed diagnostic information.

### Comprehensive Diagnostics

```swift
let diag = await client.diagnostics
print(diag)
```

### Destination Resolution Diagnostics

```swift
if let destDiag = await client.lastDestinationDiagnostics {
    print("Tried destinations: \(destDiag.triedOrder)")
    print("Resolved to: \(destDiag.resolvedDestination)")
}
```

### Communication Trace

```swift
if let trace = await client.lastCommunicationTrace {
    print("Operation: \(trace.operation)")
    print("MUID: \(trace.muid)")
    print("Resource: \(trace.resource ?? "N/A")")
    print("Duration: \(trace.duration)")
    print("Result: \(trace.result)")
}
```

---

## Related Resources

- [KORG Optimization Guide](KORG-Optimization.md) - Detailed guide for KORG optimization features
- [v1.0.9 Migration Guide](v1.0.9-Migration-Guide.md) - Migration guide for v1.0.9
- [CHANGELOG](../CHANGELOG.md) - Change history
- [README](../README.md) - Project overview
