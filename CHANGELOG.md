# Changelog

Changelog for MIDI2Kit-SDK. This SDK is the binary distribution repository for [MIDI2Kit](https://github.com/hakaru/MIDI2Kit).

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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
