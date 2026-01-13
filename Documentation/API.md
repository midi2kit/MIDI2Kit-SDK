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

### MIDITracer

Ring buffer for MIDI message tracing and diagnostics.

```swift
/// Direction of MIDI message
public enum MIDIDirection: String, Sendable {
    case send = "→"
    case receive = "←"
}

/// A single trace entry
public struct MIDITraceEntry: Sendable {
    public let timestamp: Date
    public let direction: MIDIDirection
    public let endpoint: UInt32
    public let endpointName: String?
    public let data: [UInt8]
    public let label: String?
    
    /// Format as hex string
    public var hexString: String
    
    /// Formatted timestamp (HH:mm:ss.SSS)
    public var formattedTime: String
    
    /// Single-line description
    public var oneLine: String
    
    /// Auto-detect label from SysEx content
    public static func detectLabel(for data: [UInt8]) -> String?
}

/// Thread-safe ring buffer for MIDI message tracing
public final class MIDITracer: @unchecked Sendable {
    /// Maximum entries to retain
    public let capacity: Int
    
    /// Whether tracing is enabled
    public var isEnabled: Bool
    
    /// Initialize with capacity (default: 200)
    public init(capacity: Int = 200)
    
    // Recording
    public func record(direction: MIDIDirection, endpoint: UInt32, data: [UInt8], label: String? = nil)
    public func recordSend(to endpoint: UInt32, data: [UInt8], label: String? = nil)
    public func recordReceive(from endpoint: UInt32, data: [UInt8], label: String? = nil)
    
    // Retrieval
    public var entries: [MIDITraceEntry]
    public func lastEntries(_ n: Int) -> [MIDITraceEntry]
    public func entries(direction: MIDIDirection) -> [MIDITraceEntry]
    public func entries(endpoint: UInt32) -> [MIDITraceEntry]
    public func entries(from start: Date, to end: Date) -> [MIDITraceEntry]
    public var entryCount: Int
    
    // Dump
    public func dump() -> String
    public func dump(last n: Int) -> String
    public func dumpFull() -> String
    public func exportJSON() throws -> Data
    
    // Clear
    public func clear()
    
    // Shared global tracer
    public static var shared: MIDITracer
}
```

**Usage:**
```swift
let tracer = MIDITracer(capacity: 100)

// Record messages
tracer.recordSend(to: destination.value, data: message)
tracer.recordReceive(from: source.value, data: response)

// Dump recent messages
print(tracer.dump(last: 20))

// Export for analysis
let json = try tracer.exportJSON()

// Auto-detected labels for MIDI-CI messages
let label = MIDITraceEntry.detectLabel(for: sysexData)
// → "Discovery", "PE GET", "PE SET Reply", etc.
```

---

### UMP Types

MIDI 2.0 Universal MIDI Packet type definitions.

