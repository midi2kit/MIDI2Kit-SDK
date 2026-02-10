# Changelog

All notable changes to MIDI2Kit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.12] - 2026-02-11

### Fixed
- **XCFramework macOS Binary Issue**: Fixed CFBundleExecutable mismatch in macOS framework
  - Root cause: v1.0.12 XCFramework had CFBundleExecutable=MIDI2ClientDynamic instead of MIDI2Kit
  - Renamed dynamic library product from `MIDI2ClientDynamic` to `MIDI2KitDynamic` in Package.swift
  - Fixed build-xcframework.sh to properly handle macOS versioned framework (Versions/A/) structure
  - Ensures binary name, symlink, Info.plist CFBundleExecutable, and install name are all consistent
  - Resolves xcodebuild link failures when using MIDI2Kit-SDK v1.0.12

## [1.0.9] - 2026-02-06

### Added
- **KORG ChannelList/ProgramList Auto-Conversion**: Auto-convert KORG proprietary format to standard format
  - `PEProgramDef`: Auto-convert KORG format (`title`, `bankPC: [Int]`)
    - `title` → `name` mapping
    - `bankPC: [bankMSB, bankLSB, program]` → Auto-expand to individual properties
    - Correctly handles explicit `program: 0` (distinguishes from `nil`)
  - `PEChannelInfo`: Auto-convert KORG format (`bankPC: [Int]`)
    - `bankPC: [bankMSB, bankLSB, program]` → Auto-expand to individual properties
  - Maintains backward compatibility with standard format

- **New APIs** (`MIDI2Client+KORG.swift`)
  - `getChannelList(from:timeout:)`: Auto-detect vendor and select `X-ChannelList`/`ChannelList`
  - `getProgramList(from:timeout:)`: Auto-detect vendor and fetch ProgramList

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
- **KORG最適化機能** (`PEKORGTypes.swift`, `MIDI2Client+KORG.swift`)
  - `PEXParameter`: KORG X-ParameterListエントリ（CC番号→パラメータ名マッピング）
  - `PEXParameterValue`: X-ProgramEdit内のパラメータ値
  - `PEXProgramEdit`: X-ProgramEdit（現在のプログラムデータ）
  - `MIDIVendor`: ベンダー識別enum
  - `VendorOptimization`: ベンダー別最適化オプション
  - `VendorOptimizationConfig`: ベンダー最適化設定

- **KORG拡張API** (`MIDI2Client+KORG.swift`)
  - `getXParameterList(from:timeout:)`: X-ParameterList取得
  - `getXParameterListWithResponse(from:timeout:)`: レスポンス付き取得
  - `getXProgramEdit(from:timeout:)`: X-ProgramEdit取得
  - `getXProgramEdit(channel:from:timeout:)`: チャンネル指定X-ProgramEdit取得
  - `getOptimizedResources(from:preferVendorResources:)`: 最適化パス自動選択
    - KORGデバイス: ResourceListをスキップしてX-ParameterList直接取得（99%高速化）
    - 他のベンダー: 標準パスにフォールバック

- **Adaptive WarmUp Strategy** (`WarmUpStrategy.swift`)
  - `WarmUpStrategy` enum: `.always`, `.never`, `.adaptive`, `.vendorBased`
  - `WarmUpCache` actor: デバイスごとの成功/失敗記録（in-memory、TTL付き）
  - `WarmUpCacheDiagnostics`: キャッシュ診断情報

### Changed
- **MIDI2ClientConfiguration.swift**
  - `warmUpBeforeResourceList: Bool` → `warmUpStrategy: WarmUpStrategy` (後方互換性維持)
  - `vendorOptimizations: VendorOptimizationConfig` 追加
  - デフォルト: `.adaptive` warmup strategy

- **MIDI2Client.swift**
  - WarmUpCache統合
  - `getResourceList()`: adaptive戦略対応
  - vendorBased戦略: KORG+useXParameterListAsWarmup時はX-ParameterListでwarmup

- **MIDI2Error.swift**
  - `.invalidResponse(muid:resource:details:)` ケース追加

### Performance
- **KORG最適化**: PE操作が99.1%高速化（16.4秒 → 144ms）
  - ResourceList (16.4秒) をスキップ
  - X-ParameterList直接取得 (144ms)

### Testing
- **PEKORGTypesTests.swift**: 25テスト追加
  - PEXParameterTests: 9テスト
  - PEXParameterValueTests: 3テスト
  - PEXProgramEditTests: 5テスト
  - MIDIVendorTests: 4テスト
  - VendorOptimizationConfigTests: 4テスト

- **WarmUpStrategyTests.swift**: 20テスト追加
  - WarmUpStrategyTests: 4テスト
  - WarmUpCacheTests: 12テスト
  - WarmUpCacheDiagnosticsTests: 1テスト
  - ConfigurationWarmUpStrategyTests: 3テスト

### Documentation
- **docs/KORG-Optimization.md**: KORG最適化ガイド（日本語）

