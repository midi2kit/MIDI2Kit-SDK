# KORG Optimization Guide (v1.0.8+)

MIDI2Kit v1.0.8 introduces significant performance improvements for KORG devices like KORG Module Pro. These optimizations achieve **99% reduction** in Property Exchange resource fetch time (16.4s → 144ms).

## Key New Features

### 1. Optimized Resource Fetch API

New APIs dramatically speed up the traditional `getResourceList()` workflow.

#### `getOptimizedResources(from:preferVendorResources:)`

Auto-detects device vendor and uses optimized path when available to fetch resource information.

```swift
import MIDI2Kit

let client = try MIDI2Client(name: "MyApp")
try await client.start()

// After device discovery
let result = try await client.getOptimizedResources(from: device.muid)

if result.usedOptimizedPath {
    // KORG optimized path used (99% faster)
    if let params = result.xParameterList {
        print("Fetched \(params.count) parameters")
        for param in params {
            print("CC\(param.controlCC): \(param.displayName)")
        }
    }
} else {
    // Standard path used
    if let resources = result.standardResourceList {
        print("Available resources: \(resources.map { $0.resource })")
    }
}
```

**Performance Comparison:**

| Approach | Duration | Description |
|----------|----------|-------------|
| Traditional (via ResourceList) | 16.4s | DeviceInfo warmup + ResourceList fetch |
| **Optimized Path (v1.0.8)** | **144ms** | **Direct X-ParameterList fetch (99.1% improvement)** |

### 2. KORG-Specific Type Definitions

Type definitions for handling KORG-proprietary Property Exchange resources.

#### PEXParameter - X-ParameterList Entry

KORG devices like Module Pro provide CC number to parameter name mapping via `X-ParameterList` resource.

```swift
let params = try await client.getXParameterList(from: device.muid)

for param in params {
    print("\(param.displayName) (CC\(param.controlCC))")
    print("  Range: \(param.effectiveMinValue) - \(param.effectiveMaxValue)")
    if let defaultValue = param.defaultValue {
        print("  Default: \(defaultValue)")
    }
}
```

**Convenient Extension Methods:**

```swift
// Find parameter by CC number
if let level = params.parameter(for: 11) {
    print("CC11 is \(level.displayName)")
}

// Get display name for CC number
let name = params.displayName(for: 11) // "Inst Level" or "CC11"

// Create CC → parameter dictionary
let dict = params.byControlCC
if let param = dict[11] {
    print(param.displayName)
}
```

#### PEXProgramEdit - X-ProgramEdit Data

Fetch current program information and all parameter values.

```swift
let program = try await client.getXProgramEdit(from: device.muid)

print("Program: \(program.displayName)")
if let category = program.category {
    print("Category: \(category)")
}

// Get all parameter values
for (cc, value) in program.parameterValues {
    print("CC\(cc) = \(value)")
}

// Get specific CC value
if let level = program.value(for: 11) {
    print("Inst Level: \(level)")
}
```

**Channel-Specific Fetch:**

```swift
// Get program for MIDI channel 0 (Ch.1)
let ch1Program = try await client.getXProgramEdit(channel: 0, from: device.muid)
```

#### PEXParameterValue - Parameter Value

Represents individual parameter values within `PEXProgramEdit`.

```swift
public struct PEXParameterValue: Sendable, Codable {
    public let controlCC: Int  // CC number
    public let value: Int      // Current value (0-127)
}
```

### 3. Adaptive Warm-Up Strategy

Auto-determines warm-up necessity based on connection state.

#### WarmUpStrategy

BLE MIDI connections can be unstable on first request. Warm-up strategy balances reliability and performance by executing warm-up only when needed.

```swift
var config = MIDI2ClientConfiguration()

// Adaptive strategy (recommended, default)
config.warmUpStrategy = .adaptive

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

**Available Strategies:**

| Strategy | Behavior | Use Case |
|----------|----------|----------|
| `.always` | Always warm-up | Most reliable but slower. For devices with known connection issues |
| `.never` | Never warm-up | Fastest but may fail. For devices known not to need warm-up |
| **`.adaptive`** | **Try first, remember failures** | **Recommended: Fast initially, auto-learns for devices needing warm-up** |
| `.vendorBased` | Use vendor-specific optimization | KORG: Use X-ParameterList as warmup |

#### How Adaptive Works

```
First Request:
  → Try without warm-up
  → Success → Next time no warm-up (fast)
  → Failure → Retry with warm-up → Next time with warm-up (reliable)
```

Device-specific success/failure patterns are remembered for optimal behavior during app runtime.

#### Cache Diagnostics

```swift
let cache = await client.warmUpCache
let diag = await cache.diagnostics

print(diag.description)
// Example output: "WarmUpCache: 2 need warm-up, 3 don't, 5 total"
```

### 4. Vendor-Specific Optimization Settings

Enable different optimizations per device vendor.

#### VendorOptimization

```swift
var config = MIDI2ClientConfiguration()