```swift
/// UMP message types (upper 4 bits of first word)
public enum UMPMessageType: UInt8, Sendable, CaseIterable {
    case utility = 0x0           // 32-bit: NOOP, JR Clock/Timestamp
    case system = 0x1            // 32-bit: System Real Time/Common
    case midi1ChannelVoice = 0x2 // 32-bit: MIDI 1.0 wrapped
    case data64 = 0x3            // 64-bit: SysEx7
    case midi2ChannelVoice = 0x4 // 64-bit: MIDI 2.0 Channel Voice
    case data128 = 0x5           // 128-bit: SysEx8, Mixed Data Set
    case flexData = 0xD          // 128-bit: Flex Data
    case umpStream = 0xF         // 128-bit: UMP Stream
    
    /// Number of 32-bit words in this message type
    public var wordCount: Int
}

/// MIDI 2.0 Channel Voice status codes
public enum MIDI2ChannelVoiceStatus: UInt8, Sendable, CaseIterable {
    case registeredPerNoteController = 0x0
    case assignablePerNoteController = 0x1
    case registeredController = 0x2       // RPN
    case assignableController = 0x3       // NRPN
    case relativeRegisteredController = 0x4
    case relativeAssignableController = 0x5
    case perNotePitchBend = 0x6
    case noteOff = 0x8
    case noteOn = 0x9
    case polyPressure = 0xA
    case controlChange = 0xB
    case programChange = 0xC
    case channelPressure = 0xD
    case pitchBend = 0xE
    case perNoteManagement = 0xF
}

/// Note attribute types for MIDI 2.0 Note On/Off
public enum NoteAttributeType: UInt8, Sendable {
    case none = 0x0
    case manufacturerSpecific = 0x1
    case profileSpecific = 0x2
    case pitch7_9 = 0x3
}

/// UMP Group (0-15)
public struct UMPGroup: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt8
    public static let group0: UMPGroup
}

/// MIDI Channel (0-15)
public struct MIDIChannel: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt8
    public var displayValue: Int  // 1-16
}

/// Bank selection for Program Change
public struct ProgramBank: Sendable, Hashable {
    public let msb: UInt8
    public let lsb: UInt8
    public var combined: UInt16
    public init(msb: UInt8, lsb: UInt8)
    public init(combined: UInt16)
}

/// Controller bank and index for RPN/NRPN
public struct ControllerAddress: Sendable, Hashable {
    public let bank: UInt8
    public let index: UInt8
}

/// Common RPN addresses
public enum RegisteredController {
    public static let pitchBendSensitivity: ControllerAddress  // Bank 0, Index 0
    public static let channelFineTuning: ControllerAddress     // Bank 0, Index 1
    public static let channelCoarseTuning: ControllerAddress   // Bank 0, Index 2
    public static let mpeConfiguration: ControllerAddress      // Bank 0, Index 6
}

/// Pitch bend constants
public enum PitchBendValue {
    public static let minimum: UInt32  // 0x00000000
    public static let center: UInt32   // 0x80000000
    public static let maximum: UInt32  // 0xFFFFFFFF
    public static let minimum14: UInt16  // 0x0000 (MIDI 1.0)
    public static let center14: UInt16   // 0x2000 (MIDI 1.0)
    public static let maximum14: UInt16  // 0x3FFF (MIDI 1.0)
}
```

### UMPValueScaling

Value scaling utilities between MIDI 1.0 and 2.0 resolutions.

```swift
public enum UMPValueScaling {
    /// Scale 7-bit (0-127) to 32-bit
    public static func scale7To32(_ value7: UInt8) -> UInt32
    
    /// Scale 14-bit (0-16383) to 32-bit
    public static func scale14To32(_ value14: UInt16) -> UInt32
    
    /// Scale 32-bit to 7-bit
    public static func scale32To7(_ value32: UInt32) -> UInt8
    
    /// Scale 32-bit to 14-bit
    public static func scale32To14(_ value32: UInt32) -> UInt16
    
    /// Scale normalized (0.0-1.0) to 32-bit
    public static func normalizedTo32(_ normalized: Double) -> UInt32
    
    /// Scale 32-bit to normalized (0.0-1.0)
    public static func to32Normalized(_ value32: UInt32) -> Double
    
    /// Scale 7-bit velocity to 16-bit
    public static func scaleVelocity7To16(_ velocity7: UInt8) -> UInt16
    
    /// Scale 16-bit velocity to 7-bit
    public static func scaleVelocity16To7(_ velocity16: UInt16) -> UInt8
}
```

---

### UMPBuilder

Builder for constructing MIDI 2.0 UMP messages.

