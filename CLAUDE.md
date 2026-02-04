# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

# MIDI2Kit - Swift MIDI 2.0 Library

A modern Swift library for MIDI 2.0 / MIDI-CI / Property Exchange on Apple platforms.

## Build Commands

### Build (macOS)
```bash
swift build
```

### Build for iOS Simulator
```bash
xcodebuild build \
  -scheme MIDI2Kit \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

### Run Tests
```bash
swift test
```

### Run Specific Test
```bash
swift test --filter <TestClassName>.<testMethodName>
# Example: swift test --filter PEManagerTests.testGetRequest
```

### Clean Build
```bash
swift package clean
swift build
```

---

## Module Architecture

MIDI2Kit is organized into 5 Swift Package Manager modules with clear dependency hierarchy:

```
MIDI2Core (Foundation - no dependencies)
    ↑
    ├─ MIDI2Transport (CoreMIDI abstraction)
    ├─ MIDI2CI (Capability Inquiry / Discovery)
    ├─ MIDI2PE (Property Exchange)
    └─ MIDI2Kit (High-Level API)
```

### MIDI2Core
**Purpose**: Foundation types, UMP messages, constants

**Key Types**:
- `MUID`: 28-bit MIDI Unique Identifier
- `DeviceIdentity`: Manufacturer, family, model, version
- `UMPMessage`: Type-safe MIDI 2.0 & MIDI 1.0 messages
- `Mcoded7`: 8-bit ↔ 7-bit encoding for SysEx
- `MIDI2Logger`: Configurable logging system
- `RobustJSONDecoder`: Enhanced JSON parsing with diagnostics
- `PEDecodingDiagnostics`: Detailed JSON decode error tracking

**Location**: `Sources/MIDI2Core/`

### MIDI2Transport
**Purpose**: CoreMIDI integration with connection management

**Key Types**:
- `CoreMIDITransport` (actor): Real CoreMIDI implementation
- `MIDITransport` (protocol): Abstract MIDI I/O interface
- `MockMIDITransport` (actor): Testing support
- `SysExAssembler`: Reassembles fragmented SysEx messages

**Key Features**:
- Automatic source/destination enumeration
- Differential connection management
- Setup change detection
- Bidirectional UMP/SysEx communication

**Location**: `Sources/MIDI2Transport/`

### MIDI2CI
**Purpose**: MIDI Capability Inquiry protocol (device discovery)

**Key Types**:
- `CIManager` (actor): High-level device discovery
- `CIManagerConfiguration`: Discovery behavior settings
- `DiscoveredDevice`: Device metadata from discovery
- `CIMessageBuilder`: Constructs MIDI-CI SysEx messages
- `CIMessageParser`: Parses incoming MIDI-CI responses

**Key Features**:
- Automatic Discovery Inquiry broadcasts
- Device lifecycle tracking (discovered → updated → lost)
- Device timeout detection
- Optional responder mode
- `registerFromInquiry` flag (default: false) - only register devices from Discovery Reply

**Location**: `Sources/MIDI2CI/`

### MIDI2PE
**Purpose**: Property Exchange (GET/SET device properties, subscriptions)

**Key Actors**:
- `PEManager` (actor): High-level PE API (1315 lines after Phase 6 refactoring)
- `PESubscriptionHandler` (actor): Subscribe/Unsubscribe/Notify handling
- `PETransactionManager` (actor): Request lifecycle management
- `PERequestIDManager` (actor): Request ID pool (0-127)
- `PEChunkAssembler` (actor): Multipart message reassembly
- `PESubscriptionManager` (actor): Auto-reconnecting subscriptions

**Core Types** (organized into domain-focused files):
- `PEResponse` (PEResponse.swift): HTTP-style status + header + body
- `PEError` (PEError.swift): Rich error types with classification
- `PEDeviceHandle`: Bundles MUID + destination (prevents routing mismatches)
- **Types/** directory (R-006 refactoring):
  - `PERequest.swift`: GET/SET/SUBSCRIBE parameters
  - `PEDeviceInfo.swift`: Device metadata (manufacturer, family, model, version)
  - `PEControllerTypes.swift`: Controller-related types
  - `PEHeaderTypes.swift`: PE message headers
  - `PENAKTypes.swift`: NAK status codes
  - `PEChannelInfo.swift`: Channel metadata
  - `PESubscriptionTypes.swift`: Subscription types

**Extension Files**:
- `PEManager+JSON.swift`: Typed API (getJSON/setJSON)
- `PEManager+Legacy.swift`: Deprecated MUID+destination API

**Message Handlers** (R-003 refactoring):
- `handleGetReply`: Processes GET responses
- `handleSetReply`: Processes SET responses
- `handleSubscribeReply`: Processes SUBSCRIBE responses
- `handleNotify`: Processes subscription notifications
- `handleNAK`: Processes negative acknowledgements

**SET Operations Extension** (2026-02-04):
- **Validation/** directory:
  - `PEPayloadValidator.swift`: Pre-SET validation protocol and registry
  - `PESchemaValidator.swift`: JSONSchema-based validation
- **Batch/** directory:
  - `PESetItem.swift`: Batch SET item structure
  - Batch SET methods in `PEManager`: `batchSet()`, `batchSetChannels()`
- **Pipeline/** directory:
  - `PEPipeline.swift`: GET→Transform→SET fluent builder
  - `PEConditionalSet.swift`: Read-modify-write with conditional updates

**Key Features**:
- Request ID allocation (max 128 concurrent)
- Automatic Mcoded7 decoding (with fallback for KORG)
- Per-device inflight limiting
- Batch operations (GET/SET)
- Payload validation before SET
- Pipeline-based GET→Transform→SET workflows
- Conditional SET operations
- Subscription management
- Error classification with `isRetryable`, `isClientError`, `isDeviceError`
- Automatic retry helper: `withPERetry(maxAttempts:operation:)`

**Location**: `Sources/MIDI2PE/`

### MIDI2Kit
**Purpose**: High-Level API - unified client for common use cases

**Key Types**:
- `MIDI2Client` (actor): Main entry point
- `MIDI2Device` (actor): Device representation with caching
- `MIDI2ClientConfiguration`: Centralized configuration
- `MIDI2ClientEvent`: Unified event types
- `DestinationResolver`: Device-specific routing (handles KORG quirks)

**Configuration Presets**:
- `.standard`: Default settings for MIDI 2.0 devices
- `.korgBLEMIDI`: Optimized for KORG Module Pro (warm-up, longer timeouts, fallback)

**Location**: `Sources/MIDI2Kit/`

---

## Important Architectural Patterns

### 1. Actor-Based Concurrency
- All managers are `actor` types for thread-safe isolation
- All data types are `Sendable`
- Async/await throughout (no completion handlers)

### 2. Request ID Management
- PE supports max 128 concurrent requests (0-127)
- Per-device inflight limiting to prevent overwhelming slow devices
- FIFO queue for requests exceeding limits

### 3. Mcoded7 Encoding Handling
PE responses use automatic decoding with fallback:
1. If header explicitly indicates Mcoded7 → decode
2. If body looks like JSON already (starts with `{` or `[`) → use as-is
3. If body decodes successfully as Mcoded7 → use decoded (for KORG)
4. Otherwise use raw body

### 4. Device Destination Resolution
- KORG and other devices have quirks in route mapping
- `DestinationStrategy` pattern handles device-specific logic
- Fallback mechanisms ensure robustness

### 5. Type Safety with PEDeviceHandle
Always use `PEDeviceHandle` (not raw MUID + destination) to prevent routing mismatches:
```swift
// Good
let handle = PEDeviceHandle(muid: muid, destination: dest)
let response = try await peManager.get("DeviceInfo", from: handle)

// Bad - can cause routing errors
let response = try await peManager.get("DeviceInfo", from: muid, destination: dest)
```

---

## KORG Module Pro Compatibility

### Known Issues
- **ResourceList may timeout** due to chunk loss (BLE MIDI physical layer limitation)
- Non-standard PE format (handled automatically by MIDI2Kit)

### Built-in Optimizations (with `.korgBLEMIDI` preset)
- Warm-up request before ResourceList to establish stable BLE connection
- Automatic destination fallback on timeout
- Extended timeout for multi-chunk responses (`multiChunkTimeoutMultiplier`)

### Workaround for ResourceList Failure
```swift
// Access known resources directly instead of using ResourceList
let response = try await client.get("CMList", from: device.muid)
let response = try await client.get("ChannelList", from: device.muid)
```

---

## Logging and Debugging

### Enable/Disable Logging
```swift
// Disable all logs
MIDI2Logger.isEnabled = false

// Enable verbose logging
MIDI2Logger.isVerbose = true
```

### Filter Logs in Console.app
```
subsystem == "com.midi2kit"
```

### Diagnostics API
```swift
// Comprehensive diagnostics
let diag = await client.diagnostics
print(diag)

// Destination resolution details
if let destDiag = await client.lastDestinationDiagnostics {
    print("Tried: \(destDiag.triedOrder)")
    print("Resolved: \(destDiag.resolvedDestination)")
}

// Communication trace
if let trace = await client.lastCommunicationTrace {
    print(trace.description)
}

// JSON decoding diagnostics (PEManager)
if let decodeDiag = await peManager.lastDecodingDiagnostics {
    print("Raw: \(decodeDiag.rawData)")
    print("Preprocessed: \(decodeDiag.preprocessedData)")
    print("Error: \(decodeDiag.parseError)")
}
```

---

## Important Implementation Notes

### Session-Scoped IDs
`MIDISourceID` and `MIDIDestinationID` are CoreMIDI runtime handles (not persistent across sessions). Use `uniqueID` for persistence.

### Request Encapsulation
Use `PERequest` to centralize GET/SET parameters for single API method + testability.

### Error Handling
Rich error types distinguish timeout, NAK, device errors, validation errors:
- `PEError.timeout`: No response within timeout
- `PEError.nak`: Device rejected request (includes status code)
- `PEError.deviceError`: Device-reported error
- `PEError.invalidResponse`: Malformed response

**Error Classification** (Phase 5-2):
```swift
// Check if error is retryable
if error.isRetryable {
    // timeout, transient NAK, transport error
}

// Automatic retry helper
let response = try await withPERetry(maxAttempts: 3) {
    try await peManager.get("DeviceInfo", from: device)
}
```

### Batch Operations

**Batch GET:**
```swift
let responses = await peManager.batchGet(
    ["DeviceInfo", "ResourceList"],
    from: handle
)
// Returns Dictionary<String, Result<PEResponse, Error>>
```

**Batch SET:**
```swift
// Create items
let items = [
    try PESetItem.json(resource: "Volume", value: VolumeInfo(level: 80)),
    try PESetItem.json(resource: "Pan", value: PanInfo(position: 0))
]

// Execute batch SET
let result = try await peManager.batchSet(items, to: device, options: .strict)
// Returns PEBatchSetResponse with per-item results

// Channel-specific batch SET
let channelItems = [
    try PESetItem.json(resource: "ProgramName", value: ["name": "Piano"], channel: 0),
    try PESetItem.json(resource: "ProgramName", value: ["name": "Strings"], channel: 1)
]
let channelResult = try await peManager.batchSetChannels(channelItems, to: device)
```

**Batch Options:**
- `.default`: Parallel, stop on first error
- `.strict`: Parallel, abort all on any error
- `.fast`: Parallel, continue on errors
- `.serial`: Sequential execution

**Pipeline Operations:**
```swift
// GET → Transform → SET pipeline
let result = try await PEPipeline(manager: peManager, device: device)
    .getJSON("ProgramName", as: ProgramName.self)
    .map { $0.name.uppercased() }
    .transform { ProgramName(name: $0) }
    .setJSON("ProgramName")
    .execute()

// Conditional SET (read-modify-write)
let conditional = PEConditionalSet(manager: peManager, device: device)
let result = try await conditional.conditionalSet(
    "Counter",
    as: Counter.self
) { counter in
    guard counter.value < 100 else { return nil } // Skip if >= 100
    return Counter(value: counter.value + 1) // Increment
}
// Returns PEConditionalResult<Counter> (.updated, .skipped, .failed)
```

---

## Testing

### Test Structure
- Tests are in `Tests/MIDI2KitTests/`
- Uses `MockMIDITransport` for hardware-independent testing
- 196 tests (as of 2026-01-30)

### CI Configuration
- GitHub Actions: `.github/workflows/ci.yml`
- Runs on macOS 14 with Xcode 16.x
- Tests both macOS and iOS Simulator builds

---

## Recent Fixes and Refactoring (2026-01-30)

### Phase 0 (P0 - Critical)
1. **peSendStrategy wiring**
   - Configuration now properly passed to PEManager
   - Prevents broadcast-induced timeouts

2. **multiChunkTimeoutMultiplier application**
   - Timeout now actually applied to PE requests
   - Fixes premature timeouts on multi-chunk responses

3. **print() → logger unification**
   - All debug output now goes through MIDI2Logger
   - Eliminates console noise in production

### Phase 1 (P1 - Important)
4. **RobustJSONDecoder safety**
   - No longer corrupts valid pretty JSON
   - Protects URLs like "https://" from comment removal

5. **PEDecodingDiagnostics exposure**
   - `lastDecodingDiagnostics` property now accessible
   - Enables detailed JSON decode error analysis

### Phase 5-1 (Refactoring - Complete)
6. **PESubscriptionHandler extraction** (Sources/MIDI2PE/PESubscriptionHandler.swift)
   - Subscribe/Unsubscribe/Notify handling extracted to dedicated actor
   - Uses callback pattern for actor-to-actor coordination
   - PEManager reduced from 2012 to 1718 lines

### Phase 5-2 (Error Handling - Complete)
7. **PEError classification** (Sources/MIDI2PE/PEError.swift)
   - Added `isRetryable`, `isClientError`, `isDeviceError`, `isTransportError`
   - Added `suggestedRetryDelay` for intelligent backoff
   - Added `withPERetry(maxAttempts:operation:)` helper

### Phase 6 (File Organization - Complete)
8. **PEManager file split**
   - `PEResponse.swift` (70 lines): Response type
   - `PEError.swift` (227 lines): Error types + retry helper
   - `PEManager+JSON.swift` (142 lines): Typed API
   - `PEManager+Legacy.swift` (104 lines): Deprecated API
   - PEManager.swift: 1718 → 1315 lines (29.3% total reduction from original)

### Device Registration Fix
9. **registerFromInquiry flag** (Sources/MIDI2CI/CIManager.swift)
   - Added `CIManagerConfiguration.registerFromInquiry` (default: `false`)
   - When `false`, only devices responding with Discovery Reply (0x71) are registered
   - Prevents false positives from macOS built-in MIDI-CI clients
   - Eliminates PE timeouts caused by non-responding devices

10. **CoreMIDI Bus error fix** (Sources/MIDI2Transport/CoreMIDITransport.swift)
    - Fixed MIDIPacketList handling using `unsafeSequence()`
    - Resolves crash in packet callback

### Refactoring Phase A-D (2026-02-04 - Complete)

**Summary**: Major code organization improvements reducing codebase by ~10% while maintaining 100% test pass rate (319 tests)

11. **R-001: CIMessageParser format parsers testable** (Sources/MIDI2CI/CIMessageParser.swift)
    - Extracted 3 format-specific parsers into separate `internal` functions
    - `parseDiscoveryReply`, `parsePropertyExchangeCapabilities`, `parseEndpointInfo`
    - Added 8 new dedicated format parser tests
    - Improved testability and maintainability

12. **R-002: MIDI2Client timeout+retry consolidation** (Sources/MIDI2Kit/MIDI2Client.swift)
    - Unified `executeWithDestinationFallback<T>` method for all PE operations
    - Eliminated 450 lines of duplicate code across 4 methods:
      - `getDeviceInfo`, `getResourceList`, `get`, `set`
    - Consistent error handling and retry behavior
    - Reduced MIDI2Client from 867 to 467 lines (-46%)

13. **R-003: PEManager handleReceived split** (Sources/MIDI2PE/PEManager.swift)
    - Split 150-line `handleReceived` into 5 focused handlers:
      - `handleGetReply`: GET response processing
      - `handleSetReply`: SET response processing
      - `handleSubscribeReply`: SUBSCRIBE response processing
      - `handleNotify`: Subscription notification processing
      - `handleNAK`: Negative acknowledgement processing
    - Single Responsibility Principle applied
    - Enhanced readability and error handling

14. **R-006: PETypes split into 7 files** (Sources/MIDI2PE/Types/)
    - Reorganized 921-line PETypes.swift into 7 domain-focused files:
      - `PERequest.swift`: Request parameters
      - `PEDeviceInfo.swift`: Device metadata
      - `PEControllerTypes.swift`: Controller-related types
      - `PEHeaderTypes.swift`: PE message headers
      - `PENAKTypes.swift`: NAK status codes
      - `PEChannelInfo.swift`: Channel metadata
      - `PESubscriptionTypes.swift`: Subscription types
    - Improved code navigation and maintainability

15. **Phase C/D: Code cleanup and type-safe events**
    - **R-008**: Removed 5 completed TODO comments from PESubscriptionHandler
      - `startNotificationStream()`, `addPendingContinuation()`, etc.
    - **R-010**: Added type-safe event extraction API to MIDI2ClientEvent
      - Event properties: `discoveredDevice`, `lostDeviceMUID`, etc.
      - Classification: `isDeviceLifecycleEvent`, `isClientStateEvent`
      - AsyncStream extensions: `deviceDiscovered()`, `deviceLost()`, `notifications()`

**Overall Impact**:
- Code reduction: ~10% (20,681 → 18,500 lines)
- Duplicate code: -450 lines
- Improved organization: 12 new focused files
- Test coverage: 319 tests maintained (100% pass)
- Code review: ⭐⭐⭐⭐⭐ 5.0/5

---

## Claude AI Work Rules (日本語対応)

### 絶対ルール：ワークログ記録

- ワークログに時刻を書く前に、必ず `TZ=-9 date "+%Y-%m-%d %H:%M"` コマンドで現在時刻を取得すること
- 推測や概算で時刻を書かないこと
- 各返信の前に、必ず `docs/ClaudeWorklogYYYYMMDD.md` に追記する（Filesystem MCP）
- 追記に成功していない限り、回答本文を書いてはいけない（fail closed）

### 手順（毎ターン必須）

1. `docs/ClaudeWorklogYYYYMMDD.md` の末尾を read して、直近のログを確認
2. 今回のログを append で追記（既存は消さない）
3. 追記直後にもう一度 read して、今追記した内容が末尾にあることを確認
4. 確認できたら回答を書く。回答の末尾に必ず `LOG_OK` と追記した時刻を書く

### ログフォーマット（必ずこの区切りを入れる）

```
---
YYYY-MM-DD HH:MM
作業項目:
追加機能の説明:
決定事項:
次のTODO:
---
```

### 失敗時

- 回答はせず、`LOGGING_FAILED` と失敗理由を1行
- さらに、追記するはずだったログ本文をそのままチャットに貼る（ユーザーが手動で貼れるように）

### その他のルール

- ビルドは実機Midiを優先する
