# MIDI2Kit API Reference

## MIDI2Core

### MUID

28-bit MIDI Unique Identifier used in MIDI-CI.

```swift
public struct MUID: Hashable, Sendable, Identifiable, Codable {
    /// Raw 28-bit value
    public let value: UInt32
    
    /// Broadcast MUID (0x0FFFFFFF)
    public static let broadcast: MUID
    
    /// Reserved/Invalid MUID (0x00000000)
    public static let reserved: MUID
    
    /// Create from raw value (must be <= 0x0FFFFFFF)
    public init?(rawValue: UInt32)
    
    /// Create from 4 x 7-bit bytes (LSB first)
    public init(bytes: (UInt8, UInt8, UInt8, UInt8))
    
    /// Create from byte array
    public init?(from bytes: [UInt8], offset: Int = 0)
    
    /// Generate random valid MUID
    public static func random() -> MUID
    
    /// Convert to 4 bytes for SysEx transmission
    public var bytes: [UInt8]
    
    /// Check if broadcast
    public var isBroadcast: Bool
    
    /// Check if reserved
    public var isReserved: Bool
}
```

### ManufacturerID

```swift
public enum ManufacturerID: Hashable, Sendable, Codable {
    case standard(UInt8)           // 1-byte ID
    case extended(UInt8, UInt8)    // 3-byte ID (0x00, b1, b2)
    
    // Known manufacturers
    public static let roland: ManufacturerID
    public static let korg: ManufacturerID
    public static let yamaha: ManufacturerID
    
    /// Create from 3 SysEx bytes
    public init(bytes: (UInt8, UInt8, UInt8))
    
    /// Convert to 3 bytes
    public var bytes: [UInt8]
    
    /// Human-readable name (if known)
    public var name: String?
}
```

### DeviceIdentity

```swift
public struct DeviceIdentity: Hashable, Sendable, Codable {
    public let manufacturerID: ManufacturerID
    public let familyID: UInt16
    public let modelID: UInt16
    public let versionID: UInt32
    
    /// Create from 11 SysEx bytes
    public init?(from bytes: [UInt8], offset: Int = 0)
    
    /// Convert to 11 bytes
    public var bytes: [UInt8]
    
    /// Version as string (e.g., "1.2.3.4")
    public var versionString: String
}
```

### Mcoded7

8-bit ↔ 7-bit encoding for SysEx transmission.

```swift
public enum Mcoded7 {
    /// Encode 8-bit data to 7-bit safe format
    public static func encode(_ data: Data) -> Data
    
    /// Decode 7-bit data back to 8-bit
    public static func decode(_ data: Data) -> Data?
    
    /// Calculate encoded size
    public static func encodedSize(for originalSize: Int) -> Int
    
    /// Calculate decoded size
    public static func decodedSize(for encodedSize: Int) -> Int
}
```

### CIMessageType

```swift
public enum CIMessageType: UInt8, Sendable, CaseIterable {
    // Discovery
    case discoveryInquiry = 0x70
    case discoveryReply = 0x71
    case invalidateMUID = 0x7E
    case nak = 0x7F
    case ack = 0x7D
    
    // Property Exchange
    case peCapabilityInquiry = 0x30
    case peCapabilityReply = 0x31
    case peGetInquiry = 0x34
    case peGetReply = 0x35
    case peSetInquiry = 0x36
    case peSetReply = 0x37
    case peSubscribe = 0x38
    case peSubscribeReply = 0x39
    case peNotify = 0x3F
    
    // ... and more
}
```

### CategorySupport

```swift
public struct CategorySupport: OptionSet, Sendable {
    public static let protocolNegotiation: CategorySupport
    public static let profileConfiguration: CategorySupport
    public static let propertyExchange: CategorySupport
    public static let processInquiry: CategorySupport
    public static let all: CategorySupport
}
```

### MIDI2Logger

Configurable logging system.

```swift
/// Log levels (severity order)
public enum MIDI2LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case notice = 2
    case warning = 3
    case error = 4
    case fault = 5
}

/// Logger protocol
public protocol MIDI2Logger: Sendable {
    var minLevel: MIDI2LogLevel { get }
    func log(_ level: MIDI2LogLevel, _ message: String, category: String)
    
    // Convenience methods
    func debug(_ message: String, category: String)
    func info(_ message: String, category: String)
    func warning(_ message: String, category: String)
    func error(_ message: String, category: String)
}
```

**Built-in Implementations:**