```swift
public enum UMPBuilder {
    // MIDI 2.0 Channel Voice Messages (64-bit)
    
    /// Control Change with 32-bit value
    public static func midi2ControlChange(
        group: UInt8, channel: UInt8, controller: UInt8, value: UInt32
    ) -> [UInt32]
    
    /// Control Change with normalized value (0.0-1.0)
    public static func midi2ControlChangeNormalized(
        group: UInt8, channel: UInt8, controller: UInt8, normalizedValue: Double
    ) -> [UInt32]
    
    /// Control Change with 7-bit value (auto-scaled)
    public static func midi2ControlChange7(
        group: UInt8, channel: UInt8, controller: UInt8, value7: UInt8
    ) -> [UInt32]
    
    /// Program Change with optional bank
    public static func midi2ProgramChange(
        group: UInt8, channel: UInt8, program: UInt8, bank: ProgramBank? = nil
    ) -> [UInt32]
    
    /// Note On with 16-bit velocity
    public static func midi2NoteOn(
        group: UInt8, channel: UInt8, note: UInt8, velocity: UInt16,
        attributeType: NoteAttributeType = .none, attributeData: UInt16 = 0
    ) -> [UInt32]
    
    /// Note On with 7-bit velocity (auto-scaled)
    public static func midi2NoteOn7(
        group: UInt8, channel: UInt8, note: UInt8, velocity7: UInt8
    ) -> [UInt32]
    
    /// Note Off
    public static func midi2NoteOff(
        group: UInt8, channel: UInt8, note: UInt8, velocity: UInt16 = 0,
        attributeType: NoteAttributeType = .none, attributeData: UInt16 = 0
    ) -> [UInt32]
    
    /// Pitch Bend with 32-bit value
    public static func midi2PitchBend(
        group: UInt8, channel: UInt8, value: UInt32
    ) -> [UInt32]
    
    /// Pitch Bend with 14-bit value (auto-scaled)
    public static func midi2PitchBend14(
        group: UInt8, channel: UInt8, value14: UInt16
    ) -> [UInt32]
    
    /// Channel Pressure
    public static func midi2ChannelPressure(
        group: UInt8, channel: UInt8, pressure: UInt32
    ) -> [UInt32]
    
    /// Poly Pressure
    public static func midi2PolyPressure(
        group: UInt8, channel: UInt8, note: UInt8, pressure: UInt32
    ) -> [UInt32]
    
    /// Per-Note Pitch Bend
    public static func midi2PerNotePitchBend(
        group: UInt8, channel: UInt8, note: UInt8, value: UInt32
    ) -> [UInt32]
    
    /// Registered Controller (RPN)
    public static func midi2RegisteredController(
        group: UInt8, channel: UInt8, address: ControllerAddress, value: UInt32
    ) -> [UInt32]
    
    /// Assignable Controller (NRPN)
    public static func midi2AssignableController(
        group: UInt8, channel: UInt8, address: ControllerAddress, value: UInt32
    ) -> [UInt32]
    
    /// Per-Note Management
    public static func midi2PerNoteManagement(
        group: UInt8, channel: UInt8, note: UInt8, detach: Bool = false, reset: Bool = false
    ) -> [UInt32]
    
    // MIDI 1.0 over UMP (32-bit)
    
    /// MIDI 1.0 Control Change
    public static func midi1ControlChange(
        group: UInt8, channel: UInt8, controller: UInt8, value: UInt8
    ) -> [UInt32]
    
    /// MIDI 1.0 Program Change
    public static func midi1ProgramChange(
        group: UInt8, channel: UInt8, program: UInt8
    ) -> [UInt32]
    
    /// MIDI 1.0 Note On
    public static func midi1NoteOn(
        group: UInt8, channel: UInt8, note: UInt8, velocity: UInt8
    ) -> [UInt32]
    
    /// MIDI 1.0 Note Off
    public static func midi1NoteOff(
        group: UInt8, channel: UInt8, note: UInt8, velocity: UInt8 = 0
    ) -> [UInt32]
    
    /// MIDI 1.0 Pitch Bend (14-bit)
    public static func midi1PitchBend(
        group: UInt8, channel: UInt8, value: UInt16
    ) -> [UInt32]
    
    /// Generic MIDI 1.0 Channel Voice
    public static func midi1ChannelVoice(
        group: UInt8, statusByte: UInt8, data1: UInt8, data2: UInt8?
    ) -> [UInt32]
    
    // Utility Messages (32-bit)
    
    /// NOOP message
    public static func noop(group: UInt8) -> [UInt32]
    
    /// JR Clock
    public static func jrClock(group: UInt8, senderClockTime: UInt16) -> [UInt32]
    
    /// JR Timestamp
    public static func jrTimestamp(group: UInt8, timestamp: UInt16) -> [UInt32]
}
```

