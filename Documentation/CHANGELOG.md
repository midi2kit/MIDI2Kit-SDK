# MIDI2Kit Changelog

## 2026-01-10

### Added

#### PEMonitorHandle - Automatic Timeout Monitoring
- New `PEMonitorHandle` class for lifecycle-based timeout monitoring
- `startMonitoring()` returns handle - **hold this handle to keep monitoring active**
- Handle deallocation automatically stops monitoring and cancels Task
- Eliminates need for manual `checkTimeouts()` timer setup
- Idempotent: calling `startMonitoring()` multiple times returns same handle

```swift
// Start monitoring - HOLD the handle!
let handle = await transactionManager.startMonitoring()

// Monitoring runs automatically in background...

// Stop explicitly
await handle.stop()

// Or just release handle - monitoring stops automatically
// handle = nil
```

#### MIDI2Logger - Configurable Logging System
- `MIDI2LogLevel`: debug, info, notice, warning, error, fault
- `MIDI2Logger` protocol with convenience methods
- Built-in implementations:
  - `NullMIDI2Logger`: Silent (default)
  - `StdoutMIDI2Logger`: Development/debugging
  - `OSLogMIDI2Logger`: Production (Apple's os.log)
  - `CompositeMIDI2Logger`: Forward to multiple loggers

```swift
// Enable logging for debugging
let logger = StdoutMIDI2Logger(minLevel: .debug)
let manager = PETransactionManager(logger: logger)
```

#### CIMessageParser Tests
- 24 new boundary condition tests for parseNAK, parseDiscoveryReply, parsePEReply, etc.
- Fixed parseNAK bounds check (payload[9] requires count >= 10)

### Fixed

#### PEMonitorHandle Lifecycle
- Fixed retain cycle: Task now uses `[weak self]` and shared `MonitorRunningState`
- `isActive` correctly reflects Task termination (not just cancellation)
- Manager can be deallocated while monitoring - Task exits cleanly

#### CoreMIDITransport
- Added `MIDITransportError.packetListFull` case
- Fixed MIDIPacketListAdd failure detection

### Changed

- `PEMonitoringConfiguration.autoStart` removed - use `startMonitoring()` explicitly
- `PEMonitoringConfiguration.checkInterval` is now `let` (immutable)

### Test Coverage

- **86 tests total**, all passing
- PETransactionManager: 15 tests (including 9 monitor handle lifecycle tests)
- CIMessageParser: 24 tests
- CIManager: 6 tests
- Mcoded7: 10 tests
- MUID: 10 tests
- PEChunkAssembler: 7 tests
- PERequestIDManager: 14 tests