```swift
/// Silent logger (default)
public struct NullMIDI2Logger: MIDI2Logger

/// Print to stdout
public struct StdoutMIDI2Logger: MIDI2Logger {
    public init(minLevel: MIDI2LogLevel = .debug)
}

/// Apple's os.log
public struct OSLogMIDI2Logger: MIDI2Logger {
    public init(subsystem: String, minLevel: MIDI2LogLevel = .info)
}

/// Forward to multiple loggers
public struct CompositeMIDI2Logger: MIDI2Logger {
    public init(_ loggers: [any MIDI2Logger])
}
```

**Usage:**
```swift
// Development: verbose logging
let logger = StdoutMIDI2Logger(minLevel: .debug)
let manager = PETransactionManager(logger: logger)

// Production: warnings and above
let logger = OSLogMIDI2Logger(subsystem: "com.myapp.midi", minLevel: .warning)
```

---

## MIDI2CI

### CIMessageBuilder

Builds MIDI-CI SysEx messages.

```swift
public enum CIMessageBuilder {
    /// Build Discovery Inquiry (broadcast)
    public static func discoveryInquiry(
        sourceMUID: MUID,
        deviceIdentity: DeviceIdentity = ...,
        categorySupport: CategorySupport = .propertyExchange,
        maxSysExSize: UInt32 = 0,
        initiatorOutputPath: UInt8 = 0
    ) -> [UInt8]
    
    /// Build Discovery Reply
    public static func discoveryReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        deviceIdentity: DeviceIdentity,
        categorySupport: CategorySupport,
        ...
    ) -> [UInt8]
    
    /// Build PE Capability Inquiry
    public static func peCapabilityInquiry(
        sourceMUID: MUID,
        destinationMUID: MUID,
        numSimultaneousRequests: UInt8 = 1,
        ...
    ) -> [UInt8]
    
    /// Build PE Get Inquiry
    public static func peGetInquiry(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        headerData: Data
    ) -> [UInt8]
    
    /// Build PE Set Inquiry
    public static func peSetInquiry(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        headerData: Data,
        propertyData: Data,
        numChunks: Int = 1,
        thisChunk: Int = 1
    ) -> [UInt8]
    
    // Header builders
    public static func resourceRequestHeader(resource: String) -> Data
    public static func channelResourceHeader(resource: String, channel: Int) -> Data
    public static func paginatedRequestHeader(resource: String, offset: Int, limit: Int) -> Data
}
```

### CIMessageParser

Parses MIDI-CI SysEx messages.

```swift
public enum CIMessageParser {
    public struct ParsedMessage: Sendable {
        public let messageType: CIMessageType
        public let ciVersion: UInt8
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let payload: [UInt8]
    }
    
    /// Parse complete SysEx message
    public static func parse(_ data: [UInt8]) -> ParsedMessage?
    
    public struct DiscoveryReplyPayload: Sendable {
        public let identity: DeviceIdentity
        public let categorySupport: CategorySupport
        public let maxSysExSize: UInt32
        public let initiatorOutputPath: UInt8
        public let functionBlock: UInt8
    }
    
    /// Parse Discovery Reply payload
    public static func parseDiscoveryReply(_ payload: [UInt8]) -> DiscoveryReplyPayload?
    
    public struct PECapabilityReplyPayload: Sendable {
        public let numSimultaneousRequests: UInt8
        public let majorVersion: UInt8
        public let minorVersion: UInt8
    }
    
    /// Parse PE Capability Reply
    public static func parsePECapabilityReply(_ payload: [UInt8]) -> PECapabilityReplyPayload?
    
    public struct PEReplyPayload: Sendable {
        public let requestID: UInt8
        public let headerData: Data
        public let propertyData: Data
        public let numChunks: Int
        public let thisChunk: Int
    }
    
    /// Parse PE Get/Set Reply
    public static func parsePEReply(_ payload: [UInt8]) -> PEReplyPayload?
}
```

### DiscoveredDevice

```swift
public struct DiscoveredDevice: Sendable, Identifiable, Hashable {
    public var id: MUID { muid }
    
    public let muid: MUID
    public let identity: DeviceIdentity
    public let categorySupport: CategorySupport
    public let maxSysExSize: UInt32
    public let initiatorOutputPath: UInt8
    public let functionBlock: UInt8
    
    public var supportsPropertyExchange: Bool
    public var supportsProfileConfiguration: Bool
    public var supportsProtocolNegotiation: Bool
    public var displayName: String
}
```

---

## MIDI2PE

### PEResource

