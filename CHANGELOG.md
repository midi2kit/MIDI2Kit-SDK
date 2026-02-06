# Changelog

Changelog for MIDI2Kit-SDK. This SDK is the binary distribution repository for [MIDI2Kit](https://github.com/hakaru/MIDI2Kit).

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.0.11] - 2026-02-06

### Added
- **Virtual MIDI Endpoint** (MIDI2Transport): Inter-app MIDI communication support (Issue #9)
  - `VirtualEndpointCapable` protocol with 5 methods for creating/removing virtual endpoints
  - `VirtualDevice` struct for paired source+destination
  - `publishVirtualDevice(name:)` / `unpublishVirtualDevice(_:)` convenience API
  - `sendFromVirtualSource(_:source:)` using `MIDIReceived()`
  - `broadcast()` filtering to skip own virtual destinations (feedback prevention)
  - `MIDITransportError`: 3 new virtual endpoint error cases
  - `MIDITransport` protocol unchanged (100% backwards compatible)
  - 18 new tests (527 total)

## [1.0.10] - 2026-02-06

### Added
- **AnyCodableValue** (MIDI2Core): Type-safe container for heterogeneous JSON values (Int, String, Bool, Array, Dictionary mixed types)
  - Convenience accessors: `stringValue`, `intValue`, `doubleValue`, `boolValue`, `arrayValue`, `dictionaryValue`
  - Coercion methods: `coercedIntValue`, `coercedStringValue`
  - Full Codable, Hashable, Equatable, ExpressibleByLiteral support
- **PEXCurrentValue** (MIDI2PE): Support for `currentValues` in X-ProgramEdit with mixed-type parameters
  - Handles JSON like `{"controlcc": 11, "current": 100}` or `{"controlcc": 12, "current": "High"}`
  - Convenience accessors: `intValue`, `stringValue`
- **bankPC Array Support in PEXProgramEdit** (MIDI2PE): Automatic `[bankMSB, bankLSB, programNumber]` array conversion
  - Same pattern as PEProgramDef/PEChannelInfo for consistency
- **X-Resource Fallback** (MIDI2Kit): Auto-try X-prefixed resources before standard resources
  - `getChannelList()`: X-ChannelList → ChannelList fallback
  - `getProgramList()`: X-ProgramList → ProgramList fallback
  - `getProgramEdit()`: X-ProgramEdit → ProgramEdit fallback (new API)
- **BLE MIDI Timeout Optimization** (MIDI2Transport + MIDI2Kit)
  - `MIDITransportType` enum: `.usb`, `.ble`, `.network`, `.virtual`, `.unknown`
  - Auto-detect BLE transport via `kMIDIPropertyDriverOwner` and display name heuristics
  - `autoAdjustBLETimeout` and `blePETimeout` configuration options
  - Automatic PE timeout adjustment to 15s for BLE connections
- **Empty Response Handling** (MIDI2PE)
  - `PEEmptyResponseRepresentable` protocol for graceful 0-byte response handling
  - `PEError.emptyResponse(resource:)` for non-array types

### Fixed
- Removed duplicate `AnyCodableValue` definition from `PEResource.swift` (unified to MIDI2Core version)

### Tests
- 509 tests passing (+51 new tests)

## [1.0.9] - 2026-02-06

### Added
- **KORG ChannelList/ProgramList Auto-Conversion**: Automatically converts KORG proprietary format to standard format
  - `PEProgramDef`: Auto-converts KORG format (`title`, `bankPC: [Int]`)
    - `title` → `name` mapping
    - `bankPC: [bankMSB, bankLSB, program]` → Auto-expands to individual properties
    - Correctly handles explicit `program: 0` (distinguishes from `nil`)
  - `PEChannelInfo`: Auto-converts KORG format (`bankPC: [Int]`)
    - `bankPC: [bankMSB, bankLSB, program]` → Auto-expands to individual properties
  - Maintains backward compatibility with standard format
- **New APIs** (`MIDI2Client+KORG.swift`)
  - `getChannelList(from:timeout:)`: Auto-detects vendor and selects `X-ChannelList`/`ChannelList`
  - `getProgramList(from:timeout:)`: Auto-detects vendor and fetches ProgramList

### Changed
- **PETypes.swift**: Enhanced decoding for `PEProgramDef`, `PEChannelInfo`
  - Supports both KORG and standard formats

### Testing
- **PETypesKORGFormatTests.swift**: Added 24 tests
  - PEProgramDef KORG Format: 9 tests
  - PEChannelInfo KORG Format: 7 tests
  - Edge case tests: 7 tests (explicit `program: 0`, empty array, out-of-range values)
  - ChannelList/ProgramList array decoding: 2 tests

## [1.0.8] - 2026-02-06

### Added
- **KORG-Specific PE Optimization**: 99% faster PE fetch (16.4s → 144ms)
  - `VendorOptimizationConfig` for vendor-specific settings
  - Skip ResourceList fetch for KORG devices
  - Direct `X-ParameterList` access
- **X-ParameterList / X-ProgramEdit Native Support**
  - `PEXParameter` type for KORG parameter definitions
  - `PEXProgramEdit` type for current program data
  - `MIDIVendor` enum for vendor detection
  - Extension methods: `getXParameterList()`, `getXProgramEdit()`, `getOptimizedResources()`
- **Adaptive WarmUp Strategy**
  - `WarmUpStrategy` enum (`.always`, `.never`, `.adaptive`, `.vendorBased`)
  - `WarmUpCache` actor for device-specific warmup tracking
  - Default changed to `.adaptive`

### Changed
- `MIDI2ClientConfiguration.warmUpStrategy` replaces `warmUpBeforeResourceList`
- Added `MIDI2ClientConfiguration.vendorOptimizations`
- Added `MIDI2Error.invalidResponse` case

### Performance
- **KORG Optimization**: PE operations 99.1% faster (16.4s → 144ms)
  - Skip ResourceList (16.4s)
  - Direct X-ParameterList fetch (144ms)

## [1.0.7] - 2026-02-06

### Fixed
- **Critical**: Fixed AsyncStream race condition in 4 additional files
  - `CoreMIDITransport.swift` (production MIDI I/O)
  - `MockMIDITransport.swift` (test infrastructure)
  - `LoopbackTransport.swift` (test infrastructure)
  - `PESubscriptionManager.swift` (subscription events)

## [1.0.6] - 2026-02-06

### Fixed
- **Critical**: Fixed AsyncStream continuation race condition in CIManager
  - `CIManager.events` stream now properly fires events
  - Used `AsyncStream.makeStream()` for immediate continuation access
  - Fixes GitHub issue #1: deviceDiscovered events not firing

## [1.0.5] - 2026-02-05

### Added
- **MIDI-CI Responder**: Same-process testing without physical hardware
  - `MockDevice` actor for device simulation
  - `LoopbackTransport` for bidirectional communication
  - `PEResponder` for Property Exchange handling
  - Device presets: KORG Module Pro, Roland, Yamaha, generic

### Improved
- Auto-register preset resources in `MockDevice.start()`
- Safer JSON escaping in error response headers
- Shutdown guard in `LoopbackTransport`

## [1.0.4] - 2026-02-05

### Changed
- `.explorer` preset now uses `peSendStrategy = .broadcast`
- Optimized Property Exchange send strategy

### Fixed
- Fixed PE timeout issue with KORG BLE MIDI devices (e.g., KORG Module Pro)

## [1.0.3] - 2026-02-05

### Changed
- Changed default value of `registerFromInquiry` from `false` to `true`
- Improved compatibility with KORG and similar devices
- Enhanced device discovery behavior

## [1.0.2] - 2026-02-05

### Fixed
- **Important**: Fixed dyld "Library not loaded" error
  - Resolved `LC_ID_DYLIB` mismatch
  - All XCFrameworks now have correct install names
  - Eliminated runtime dependency on `MIDI2ClientDynamic.framework`

### Technical Details
- Fixed `LC_ID_DYLIB` using `install_name_tool` during XCFramework build
- Resolved dynamic linking issues after framework rename

## [1.0.1] - 2026-02-05

### Changed
- **Breaking Change**: Renamed module from `MIDI2Client` to `MIDI2Kit`
  - Binary target renamed: `MIDI2Client` → `MIDI2Kit`
  - Import statement change required: `import MIDI2Client` → `import MIDI2Kit`

### Added
- Migration guide in README

### Migration Guide
When upgrading from v1.0.0:

```swift
// Before
import MIDI2Client

// After
import MIDI2Kit
```

## [1.0.0] - 2026-02-04

### Added
- Initial release
- XCFramework binary distribution
- Swift module support

### Modules
- `MIDI2Core` - Foundation types, UMP messages, constants
- `MIDI2Transport` - CoreMIDI integration and connection management
- `MIDI2CI` - MIDI Capability Inquiry protocol (device discovery)
- `MIDI2PE` - Property Exchange (GET/SET device properties)
- `MIDI2Kit` - High-level unified API (recommended)

---

**Note**: For detailed source code changes, see the [MIDI2Kit main repository CHANGELOG](https://github.com/hakaru/MIDI2Kit/blob/main/CHANGELOG.md).