// Default (KORG optimization enabled)
config.vendorOptimizations = .default

// Disable all optimizations
config.vendorOptimizations = .none

// Custom optimization
config.vendorOptimizations.enable(.skipResourceListWhenPossible, for: .korg)
config.vendorOptimizations.enable(.useXParameterListAsWarmup, for: .korg)

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

**KORG-Enabled Optimizations:**

| Optimization | Effect | Performance Impact |
|--------------|--------|-------------------|
| `.skipResourceListWhenPossible` | Skip ResourceList, directly fetch X-ParameterList | **99% faster** |
| `.useXParameterListAsWarmup` | Use X-ParameterList as warm-up | Improves BLE connection stability |
| `.preferVendorResources` | Prefer vendor-specific over standard resources | Fetch more detailed info |
| `.extendedMultiChunkTimeout` | Extend timeout for multi-chunk responses | Prevent timeouts in BLE environment |

#### MIDIVendor Enum

Supported vendors:

```swift
public enum MIDIVendor: String {
    case korg = "KORG"
    case roland = "Roland"
    case yamaha = "Yamaha"
    case native_instruments = "Native Instruments"
    case arturia = "Arturia"
    case novation = "Novation"
    case akai = "Akai"
    case unknown = "Unknown"
}
```

Vendor is auto-detected from `DeviceInfo` manufacturerName.

## Practical Examples

### Example 1: Quickly Fetch KORG Module Pro Parameter List

```swift
import MIDI2Kit

let client = try MIDI2Client(name: "MIDIController")
try await client.start()

// Wait for device discovery
for await event in await client.makeEventStream() {
    guard case .deviceDiscovered(let device) = event else { continue }
    guard device.supportsPropertyExchange else { continue }

    // Fetch with KORG optimized path (144ms)
    let result = try await client.getOptimizedResources(from: device.muid)

    if let params = result.xParameterList {
        print("✅ KORG optimized: Fetched \(params.count) parameters")

        // Display grouped by CC
        for param in params.sorted(by: { $0.controlCC < $1.controlCC }) {
            print("  CC\(String(format: "%3d", param.controlCC)): \(param.displayName)")
            if let category = param.category {
                print("         Category: \(category)")
            }
        }
    }

    break
}

await client.stop()
```

### Example 2: Fetch Current Program and Parameter Values

```swift
// Get program info
let program = try await client.getXProgramEdit(from: device.muid)

print("📋 Current Program: \(program.displayName)")

// Get parameter definitions
let params = try await client.getXParameterList(from: device.muid)

// Display combined current values and definitions
for param in params {
    if let currentValue = program.value(for: param.controlCC) {
        let percentage = Double(currentValue - param.effectiveMinValue) /
                        Double(param.effectiveMaxValue - param.effectiveMinValue) * 100

        print("\(param.displayName):")
        print("  Current: \(currentValue)")
        print("  Range: \(param.effectiveMinValue)-\(param.effectiveMaxValue)")
        print("  Percentage: \(String(format: "%.1f", percentage))%")
    }
}
```

### Example 3: Optimize ResourceList Fetch with Adaptive Strategy

```swift
var config = MIDI2ClientConfiguration()
config.warmUpStrategy = .adaptive  // Default

let client = try MIDI2Client(name: "MyApp", configuration: config)
try await client.start()

// First time: Try without warm-up (fast)
// If successful, next time also no warm-up
do {
    let resources = try await client.getResourceList(from: device.muid)
    print("✅ ResourceList fetch succeeded (no warm-up)")
} catch {
    // If failed, auto-retries with warm-up, remembers for next time
    print("⚠️ First attempt failed, retrying with warm-up...")
}

// Second time and beyond: Use cached strategy (auto-optimized)
let resources = try await client.getResourceList(from: device.muid)
```

### Example 4: Use Vendor-Specific Warm-Up Strategy

```swift
var config = MIDI2ClientConfiguration()
config.warmUpStrategy = .vendorBased
config.vendorOptimizations = .default  // Enable KORG optimization

let client = try MIDI2Client(name: "MyApp", configuration: config)
try await client.start()

// For KORG devices, X-ParameterList is used as warmup
// For other vendors, behaves like .adaptive
let resources = try await client.getResourceList(from: device.muid)
```

## Performance Comparison

Measured results with actual KORG Module Pro (BLE MIDI):

| Operation | v1.0.7 and earlier | v1.0.8 Optimized Path | Improvement |
|-----------|-------------------|----------------------|-------------|
| Resource info fetch | 16,400ms | 144ms | **99.1%** |
| X-ParameterList fetch | 16,400ms (via ResourceList) | 144ms (direct) | **99.1%** |
| DeviceInfo fetch (warm-up) | 100-300ms | 100-300ms | No change |

**How Optimization Works:**