```swift
public enum PEResource: String, Sendable, CaseIterable {
    case resourceList = "ResourceList"
    case deviceInfo = "DeviceInfo"
    case channelList = "ChannelList"
    case channelControllerList = "ChCtrlList"
    case programList = "ProgramList"
    case currentProgram = "CurrentProgram"
    case state = "State"
    case localOn = "LocalOn"
    case jsonSchema = "JSONSchema"
    
    // Vendor extensions
    case xParameterList = "X-ParameterList"
    case xCustomUI = "X-CustomUI"
}
```

### PEDeviceInfo

```swift
public struct PEDeviceInfo: Sendable, Codable {
    public let manufacturerName: String?
    public let productName: String?
    public let productInstanceID: String?
    public let softwareVersion: String?
    public let familyName: String?
    public let modelName: String?
    
    public var displayName: String
}
```

### PEControllerDef

```swift
public struct PEControllerDef: Sendable, Codable, Identifiable {
    public var id: Int { ctrlIndex }
    
    public let ctrlIndex: Int
    public let name: String?
    public let ctrlType: String?
    public let minValue: Int?
    public let maxValue: Int?
    public let defaultValue: Int?
    public let stepCount: Int?
    public let valueList: [String]?
    public let units: String?
    
    public var displayName: String
}
```

### PEChunkAssembler

```swift
public enum PEChunkResult: Sendable {
    case incomplete(received: Int, total: Int)
    case complete(header: Data, body: Data)
    case timeout(requestID: UInt8, received: Int, total: Int, partial: Data?)
}

public struct PEChunkAssembler: Sendable {
    public init(timeout: TimeInterval = 3.0)
    
    /// Add received chunk
    public mutating func addChunk(
        requestID: UInt8,
        thisChunk: Int,
        numChunks: Int,
        headerData: Data,
        propertyData: Data,
        resource: String = ""
    ) -> PEChunkResult
    
    /// Check for timed-out assemblies
    public mutating func checkTimeouts() -> [PEChunkResult]
    
    /// Cancel pending assembly
    public mutating func cancel(requestID: UInt8)
    
    public var hasPending: Bool
    public var pendingCount: Int
}
```

### PERequestIDManager

```swift
public struct PERequestIDManager: Sendable {
    public static let maxRequestID: UInt8 = 127
    
    public init()
    
    /// Acquire next available ID (nil if exhausted)
    public mutating func acquire() -> UInt8?
    
    /// Release ID for reuse
    public mutating func release(_ id: UInt8)
    
    /// Release multiple IDs
    public mutating func release(_ ids: [UInt8])
    
    public func isInUse(_ id: UInt8) -> Bool
    public var usedCount: Int
    public var availableCount: Int
    public mutating func releaseAll()
}
```

### PEMonitorHandle

**Handle for automatic timeout monitoring.**

```swift
public final class PEMonitorHandle: Sendable {
    /// Check if monitoring is still active
    public var isActive: Bool
    
    /// Explicitly stop monitoring
    public func stop() async
    
    // deinit automatically cancels monitoring
}
```

**Usage:**
```swift
class MyManager {
    var handle: PEMonitorHandle?  // MUST hold this!
    
    func start() async {
        handle = await transactionManager.startMonitoring()
    }
}
```

### PETransactionManager

**Critical component for preventing Request ID leaks.**

```swift
public actor PETransactionManager {
    public static let defaultTimeout: TimeInterval = 5.0
    public static let warningThreshold: Int = 100
    
    public init(
        logger: any MIDI2Logger = NullMIDI2Logger(),
        monitoringConfig: PEMonitoringConfiguration = .default
    )
    
    // Monitoring
    
    /// Start automatic timeout monitoring
    /// Returns handle - hold this to keep monitoring active
    @discardableResult
    public func startMonitoring() -> PEMonitorHandle
    
    /// Whether monitoring is currently active
    public var isMonitoring: Bool
    
    // Lifecycle
    
    /// Begin transaction (returns nil if exhausted)
    public func begin(
        resource: String,
        destinationMUID: MUID,
        timeout: TimeInterval = defaultTimeout
    ) -> UInt8?
    
    /// Complete successfully
    public func complete(requestID: UInt8, header: Data, body: Data)
    
    /// Complete with error
    public func completeWithError(requestID: UInt8, status: Int, message: String? = nil)
    
    /// Cancel transaction
    public func cancel(requestID: UInt8)
    
    /// Cancel all for device
    public func cancelAll(for muid: MUID)
    
    /// Cancel all
    public func cancelAll()
    
    // Chunk handling
    
    /// Process received chunk
    public func processChunk(
        requestID: UInt8,
        thisChunk: Int,
        numChunks: Int,
        headerData: Data,
        propertyData: Data
    ) -> PEChunkResult
    
    // Timeout
    
    /// Check and cleanup timed-out transactions
    @discardableResult
    public func checkTimeouts() -> [UInt8]
    
    // Async
    
    /// Wait for transaction completion
    public func waitForCompletion(requestID: UInt8) async -> PETransactionResult
    
    // Monitoring
    
    public var activeCount: Int
    public var availableIDs: Int
    public var isNearExhaustion: Bool
    public var diagnostics: String
}

public enum PETransactionResult: Sendable {
    case success(header: Data, body: Data)
    case error(status: Int, message: String?)
    case timeout
    case cancelled
}
```