**Usage:**
```swift
// MIDI 2.0 Control Change (32-bit resolution)
let ccWords = UMPBuilder.midi2ControlChange(
    group: 0, channel: 0, controller: 74, value: 0x80000000
)

// MIDI 2.0 Note On with 16-bit velocity
let noteWords = UMPBuilder.midi2NoteOn(
    group: 0, channel: 0, note: 60, velocity: 0xC000
)

// Program Change with bank select
let pcWords = UMPBuilder.midi2ProgramChange(
    group: 0, channel: 0, program: 10, bank: ProgramBank(msb: 0, lsb: 32)
)

// RPN with 32-bit value
let rpnWords = UMPBuilder.midi2RegisteredController(
    group: 0, channel: 0,
    address: RegisteredController.pitchBendSensitivity,
    value: 0x30000000
)
```

---

### UMPParser

Parser for MIDI 2.0 UMP messages.

```swift
/// Parsed MIDI 2.0 Channel Voice message
public struct ParsedMIDI2ChannelVoice: Sendable, Equatable {
    public let group: UInt8
    public let status: MIDI2ChannelVoiceStatus
    public let channel: UInt8
    public let index: UInt8
    public let extra: UInt8
    public let data: UInt32
    
    // Convenience properties
    public var noteNumber: UInt8          // For Note On/Off
    public var velocity16: UInt16          // 16-bit velocity
    public var velocity7: UInt8            // Scaled to 7-bit
    public var attributeType: NoteAttributeType?
    public var attributeData: UInt16
    public var controllerNumber: UInt8     // For CC
    public var controllerValue32: UInt32   // 32-bit CC value
    public var controllerValue7: UInt8     // Scaled to 7-bit
    public var pitchBendValue32: UInt32    // For Pitch Bend
    public var pitchBendValue14: UInt16    // Scaled to 14-bit
    public var programNumber: UInt8        // For Program Change
    public var bankValid: Bool
    public var bank: ProgramBank?
    public var controllerAddress: ControllerAddress  // For RPN/NRPN
    public var pressureValue32: UInt32     // For Pressure messages
    public var pressureValue7: UInt8
}

/// Parsed MIDI 1.0 Channel Voice message
public struct ParsedMIDI1ChannelVoice: Sendable, Equatable {
    public let group: UInt8
    public let statusByte: UInt8
    public let channel: UInt8
    public let data1: UInt8
    public let data2: UInt8
    
    // Convenience properties
    public var statusNibble: UInt8
    public var isNoteOn: Bool
    public var isNoteOff: Bool
    public var isControlChange: Bool
    public var isProgramChange: Bool
    public var isPitchBend: Bool
    public var noteNumber: UInt8
    public var velocity: UInt8
    public var controllerNumber: UInt8
    public var controllerValue: UInt8
    public var programNumber: UInt8
    public var pitchBendValue: UInt16
}

/// Parsed UMP message types
public enum ParsedUMPMessage: Sendable, Equatable {
    case utility(group: UInt8, status: UInt8, data: UInt16)
    case system(group: UInt8, statusByte: UInt8, data1: UInt8, data2: UInt8)
    case midi1ChannelVoice(ParsedMIDI1ChannelVoice)
    case midi2ChannelVoice(ParsedMIDI2ChannelVoice)
    case data64(group: UInt8, status: UInt8, bytes: [UInt8])
    case data128(group: UInt8, status: UInt8, bytes: [UInt8])
    case unknown(words: [UInt32])
}

public enum UMPParser {
    /// Parse UMP words into structured message
    public static func parse(_ words: [UInt32]) -> ParsedUMPMessage?
    
    /// Extract message type from first word
    public static func messageType(from word0: UInt32) -> UMPMessageType?
    
    /// Extract group from first word
    public static func group(from word0: UInt32) -> UInt8
}
```