```
【v1.0.7 and earlier】
1. DeviceInfo fetch (warm-up) - 200ms
2. ResourceList fetch - 16,200ms (multi-chunk, unstable over BLE)
3. Search for needed resource
Total: 16,400ms

【v1.0.8 Optimized】
1. X-ParameterList direct fetch - 144ms (skip ResourceList)
Total: 144ms

Speedup: (16,400 - 144) / 16,400 = 99.1%
```

## Configuration Guide

### Recommended Settings for KORG Module Pro

```swift
var config = MIDI2ClientConfiguration()

// Adaptive warm-up (auto-learn)
config.warmUpStrategy = .adaptive

// Enable KORG optimization
config.vendorOptimizations = .default

// Extended timeout for BLE environment
config.peTimeout = .seconds(5)
config.multiChunkTimeoutMultiplier = 1.5

// Retry settings
config.maxRetries = 2
config.retryDelay = .milliseconds(100)

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

### Recommended Settings for Standard MIDI 2.0 Devices

```swift
// Default settings are sufficient
let config = MIDI2ClientConfiguration()
// or
let client = try MIDI2Client(name: "MyApp", preset: .standard)
```

### Development/Debug Settings

```swift
var config = MIDI2ClientConfiguration(preset: .explorer)

// Enable logging
MIDI2Logger.isEnabled = true
MIDI2Logger.isVerbose = true

let client = try MIDI2Client(name: "MyApp", configuration: config)
try await client.start()

// Check diagnostic info
let diag = await client.diagnostics
print(diag)
```

## Troubleshooting

### Optimized Path Not Used

**Symptom:** `result.usedOptimizedPath` is `false`

**Causes:**
- Device not recognized as KORG
- Vendor optimization disabled
- X-ParameterList resource unavailable

**Solution:**

```swift
// 1. Check vendor detection
let info = try await client.getDeviceInfo(from: device.muid)
let vendor = MIDIVendor.detect(from: info.manufacturerName)
print("Detected vendor: \(vendor)")

// 2. Check optimization settings
let config = await client.configuration
print("vendorOptimizations: \(config.vendorOptimizations)")

// 3. Check logs
MIDI2Logger.isVerbose = true
let result = try await client.getOptimizedResources(from: device.muid)
```

### Adaptive Strategy Not Learning

**Symptom:** Warm-up always executed or never executed

**Causes:**
- Cache cleared
- Device key generation failed

**Solution:**

```swift
// Check cache status
let cache = await client.warmUpCache
let diag = await cache.diagnostics
print(diag)

// Clear cache for specific device
if let info = try await client.getDeviceInfo(from: device.muid) {
    let key = WarmUpCache.deviceKey(
        manufacturer: info.manufacturerName,
        model: info.modelName
    )
    await cache.clear(for: key)
}
```

### X-ParameterList Decode Error

**Symptom:** `MIDI2Error.invalidResponse` when decoding X-ParameterList

**Causes:**
- Device returning non-standard JSON format
- Missing controlcc field

**Solution:**

```swift
// Check raw data
let response = try await client.get("X-ParameterList", from: device.muid)
print("Status: \(response.statusCode)")
print("Body: \(response.bodyString ?? "(empty)")")

// Check RobustJSONDecoder diagnostic info
if let diag = await client.peManager.lastDecodingDiagnostics {
    print("Raw: \(diag.rawData)")
    print("Error: \(diag.parseError ?? "(none)")")
}
```

## Backward Compatibility

v1.0.8 maintains the following backward compatibility:

### Deprecated API

```swift
// Deprecated (v1.0.8+)
config.warmUpBeforeResourceList = true

// Recommended
config.warmUpStrategy = .always
```

The `warmUpBeforeResourceList` property is still available but internally maps to `warmUpStrategy`.

### Impact on Existing Code

v1.0.8 new features are opt-in, so existing code works without modification:

- Default `.adaptive` strategy enabled (warm-up behavior auto-optimized)
- Default KORG optimization enabled (no impact unless using `getOptimizedResources()`)
- Existing `getResourceList()` continues working (only affected by warm-up strategy)

## Summary

MIDI2Kit v1.0.8 significantly speeds up KORG device interactions with these new features:

✅ **99% faster** - `getOptimizedResources()` reduces 16.4s → 144ms
✅ **KORG-specific types** - Type-safe APIs with `PEXParameter`, `PEXProgramEdit`
✅ **Adaptive strategy** - Auto-learn optimal per device
✅ **Vendor optimization** - KORG-specific optimizations enabled by default

Existing apps benefit from adaptive strategy without configuration changes. For maximum performance, consider using `getOptimizedResources()`.

## Related Documentation

- [README.md](../README.md) - MIDI2Kit basic usage
- [CHANGELOG.md](../CHANGELOG.md) - Detailed v1.0.8 changes
- [KORG-Module-Pro-Limitations.md](./KORG-Module-Pro-Limitations.md) - Known KORG device limitations
- [MigrationGuide.md](./MigrationGuide.md) - Migration guide from low-level API
