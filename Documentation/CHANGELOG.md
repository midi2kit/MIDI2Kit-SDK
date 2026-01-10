# MIDI2Kit Changelog

## 2026-01-10 (Session 3)

### Fixed

#### PEManager.stopReceiving() - RequestID Leak & Unsafe Mutation
- **RequestID leak**: Now calls `transactionManager.cancelAll()` to release all Request IDs on stop
- **Unsafe dictionary mutation**: Fixed iterating `pendingContinuations` while mutating
  ```swift
  // Before (unsafe)
  for (requestID, continuation) in pendingContinuations {
      pendingContinuations.removeValue(forKey: requestID)  // ❌
  }
  
  // After (safe)
  for continuation in pendingContinuations.values {
      continuation.resume(throwing: PEError.cancelled)
  }
  pendingContinuations.removeAll()
  ```

#### CoreMIDITransport.handlePacketList() - Packet Order for SysEx Assembly
- **Problem**: Each packet spawned separate Task → order not guaranteed → SysEx corruption
- **Fix**: Collect all packets first, then process sequentially in single Task
  ```swift
  // Before (order not guaranteed)
  for packet in packets {
      Task { await processReceivedData(data) }  // ❌ Race condition
  }
  
  // After (order guaranteed)
  var allPacketData: [[UInt8]] = []
  for packet in packets { allPacketData.append(data) }
  Task {
      for data in allPacketData { await processReceivedData(data) }  // ✅
  }
  ```

#### PETransactionManager.waitForCompletion() - Double-Call Continuation Overwrite
- **Problem**: Multiple calls for same requestID would overwrite previous continuation
- **Fix**: Return `.cancelled` immediately if already waiting
  ```swift
  if completionHandlers[requestID] != nil {
      return .cancelled  // Prevent overwrite
  }
  ```

#### CoreMIDITransport - sourceID Always nil
- **Problem**: `MIDIReceivedData.sourceID` was never populated
- **Fix**: Pass source as `connRefCon` in `MIDIPortConnectSource`, extract in callback
  ```swift
  // Connect with source ref as connRefCon
  let connRefCon = UnsafeMutableRawPointer(bitPattern: UInt(sourceRef))
  MIDIPortConnectSource(inputPort, sourceRef, connRefCon)
  
  // Extract in callback
  MIDIInputPortCreateWithBlock(...) { packetList, srcConnRefCon in
      let sourceRef = MIDIEndpointRef(UInt(bitPattern: srcConnRefCon))
      ...
  }
  ```

### Changed

#### PEManager - Unified Timeout Management
- **Problem**: Dual timeout management (PETransactionManager.startMonitoring + per-request Task)
- **Fix**: Removed `monitorHandle`, centralized timeout in `PEManager.timeoutTasks`
- Responsibilities now clearly separated:
  - `PETransactionManager`: RequestID lifecycle, chunk assembly
  - `PEManager`: Response delivery, timeout-to-continuation mapping

### Added

#### SysExAssemblerTests (18 tests)
- Complete SysEx in single/multiple packets
- Fragmented SysEx across 2-3 packets
- Order sensitivity tests demonstrating corruption on wrong order
- Corruption handling (F0 before F7)
- Large SysEx message assembly (1000+ bytes)

#### PETransactionManager waitForCompletion Tests (4 tests)
- Returns result on complete
- Returns cancelled for unknown requestID
- Duplicate call returns cancelled
- Does not leak continuation on duplicate call

### Test Coverage

- **121 tests total**, all passing (up from 95)
- Previously disabled "GET times out when no reply" test now enabled and passing
- SysExAssembler Tests: 14 tests
- CoreMIDITransport Packet Order Tests: 4 tests
- PETransactionManager Tests: 24 tests (up from 11)
- PEManager Tests: 13 tests (up from 7)

---

## 2026-01-10 (Session 1 & 2)

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