---

## MIDI2Transport

### MIDITransport Protocol

```swift
public protocol MIDITransport: Sendable {
    func send(_ data: [UInt8], to destination: MIDIDestinationID) async throws
    
    var received: AsyncStream<MIDIReceivedData> { get }
    var sources: [MIDISourceInfo] { get async }
    var destinations: [MIDIDestinationInfo] { get async }
    var setupChanged: AsyncStream<Void> { get }
    
    func connect(to source: MIDISourceID) async throws
    func disconnect(from source: MIDISourceID) async throws
    func connectToAllSources() async throws
}
```

### CoreMIDITransport

```swift
public final class CoreMIDITransport: MIDITransport {
    public init(clientName: String = "MIDI2Kit") throws
    
    // MIDITransport conformance
    public func send(_ data: [UInt8], to destination: MIDIDestinationID) async throws
    public var received: AsyncStream<MIDIReceivedData>
    public var sources: [MIDISourceInfo] { get async }
    public var destinations: [MIDIDestinationInfo] { get async }
    public var setupChanged: AsyncStream<Void>
    
    /// Connect (idempotent - safe to call multiple times)
    public func connect(to source: MIDISourceID) async throws
    
    /// Disconnect
    public func disconnect(from source: MIDISourceID) async throws
    
    /// Differential connect - only new sources
    public func connectToAllSources() async throws
    
    /// Full reconnect - disconnect all, then connect all
    public func reconnectAllSources() async throws
    
    /// Disconnect all sources
    public func disconnectAllSources() async
    
    /// Connection state
    public var connectedSourceCount: Int { get async }
    public func isConnected(to source: MIDISourceID) async -> Bool
}
```

### MockMIDITransport

For testing without hardware.

```swift
public actor MockMIDITransport: MIDITransport {
    public init()
    
    // MIDITransport conformance
    // ...
    
    // Test helpers
    
    /// Inject received data (simulates device)
    public func injectReceived(_ data: [UInt8], from source: MIDISourceID? = nil)
    
    /// Inject multiple messages
    public func injectReceived(_ messages: [[UInt8]], from source: MIDISourceID? = nil)
    
    /// Notify setup changed
    public func notifySetupChanged()
    
    /// Sent messages
    public var sentMessages: [SentMessage]
    public var lastSentMessage: SentMessage?
    
    /// Clear sent history
    public func clearSentMessages()
    
    /// Check if CI message type was sent
    public func wasSent(ciMessageType: UInt8) -> Bool
    
    // Mock configuration
    public var mockSources: [MIDISourceInfo]
    public var mockDestinations: [MIDIDestinationInfo]
}
```

### Data Types

```swift
public struct MIDISourceID: Sendable, Hashable {
    public let value: UInt32
    public init(_ value: UInt32)
}

public struct MIDIDestinationID: Sendable, Hashable {
    public let value: UInt32
    public init(_ value: UInt32)
}

public struct MIDISourceInfo: Sendable, Identifiable, Hashable {
    public var id: UInt32 { sourceID.value }
    public let sourceID: MIDISourceID
    public let name: String
    public let manufacturer: String?
    public let isOnline: Bool
}

public struct MIDIDestinationInfo: Sendable, Identifiable, Hashable {
    public var id: UInt32 { destinationID.value }
    public let destinationID: MIDIDestinationID
    public let name: String
    public let manufacturer: String?
    public let isOnline: Bool
}

public struct MIDIReceivedData: Sendable {
    public let data: [UInt8]
    public let sourceID: MIDISourceID?
    public let timestamp: UInt64
}
```

### Errors

```swift
public enum MIDITransportError: Error, Sendable {
    case notInitialized
    case clientCreationFailed(Int32)
    case portCreationFailed(Int32)
    case sendFailed(Int32)
    case connectionFailed(Int32)
    case destinationNotFound(UInt32)
    case sourceNotFound(UInt32)
}
```
