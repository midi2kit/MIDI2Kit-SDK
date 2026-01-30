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
- `DiscoveredDevice`: Device metadata from discovery
- `CIMessageBuilder`: Constructs MIDI-CI SysEx messages
- `CIMessageParser`: Parses incoming MIDI-CI responses

**Key Features**:
- Automatic Discovery Inquiry broadcasts
- Device lifecycle tracking (discovered → updated → lost)
- Device timeout detection
- Optional responder mode

**Location**: `Sources/MIDI2CI/`

### MIDI2PE
**Purpose**: Property Exchange (GET/SET device properties, subscriptions)

**Key Actors**:
- `PEManager` (actor): High-level PE API
- `PETransactionManager` (actor): Request lifecycle management
- `PERequestIDManager` (actor): Request ID pool (0-127)
- `PEChunkAssembler` (actor): Multipart message reassembly
- `PESubscriptionManager` (actor): Auto-reconnecting subscriptions

**Core Types**:
- `PEDeviceHandle`: Bundles MUID + destination (prevents routing mismatches)
- `PERequest`: GET/SET/SUBSCRIBE parameters
- `PEResponse`: HTTP-style status + header + body
- `PEError`: Rich error types (timeout, NAK, deviceError, etc.)

**Key Features**:
- Request ID allocation (max 128 concurrent)
- Automatic Mcoded7 decoding (with fallback for KORG)
- Per-device inflight limiting
- Batch operations
- Subscription management

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

### Batch Operations
```swift
let responses = await peManager.batchGet(
    ["DeviceInfo", "ResourceList"],
    from: handle
)
// Returns Dictionary<String, Result<PEResponse, Error>>
```

---

## Testing

### Test Structure
- Tests are in `Tests/MIDI2KitTests/`
- Uses `MockMIDITransport` for hardware-independent testing
- 188 tests (as of latest run)

### CI Configuration
- GitHub Actions: `.github/workflows/ci.yml`
- Runs on macOS 14 with Xcode 16.x
- Tests both macOS and iOS Simulator builds

---

## Recent Critical Fixes (2026-01-30)

### Phase 0 (P0 - Critical)
1. **peSendStrategy wiring** (Sources/MIDI2PE/PEManager.swift:337, Sources/MIDI2Kit/HighLevelAPI/MIDI2Client.swift:177)
   - Configuration now properly passed to PEManager
   - Prevents broadcast-induced timeouts

2. **multiChunkTimeoutMultiplier application** (Sources/MIDI2PE/PEManager.swift:738,1001,1051)
   - Timeout now actually applied to PE requests
   - Fixes premature timeouts on multi-chunk responses

3. **print() → logger unification** (Sources/MIDI2PE/PEChunkAssembler.swift)
   - All debug output now goes through MIDI2Logger
   - Eliminates console noise in production

### Phase 1 (P1 - Important)
4. **RobustJSONDecoder safety** (Sources/MIDI2Core/JSON/RobustJSONDecoder.swift:204,278)
   - No longer corrupts valid pretty JSON
   - Protects URLs like "https://" from comment removal

5. **PEDecodingDiagnostics exposure** (Sources/MIDI2PE/PEManager.swift:293)
   - `lastDecodingDiagnostics` property now accessible
   - Enables detailed JSON decode error analysis

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