**Usage:**
```swift
let words: [UInt32] = [0x40903C00, 0xC0000000]

if let message = UMPParser.parse(words) {
    switch message {
    case .midi2ChannelVoice(let cv):
        switch cv.status {
        case .noteOn:
            print("Note On: \(cv.noteNumber) velocity: \(cv.velocity16)")
        case .controlChange:
            print("CC \(cv.controllerNumber): \(cv.controllerValue32)")
        case .pitchBend:
            print("Pitch Bend: \(cv.pitchBendValue32)")
        default:
            break
        }
        
    case .midi1ChannelVoice(let cv):
        if cv.isNoteOn {
            print("MIDI 1.0 Note On: \(cv.noteNumber)")
        }
        
    default:
        break
    }
}
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
public mutating func cancelAll()

}
```

### PEChunkAssembler

```swift
public enum PEChunkResult: Sendable {
    case incomplete(received: Int, total: Int)
    case complete(header: Data, body: Data)
    case unknownRequestID(requestID: UInt8)
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

**Thread safety**

`CoreMIDITransport` serializes `send()` with its shutdown path (including `deinit → shutdownSync()`) using an internal `shutdownLock`.
`send()` performs the `MIDISend` call while holding this lock to prevent the output port being disposed mid-send.
If shutdown has started, `send()` throws `MIDITransportError.notInitialized`.

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

### UMP (Universal MIDI Packet) API

**Type-safe MIDI 2.0 message construction.**

```swift
/// Message type enumeration
public enum UMPMessageType: UInt8, Sendable {
    case utility = 0x0
    case systemRealTime = 0x1
    case midi1ChannelVoice = 0x2
    case data64 = 0x3
    case midi2ChannelVoice = 0x4
    case data128 = 0x5
    case flexData = 0xD
    case umpStream = 0xF
}

/// Protocol for all UMP messages
public protocol UMPMessage: Sendable {
    var messageType: UMPMessageType { get }
    var group: UMPGroup { get }
    var wordCount: Int { get }
    func toBytes() -> [UInt8]
}

/// MIDI 2.0 Channel Voice (64-bit)
public enum UMPMIDI2ChannelVoice: UMPMessage {
    case noteOff(group: UMPGroup, channel: UMPChannel, note: UInt8, velocity: UInt16, ...)
    case noteOn(group: UMPGroup, channel: UMPChannel, note: UInt8, velocity: UInt16, ...)
    case polyPressure(group: UMPGroup, channel: UMPChannel, note: UInt8, pressure: UInt32)
    case controlChange(group: UMPGroup, channel: UMPChannel, controller: UInt8, value: UInt32)
    case programChange(group: UMPGroup, channel: UMPChannel, program: UInt8, ...)
    case channelPressure(group: UMPGroup, channel: UMPChannel, pressure: UInt32)
    case pitchBend(group: UMPGroup, channel: UMPChannel, value: UInt32)
    // ... and more
}