## [1.0.7] - 2026-02-06

### Fixed
- **AsyncStream race condition fixed**: Fixed similar bugs in 4 files
  - `CoreMIDITransport.swift`: Production MIDI I/O (highest priority)
  - `MockMIDITransport.swift`: Test infrastructure
  - `LoopbackTransport.swift`: Test infrastructure
  - `PESubscriptionManager.swift`: Subscription events
  - Unified all AsyncStreams to `makeStream()` pattern

### Changed
- **AsyncStream initialization**: Unified from closure pattern (deferred execution) to `makeStream()` (immediate execution)
  - Prevents race conditions
  - Ensures continuation is set

## [1.0.6] - 2026-02-06

### Fixed
- **CIManager.events AsyncStream race condition**: Critical bug fix
  - AsyncStream continuation was not set correctly in `CIManager.init()`
  - Old closure pattern (deferred execution) left `eventContinuation` as `nil`
  - Fixed by using `AsyncStream.makeStream()` to immediately get continuation
  - `.deviceDiscovered`, `.deviceLost` events now fire correctly

### Impact
- **Affected**: All code using CIManager directly
- **Symptom**: `CIManager.events` stream never fires events
- **Resolution**: Update to v1.0.6 for events to fire correctly

### Testing
- All 387 tests pass

## [1.0.4] - 2026-02-05 (SDK Release)

### Changed
- **MIDI2Kit-SDK**: `.explorer` プリセットで `peSendStrategy = .broadcast` を使用
- **MIDI2Kit-SDK**: KORG BLE MIDI デバイスの PE タイムアウト問題を修正

## [1.0.3] - 2026-02-05 (SDK Release)

### Changed
- **MIDI2Kit-SDK**: `registerFromInquiry` のデフォルト値を `true` に変更（KORG互換性向上）

## [1.0.2] - 2026-02-05 (SDK Release)

### Fixed
- **MIDI2Kit-SDK**: dyld Library not loaded エラーを修正（LC_ID_DYLIB 不一致解消）

## [1.0.1] - 2026-02-05 (SDK Release)

### Changed
- **MIDI2Kit-SDK**: モジュール名を `MIDI2Client` から `MIDI2Kit` にリネーム（破壊的変更）

## [1.0.0] - 2026-02-04 (SDK Release)

### Added
- **MIDI2Kit-SDK**: XCFramework バイナリ配布リポジトリ初回リリース
- **MIDI2Kit-SDK**: 5つのモジュール（MIDI2Core, MIDI2Transport, MIDI2CI, MIDI2PE, MIDI2Kit）のバイナリ提供

---

## [Unreleased] (Source)

### Added

#### SET Operations Extension (2026-02-04)

**Phase 1: Payload Validation Layer**
- **PEPayloadValidator Protocol**: Pre-SET validation interface for catching errors before device transmission
  - `PEPayloadValidationError`: Comprehensive validation error types (invalidJSON, schemaViolation, payloadTooLarge, etc.)
  - `PEPayloadValidatorRegistry` (actor): Thread-safe validator registration system
  - `PESchemaBasedValidator`: JSONSchema-based validation with schema caching
  - `PEBuiltinValidators`: Pre-configured validators for DeviceInfo, ResourceList, ChannelList, and common resources
  - `PEError.payloadValidationFailed`: New error case for validation failures

**Phase 2: Batch SET API**
- **PESetItem**: Type-safe SET item structure
  - Factory methods: `json(resource:value:channel:)`, `dictionary(resource:_:channel:)`
  - Support for channel-specific resources
- **PEBatchSetOptions**: Batch operation strategies
  - `.default`: Parallel execution with first error (default)
  - `.strict`: Parallel execution, abort all on any error
  - `.fast`: Parallel execution, continue on errors
  - `.serial`: Sequential execution
- **PEBatchSetResponse**: Structured batch result with per-item success/failure tracking
- **PEManager.batchSet()**: Execute multiple SET operations concurrently
- **PEManager.batchSetChannels()**: Channel-specific batch SET with automatic channel routing

**Phase 3: SET Chain/Pipeline**
- **PEPipeline<T>**: Fluent builder for GET → Transform → SET workflows
  - Read operations: `get(resource:channel:)`, `getJSON(_:as:channel:)`
  - Transform: `transform(_:)`, `map(_:)` for value modification
  - Write operations: `set(resource:)`, `setJSON(resource:)`
  - Conditional: `where(_:)`, `whereOr(_:)` for conditional execution
  - Execution: `execute()` to run the pipeline
- **PEConditionalSet<T>**: Read-modify-write with conditional updates
  - `PEConditionalResult<T>`: Typed result (updated/skipped/failed)
  - Optimized for scenarios where SET depends on current value (e.g., increment, toggle)

