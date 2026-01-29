# Changelog

All notable changes to MIDI2Kit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Phase 1: Core Update (2026-01-30)
- **Real Device Testing**: Verified PE operations with KORG Module Pro on iPhone
- **FileMIDI2Logger**: File-based logging for automated testing
- **CompositeMIDI2Logger**: Combine multiple loggers
- **PE Message Format Tests**: Added comprehensive tests for PE Get Inquiry/Reply format validation
  - `testPEGetInquiryDoesNotContainChunkFields()`
  - `testPEGetReplyContainsChunkFields()`
  - `testHeaderDataStartPositionDiffers()`
  - `test14BitEncodingLargeSizes()`

#### Phase 2: High-Level API (2026-01-30)
- **MIDI2Client Actor**: High-level client for MIDI 2.0 operations
  - Simplified initialization with presets (`.korgBLEMIDI`, `.standard`)
  - Automatic discovery lifecycle management
  - Built-in event streaming with `makeEventStream()`
  - Automatic destination resolution with fallback
  - Integrated caching for device info and resource lists

- **MIDI2ClientConfiguration**: Flexible configuration options
  - `destinationStrategy`: Control destination resolution behavior
  - `warmUpBeforeResourceList`: BLE connection warm-up option
  - `peTimeout`: Configurable timeout for PE operations
  - Preset configurations for common scenarios

- **DestinationStrategy Enhancement**: Unified destination fallback
  - All PE methods now support automatic fallback on timeout
  - Consistent retry pattern: try primary destination → timeout → try next candidate once
  - Applies to: `getDeviceInfo`, `getResourceList`, `get`, `set`
  - Improved diagnostics with `DestinationDiagnostics`

- **MIDI2Device Actor**: Type-safe device wrapper
  - Converted from struct to actor for thread-safe caching
  - Cached `deviceInfo` property with automatic fetching
  - Cached `resourceList` property with automatic fetching
  - Type-safe `getProperty<T>(_:as:)` with automatic JSON decoding
  - `invalidateCache()` method to force fresh fetches

- **MIDI2Error**: Comprehensive error types
  - `.deviceNotResponding(muid:resource:timeout:)`
  - `.propertyNotSupported(resource:)`
  - `.communicationFailed(underlying:)`
  - `.deviceNotFound(muid:)`
  - `.clientNotRunning`
  - `.cancelled`
  - Full `LocalizedError` conformance with recovery suggestions

### Changed

- **MIDI2ClientConfiguration**: Added `logger` property for configurable logging

### Deprecated

#### CIManager
- `start()` - Use `MIDI2Client.start()` instead
- `stop()` - Use `MIDI2Client.stop()` instead
- `startDiscovery()` - Use `MIDI2Client` (discovery starts automatically)
- `stopDiscovery()` - Use `MIDI2Client` (discovery stops automatically)
- `events` - Use `MIDI2Client.makeEventStream()` instead
- `destination(for:)` - Use `MIDI2Client` (destination resolved automatically)
- `makeDestinationResolver()` - Use `MIDI2Client` (destination resolver integrated)

#### PEManager
- `startReceiving()` - Use `MIDI2Client.start()` instead
- `stopReceiving()` - Use `MIDI2Client.stop()` instead
- `destinationResolver` - Use `MIDI2Client` (destination resolver integrated)
- `get(_:from:PEDeviceHandle)` - Use `MIDI2Client.get()` instead (Legacy API)
- `set(_:data:to:PEDeviceHandle)` - Use `MIDI2Client.set()` instead (Legacy API)

**Migration Guide**: See [docs/MigrationGuide.md](docs/MigrationGuide.md) for detailed migration instructions.

### Fixed
- **Destination Fallback**: `getResourceList` now properly retries with next destination candidate on timeout (previously only retried same destination)
- **BLE MIDI Reliability**: Known issue with KORG Module Pro ResourceList chunk 2/3 loss documented (physical layer limitation)

## [0.1.0] - 2026-01-26

### Added
- Initial MIDI2Kit release
- Core MIDI-CI support
- Property Exchange (PE) support
- Basic transport layer
- Discovery protocol implementation

---

**Note**: This project is under active development. APIs may change before the 1.0 release.