/// MIDI 1.0 Channel Voice (32-bit)
public enum UMPMIDI1ChannelVoice: UMPMessage {
    case noteOff(group: UMPGroup, channel: UMPChannel, note: UInt8, velocity: UInt8)
    case noteOn(group: UMPGroup, channel: UMPChannel, note: UInt8, velocity: UInt8)
    case controlChange(group: UMPGroup, channel: UMPChannel, controller: UInt8, value: UInt8)
    case programChange(group: UMPGroup, channel: UMPChannel, program: UInt8)
    case pitchBend(group: UMPGroup, channel: UMPChannel, value: UInt16)
    // ... convenience methods: volume, pan, modulation, sustain, etc.
}
```

**Convenient Factory:**

```swift
public enum UMP {
    // MIDI 2.0 (high resolution)
    static func noteOn(group: UMPGroup = 0, channel: UMPChannel, note: UInt8, velocity: UInt16) -> UMPMIDI2ChannelVoice
    static func noteOff(group: UMPGroup = 0, channel: UMPChannel, note: UInt8, velocity: UInt16 = 0) -> UMPMIDI2ChannelVoice
    static func controlChange(group: UMPGroup = 0, channel: UMPChannel, controller: UInt8, value: UInt32) -> UMPMIDI2ChannelVoice
    static func pitchBend(group: UMPGroup = 0, channel: UMPChannel, value: UInt32) -> UMPMIDI2ChannelVoice
    static func programChange(group: UMPGroup = 0, channel: UMPChannel, program: UInt8, bankMSB: UInt8? = nil, bankLSB: UInt8? = nil) -> UMPMIDI2ChannelVoice
    static func rpn(group: UMPGroup = 0, channel: UMPChannel, bank: UInt8, index: UInt8, value: UInt32) -> UMPMIDI2ChannelVoice
    static func nrpn(group: UMPGroup = 0, channel: UMPChannel, bank: UInt8, index: UInt8, value: UInt32) -> UMPMIDI2ChannelVoice
    
    // MIDI 1.0 (compatible)
    enum midi1 {
        static func noteOn(...) -> UMPMIDI1ChannelVoice
        static func controlChange(...) -> UMPMIDI1ChannelVoice
        static func volume(...) -> UMPMIDI1ChannelVoice
        static func pan(...) -> UMPMIDI1ChannelVoice
        static func sustain(...) -> UMPMIDI1ChannelVoice
        static func allNotesOff(...) -> UMPMIDI1ChannelVoice
    }
    
    // Value conversion
    static func velocity7to16(_ v: UInt8) -> UInt16
    static func velocity16to7(_ v: UInt16) -> UInt8
    static func cc7to32(_ v: UInt8) -> UInt32
    static func cc32to7(_ v: UInt32) -> UInt8
    static func pitchBend14to32(_ v: UInt16) -> UInt32
    static func pitchBend32to14(_ v: UInt32) -> UInt16
    
    static let pitchBendCenter: UInt32 = 0x80000000
    static let pitchBendCenter14: UInt16 = 8192
}
```

**Transport Extension:**

```swift
extension MIDITransport {
    /// Send UMP message
    func send(_ message: some UMPMessage, to destination: MIDIDestinationID) async throws
    
    /// Send multiple UMP messages
    func send(_ messages: [any UMPMessage], to destination: MIDIDestinationID) async throws
    
    // Convenience methods
    func sendNoteOn(group: UMPGroup = 0, channel: UMPChannel, note: UInt8, velocity: UInt16, to: MIDIDestinationID) async throws
    func sendNoteOff(group: UMPGroup = 0, channel: UMPChannel, note: UInt8, velocity: UInt16 = 0, to: MIDIDestinationID) async throws
    func sendControlChange(group: UMPGroup = 0, channel: UMPChannel, controller: UInt8, value: UInt32, to: MIDIDestinationID) async throws
    func sendProgramChange(group: UMPGroup = 0, channel: UMPChannel, program: UInt8, bankMSB: UInt8? = nil, bankLSB: UInt8? = nil, to: MIDIDestinationID) async throws
    func sendPitchBend(group: UMPGroup = 0, channel: UMPChannel, value: UInt32, to: MIDIDestinationID) async throws
    func sendAllNotesOff(group: UMPGroup = 0, channel: UMPChannel, to: MIDIDestinationID) async throws
    func sendAllSoundOff(group: UMPGroup = 0, channel: UMPChannel, to: MIDIDestinationID) async throws
}
```

---

## MIDI2PE (Batch API)

### PEBatchResult

```swift
public enum PEBatchResult: Sendable {
    case success(PEResponse)
    case failure(Error)
    