**Testing**
- Added 53 new tests (372 total):
  - `PEPayloadValidatorTests.swift`: 18 tests for validation layer
  - `PEBatchSetTests.swift`: 19 tests for batch operations
  - `PEPipelineTests.swift`: 16 tests for pipeline and conditional SET

**Examples**

```swift
// Payload validation
let validator = PESchemaBasedValidator(schema: mySchema)
try await validatorRegistry.register(validator, for: "Volume")
try await peManager.set("Volume", data: volumeData, to: device) // Validates before sending

// Batch SET
let items = [
    try PESetItem.json(resource: "Volume", value: VolumeInfo(level: 80)),
    try PESetItem.json(resource: "Pan", value: PanInfo(position: 0))
]
let result = try await peManager.batchSet(items, to: device, options: .strict)

// Pipeline
let result = try await PEPipeline(manager: peManager, device: device)
    .getJSON("ProgramName", as: ProgramName.self)
    .map { $0.name.uppercased() }
    .transform { ProgramName(name: $0) }
    .setJSON("ProgramName")
    .execute()
```

#### Code Quality & Robustness Improvements (2026-02-04)

**Refactoring Phase A-D (2026-02-04)**: Major code organization and quality improvements
- **R-001**: Extracted 3 CI message format parsers from `CIMessageParser` into separate testable functions
  - Added 8 new dedicated format parser tests
  - Improved test coverage and maintainability
- **R-002**: Consolidated timeout+retry logic in `MIDI2Client`
  - Unified `executeWithDestinationFallback` method
  - Eliminated 450 lines of duplicate code across 4 PE methods
  - Consistent error handling and retry behavior
- **R-003**: Split `PEManager.handleReceived` (150 lines) into 5 focused handlers
  - `handleGetReply`, `handleSetReply`, `handleSubscribeReply`, `handleNotify`, `handleNAK`
  - Single Responsibility Principle applied
  - Enhanced readability and maintainability
- **R-006**: Reorganized `PETypes.swift` (921 lines) into 7 domain-focused files
  - `Types/PERequest.swift`: Request parameters
  - `Types/PEDeviceInfo.swift`: Device metadata
  - `Types/PEControllerTypes.swift`: Controller-related types
  - `Types/PEHeaderTypes.swift`: PE message headers
  - `Types/PENAKTypes.swift`: NAK status codes
  - `Types/PEChannelInfo.swift`: Channel metadata
  - `Types/PESubscriptionTypes.swift`: Subscription types
- **Phase C/D**: Code cleanup and type-safe event API
  - Removed 5 completed TODO comments from `PESubscriptionHandler`
  - Added type-safe event extraction API to `MIDI2ClientEvent`
  - Added `AsyncStream` convenience methods: `deviceDiscovered()`, `deviceLost()`, `notifications()`

**Improvements**:
- Code reduction: ~10% overall (20,681 → 18,500 lines)
- Duplicate code: -450 lines
- Test coverage: 319 tests maintained (100% pass rate)
- Code review rating: ⭐⭐⭐⭐⭐ 5.0/5

#### Code Quality & Robustness Improvements (2026-02-04)

- **Integration Test Suite**: 5 comprehensive integration tests added
  - Discovery to PE Get flow (end-to-end)
  - Multiple devices queried simultaneously
  - Timeout followed by retry succeeds
  - Device loss during PE request returns error
  - Request IDs are properly recycled after completion

- **Request ID Lifecycle Management**: Enhanced request ID cooldown mechanism
  - Prevents delayed response mismatch after timeout
  - Default 2-second cooldown period before ID reuse
  - `forceCooldownExpire()` and `forceExpireAllCooldowns()` control API
  - Addresses issue identified in ktmidi #57

- **MIDI-CI 1.1 Full Support**: Improved Discovery Reply parsing
  - Accepts partial payloads (minimum 11 bytes for DeviceIdentity)
  - `isPartialDiscovery` flag in `DiscoveredDevice` for diagnostics
  - Better compatibility with KORG devices using MIDI-CI 1.1 format
  - Addresses issue identified in ktmidi #102

- **Security Enhancements**:
  - Buffer size limits (1MB) added to `SysExAssembler` (DoS prevention)
  - Debug print statements wrapped in `#if DEBUG` (prevents data leakage)

### Changed

- **CIManager**: Added `registerFromInquiry` configuration flag (default: `false`)
  - When `false`, only devices responding with Discovery Reply (0x71) are registered
  - Prevents false positives from macOS built-in MIDI-CI clients
  - Eliminates PE timeouts caused by non-responding devices

- **CoreMIDITransport**: Fixed MIDIPacketList handling using `unsafeSequence()`
  - Resolves crash in packet callback

### Fixed

- **Force Cast Removal**: Replaced `as!` with `as?` + fallback in `MIDI2Client.swift`
- **Print Statements**: Replaced debug `print()` with structured logger calls in `PEManager.swift` and `CIMessageParser.swift`
- **Documentation**: Enhanced shutdown lifecycle documentation in `CoreMIDITransport.swift`

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