    var response: PEResponse?
    var error: Error?
    var isSuccess: Bool
}
```

### PEBatchResponse

```swift
public struct PEBatchResponse: Sendable {
    /// Results keyed by resource name
    public let results: [String: PEBatchResult]
    
    /// All successful responses
    public var successes: [String: PEResponse]
    
    /// All failures
    public var failures: [String: Error]
    
    /// Whether all requests succeeded
    public var allSucceeded: Bool
    
    /// Counts
    public var successCount: Int
    public var failureCount: Int
    
    /// Subscript access
    public subscript(resource: String) -> PEBatchResult?
}
```

### PEBatchOptions

```swift
public struct PEBatchOptions: Sendable {
    /// Maximum concurrent requests (default: 4)
    public var maxConcurrency: Int
    
    /// Continue on individual failures (default: true)
    public var continueOnFailure: Bool
    
    /// Timeout per request (default: 5 seconds)
    public var timeout: Duration
    
    public init(maxConcurrency: Int = 4, continueOnFailure: Bool = true, timeout: Duration = .seconds(5))
    
    public static let `default`: PEBatchOptions
    public static let serial: PEBatchOptions      // maxConcurrency: 1
    public static let fast: PEBatchOptions        // maxConcurrency: 8, timeout: 3s
}
```

### PEManager Batch Extension

```swift
extension PEManager {
    /// Fetch multiple resources in parallel
    public func batchGet(
        _ resources: [String],
        from device: PEDeviceHandle,
        options: PEBatchOptions = .default
    ) async -> PEBatchResponse
    
    /// Fetch multiple resources (MUID-only, requires destinationResolver)
    public func batchGet(
        _ resources: [String],
        from muid: MUID,
        options: PEBatchOptions = .default
    ) async throws -> PEBatchResponse
    
    /// Fetch channel-specific resources for multiple channels
    public func batchGetChannels(
        _ resource: String,
        channels: [Int],
        from device: PEDeviceHandle,
        options: PEBatchOptions = .default
    ) async -> PEBatchResponse
    
    /// Type-safe batch fetch (2 resources)
    public func batchGetTyped<T1: Decodable & Sendable, T2: Decodable & Sendable>(
        from device: PEDeviceHandle,
        _ r1: (String, T1.Type),
        _ r2: (String, T2.Type),
        timeout: Duration = .seconds(5)
    ) async throws -> (T1, T2)
    
    /// Type-safe batch fetch (3 resources)
    public func batchGetTyped<T1, T2, T3>(...) async throws -> (T1, T2, T3)
    
    /// Type-safe batch fetch (4 resources)
    public func batchGetTyped<T1, T2, T3, T4>(...) async throws -> (T1, T2, T3, T4)
}
```

**Usage Examples:**

```swift
// Basic batch GET
let response = await peManager.batchGet(
    ["DeviceInfo", "ResourceList", "ProgramList"],
    from: device
)

if let info = response["DeviceInfo"]?.response {
    print("Status: \(info.status)")
}
print("Success: \(response.successCount)/\(response.results.count)")

// With options
let response = await peManager.batchGet(
    resources,
    from: device,
    options: PEBatchOptions(maxConcurrency: 2, continueOnFailure: false)
)

// Type-safe batch
let (deviceInfo, resourceList) = try await peManager.batchGetTyped(
    from: device,
    ("DeviceInfo", PEDeviceInfo.self),
    ("ResourceList", [PEResourceEntry].self)
)

// Channel batch
let response = await peManager.batchGetChannels(
    "ProgramInfo",
    channels: Array(0..<16),
    from: device
)
for (key, result) in response.successes {
    print("\(key): \(result.status)")
}
```
