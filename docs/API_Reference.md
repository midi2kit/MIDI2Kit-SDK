# MIDI2Kit API Reference

**Version**: 1.0.0-draft  
**Last Updated**: 2026-01-26

---

## Overview

MIDI2Kit is a Swift library for implementing MIDI 2.0 (UMP, MIDI-CI, Property Exchange) in macOS and iOS applications.

### Module Structure

| Module | Description |
|--------|-------------|
| **MIDI2Core** | UMP types, parsing, value scaling |
| **MIDI2Transport** | MIDI I/O abstraction (CoreMIDI wrapper) |
| **MIDI2CI** | MIDI-CI Discovery and device management |
| **MIDI2PE** | Property Exchange (GET/SET/Subscribe) |
| **MIDI2Kit** | Unified API combining all modules |

---

## Quick Start

```swift
import MIDI2Kit

// 1. Create transport
let transport = try CoreMIDITransport(clientName: "MyApp")

// 2. Create CI Manager for device discovery
let ciManager = CIManager(transport: transport)
try await ciManager.start()

// 3. Create PE Manager for Property Exchange
let peManager = PEManager(transport: transport, sourceMUID: ciManager.muid)
peManager.destinationResolver = ciManager.makeDestinationResolver()
await peManager.startReceiving()

// 4. Discover devices
for await event in ciManager.events {
    switch event {
    case .deviceDiscovered(let device):
        if device.supportsPropertyExchange {
            // Get device info
            let info = try await peManager.getDeviceInfo(from: device.muid)
            print("Found: \(info.productName)")
        }
    default:
        break
    }
}
```

---

## MIDI2Core

### UMPMessageType

MIDI 2.0 Universal MIDI Packet message types.

```swift
public enum UMPMessageType: UInt8, Sendable, CaseIterable {
    case utility = 0x0          // 32-bit: NOOP, JR Clock, etc.
    case system = 0x1           // 32-bit: System Real Time/Common
    case midi1ChannelVoice = 0x2 // 32-bit: MIDI 1.0 wrapped
    case data64 = 0x3           // 64-bit: SysEx7
    case midi2ChannelVoice = 0x4 // 64-bit: MIDI 2.0 Channel Voice
    case data128 = 0x5          // 128-bit: SysEx8, Mixed Data Set
    case flexData = 0xD         // 128-bit: Flex Data
    case umpStream = 0xF        // 128-bit: UMP Stream
    
    var wordCount: Int { get }
}
```

### MIDI2ChannelVoiceStatus

MIDI 2.0 Channel Voice message status codes.

```swift
public enum MIDI2ChannelVoiceStatus: UInt8, Sendable, CaseIterable {
    case registeredPerNoteController = 0x0
    case assignablePerNoteController = 0x1
    case registeredController = 0x2
    case assignableController = 0x3
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
```

### UMPGroup / MIDIChannel

```swift
public struct UMPGroup: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt8  // 0-15
    public static let group0 = UMPGroup(rawValue: 0)
}

public struct MIDIChannel: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt8  // 0-15
    var displayValue: Int { get }  // 1-16
    public static let channel1 = MIDIChannel(rawValue: 0)
}
```

### UMPValueScaling

Utilities for scaling values between MIDI 1.0 and MIDI 2.0 resolutions.

```swift
public enum UMPValueScaling {
    // 7-bit ↔ 32-bit
    static func scale7To32(_ value7: UInt8) -> UInt32
    static func scale32To7(_ value32: UInt32) -> UInt8
    
    // 14-bit ↔ 32-bit
    static func scale14To32(_ value14: UInt16) -> UInt32
    static func scale32To14(_ value32: UInt32) -> UInt16
    
    // Normalized (0.0-1.0) ↔ 32-bit
    static func normalizedTo32(_ normalized: Double) -> UInt32
    static func to32Normalized(_ value32: UInt32) -> Double
    
    // Velocity scaling (7-bit ↔ 16-bit)
    static func scaleVelocity7To16(_ velocity7: UInt8) -> UInt16
    static func scaleVelocity16To7(_ velocity16: UInt16) -> UInt8
}
```

### MUID

MIDI Unique Identifier (28-bit).

```swift
public struct MUID: Sendable, Hashable, CustomStringConvertible {
    public let value: UInt32
    
    public static func random() -> MUID
    public static let broadcast: MUID  // 0x0FFFFFFF
    
    var isBroadcast: Bool { get }
}
```

### DeviceIdentity

Device identification for MIDI-CI.

```swift
public struct DeviceIdentity: Sendable, Hashable {
    public let manufacturerID: ManufacturerID
    public let familyID: UInt16
    public let modelID: UInt16
    public let versionID: UInt32
    
    public static let `default`: DeviceIdentity
}

public enum ManufacturerID: Sendable, Hashable {
    case standard(UInt8)              // 1-byte ID
    case extended(UInt8, UInt8)       // 3-byte ID (00 xx xx)
}
```

### Mcoded7

Encoding/decoding for 8-bit data over 7-bit MIDI.

```swift
public enum Mcoded7 {
    public static func encode(_ data: Data) -> Data
    public static func decode(_ data: Data) -> Data?
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
    func findMatchingDestination(for source: MIDISourceID) async -> MIDIDestinationID?
    func shutdown() async
}
```

### CoreMIDITransport

Production implementation using CoreMIDI.

```swift
public class CoreMIDITransport: MIDITransport {
    public init(clientName: String) throws
}
```

### MockMIDITransport

For unit testing.

```swift
public actor MockMIDITransport: MIDITransport {
    public init()
    
    // Test helpers
    public func simulateReceive(_ data: [UInt8], from source: MIDISourceID?)
    public func addMockDestination(_ info: MIDIDestinationInfo)
    public func addMockSource(_ info: MIDISourceInfo)
    public var sentMessages: [(data: [UInt8], destination: MIDIDestinationID)] { get }
}
```

### Endpoint Types

```swift
public struct MIDISourceID: Sendable, Hashable {
    public let value: UInt32
}

public struct MIDIDestinationID: Sendable, Hashable {
    public let value: UInt32
}

public struct MIDISourceInfo: Sendable, Identifiable, Hashable {
    public let sourceID: MIDISourceID
    public let name: String
    public let manufacturer: String?
    public let isOnline: Bool
    public let uniqueID: Int32?  // Persistent across sessions
}

public struct MIDIDestinationInfo: Sendable, Identifiable, Hashable {
    public let destinationID: MIDIDestinationID
    public let name: String
    public let manufacturer: String?
    public let isOnline: Bool
    public let uniqueID: Int32?  // Persistent across sessions
}

public struct MIDIReceivedData: Sendable {
    public let data: [UInt8]
    public let sourceID: MIDISourceID?
    public let timestamp: UInt64
}
```

---

## MIDI2CI

### CIManager

High-level MIDI-CI manager with automatic device discovery.

```swift
public actor CIManager {
    // Initialization
    public init(
        transport: any MIDITransport,
        muid: MUID? = nil,
        configuration: CIManagerConfiguration = .default
    )
    
    // Properties
    public nonisolated let muid: MUID
    public nonisolated let events: AsyncStream<CIManagerEvent>
    public var discoveredDevices: [DiscoveredDevice] { get }
    public var peCapableDevices: [DiscoveredDevice] { get }
    
    // Lifecycle
    public func start() async throws
    public func stop() async
    
    // Discovery
    public func startDiscovery()
    public func stopDiscovery()
    public func sendDiscoveryInquiry() async
    
    // Device access
    public func device(for muid: MUID) -> DiscoveredDevice?
    public func destination(for muid: MUID) -> MIDIDestinationID?
    public nonisolated func makeDestinationResolver() -> @Sendable (MUID) async -> MIDIDestinationID?
    
    // Device management
    public func removeDevice(_ muid: MUID)
    public func clearDevices()
    public func invalidateMUID() async
}
```

### CIManagerConfiguration

```swift
public struct CIManagerConfiguration: Sendable {
    public var discoveryInterval: TimeInterval      // Default: 5.0
    public var deviceTimeout: TimeInterval          // Default: 15.0
    public var autoStartDiscovery: Bool             // Default: true
    public var respondToDiscovery: Bool             // Default: true
    public var categorySupport: CategorySupport     // Default: .propertyExchange
    public var deviceIdentity: DeviceIdentity
    public var maxSysExSize: UInt32                 // Default: 0 (no limit)
    
    public static let `default`: CIManagerConfiguration
}
```

### CIManagerEvent

```swift
public enum CIManagerEvent: Sendable {
    case deviceDiscovered(DiscoveredDevice)
    case deviceLost(MUID)
    case deviceUpdated(DiscoveredDevice)
    case discoveryStarted
    case discoveryStopped
}
```

### DiscoveredDevice

```swift
public struct DiscoveredDevice: Sendable, Identifiable, Hashable {
    public let muid: MUID
    public let identity: DeviceIdentity
    public let categorySupport: CategorySupport
    public let maxSysExSize: UInt32
    public let initiatorOutputPath: UInt8
    public let functionBlock: UInt8
    
    public var id: UInt32 { muid.value }
    public var supportsPropertyExchange: Bool { get }
    public var displayName: String { get }
}
```

### CategorySupport

```swift
public struct CategorySupport: OptionSet, Sendable {
    public static let protocolNegotiation: CategorySupport
    public static let profileConfiguration: CategorySupport
    public static let propertyExchange: CategorySupport
    public static let processInquiry: CategorySupport
}
```

---

## MIDI2PE

### PEManager

High-level Property Exchange manager.

```swift
public actor PEManager {
    public static let defaultTimeout: Duration = .seconds(5)
    
    // Initialization
    public init(
        transport: any MIDITransport,
        sourceMUID: MUID,
        maxInflightPerDevice: Int = 2,
        notifyAssemblyTimeout: TimeInterval = 2.0,
        logger: any MIDI2Logger = NullMIDI2Logger()
    )
    
    // Destination resolver (for MUID-only API)
    public var destinationResolver: (@Sendable (MUID) async -> MIDIDestinationID?)?
    
    // Lifecycle
    public func startReceiving() async
    public func stopReceiving() async
    
    // Unified Request API (Recommended)
    public func send(_ request: PERequest) async throws -> PEResponse
    
    // GET Operations
    public func get(_ resource: String, from device: PEDeviceHandle, timeout: Duration) async throws -> PEResponse
    public func get(_ resource: String, channel: Int, from device: PEDeviceHandle, timeout: Duration) async throws -> PEResponse
    public func get(_ resource: String, offset: Int, limit: Int, from device: PEDeviceHandle, timeout: Duration) async throws -> PEResponse
    
    // GET with MUID (auto-resolve destination)
    public func get(_ resource: String, from muid: MUID, timeout: Duration) async throws -> PEResponse
    
    // SET Operations
    public func set(_ resource: String, data: Data, to device: PEDeviceHandle, timeout: Duration) async throws -> PEResponse
    public func set(_ resource: String, data: Data, channel: Int, to device: PEDeviceHandle, timeout: Duration) async throws -> PEResponse
    
    // SET with MUID
    public func set(_ resource: String, data: Data, to muid: MUID, timeout: Duration) async throws -> PEResponse
    
    // Typed JSON API
    public func getJSON<T: Decodable>(_ resource: String, from device: PEDeviceHandle, timeout: Duration) async throws -> T
    public func setJSON<T: Encodable>(_ resource: String, value: T, to device: PEDeviceHandle, timeout: Duration) async throws -> PEResponse
    
    // Convenience Methods
    public func getDeviceInfo(from device: PEDeviceHandle) async throws -> PEDeviceInfo
    public func getDeviceInfo(from muid: MUID) async throws -> PEDeviceInfo
    public func getResourceList(from device: PEDeviceHandle) async throws -> [PEResourceEntry]
    public func getResourceList(from muid: MUID) async throws -> [PEResourceEntry]
    
    // Subscribe Operations
    public func subscribe(to resource: String, on device: PEDeviceHandle, timeout: Duration) async throws -> PESubscribeResponse
    public func unsubscribe(subscribeId: String, timeout: Duration) async throws -> PESubscribeResponse
    public func startNotificationStream() -> AsyncStream<PENotification>
    public var subscriptions: [PESubscription] { get }
    
    // Diagnostics
    public var diagnostics: String { get async }
}
```

### PEDeviceHandle

```swift
public struct PEDeviceHandle: Sendable, Hashable {
    public let muid: MUID
    public let destination: MIDIDestinationID
    
    public init(muid: MUID, destination: MIDIDestinationID)
}
```

### PERequest

```swift
public struct PERequest: Sendable {
    public let operation: Operation
    public let resource: String
    public let device: PEDeviceHandle
    public let body: Data?
    public let channel: Int?
    public let offset: Int?
    public let limit: Int?
    public let timeout: Duration
    
    public enum Operation: String, Sendable {
        case get = "GET"
        case set = "SET"
        case subscribe = "SUBSCRIBE"
        case unsubscribe = "UNSUBSCRIBE"
    }
    
    // Factory methods
    public static func get(_ resource: String, from device: PEDeviceHandle, timeout: Duration = PEManager.defaultTimeout) -> PERequest
    public static func get(_ resource: String, channel: Int, from device: PEDeviceHandle, timeout: Duration = PEManager.defaultTimeout) -> PERequest
    public static func get(_ resource: String, offset: Int, limit: Int, from device: PEDeviceHandle, timeout: Duration = PEManager.defaultTimeout) -> PERequest
    public static func set(_ resource: String, data: Data, to device: PEDeviceHandle, timeout: Duration = PEManager.defaultTimeout) -> PERequest
    public static func set(_ resource: String, data: Data, channel: Int, to device: PEDeviceHandle, timeout: Duration = PEManager.defaultTimeout) -> PERequest
}
```

### PEResponse

```swift
public struct PEResponse: Sendable {
    public let status: Int
    public let header: PEHeader?
    public let body: Data
    
    public var decodedBody: Data { get }  // Mcoded7 decoded
    public var bodyString: String? { get }
    public var isSuccess: Bool { get }    // 200-299
    public var isError: Bool { get }      // 400+
}
```

### PEHeader

```swift
public struct PEHeader: Sendable, Codable {
    public let status: Int?
    public let message: String?
    public let resource: String?
    public let mutualEncoding: String?
    
    public var isMcoded7: Bool { get }
}
```

### PEError

```swift
public enum PEError: Error, Sendable {
    case timeout(resource: String)
    case cancelled
    case requestIDExhausted
    case deviceError(status: Int, message: String?)
    case deviceNotFound(MUID)
    case invalidResponse(String)
    case transportError(Error)
    case noDestination
    case validationFailed(PERequestError)
    case nak(PENAKDetails)
}
```

### Standard Resources

```swift
// DeviceInfo response
public struct PEDeviceInfo: Sendable, Codable {
    public let manufacturerId: [Int]
    public let familyId: [Int]
    public let modelId: [Int]
    public let softwareRevisionLevel: [Int]
    public let manufacturerName: String?
    public let productName: String?
    public let productInstanceId: String?
}

// ResourceList entry
public struct PEResourceEntry: Sendable, Codable {
    public let resource: String
    public let canGet: Bool?
    public let canSet: Bool?
    public let canSubscribe: Bool?
    public let requireResId: Bool?
    public let canPaginate: Bool?
    public let columns: [PEColumnDefinition]?
}
```

### Subscription Types

```swift
public struct PESubscription: Sendable {
    public let subscribeId: String
    public let resource: String
    public let device: PEDeviceHandle
}

public struct PESubscribeResponse: Sendable {
    public let status: Int
    public let subscribeId: String?
    public var isSuccess: Bool { get }
}

public struct PENotification: Sendable {
    public let resource: String
    public let subscribeId: String
    public let header: PEHeader?
    public let data: Data
    public let sourceMUID: MUID
}
```

---

## Error Handling

### Transport Errors

```swift
public enum MIDITransportError: Error, Sendable {
    case notInitialized
    case clientCreationFailed(Int32)
    case portCreationFailed(Int32)
    case sendFailed(Int32)
    case connectionFailed(Int32)
    case destinationNotFound(UInt32)
    case sourceNotFound(UInt32)
    case packetListAddFailed(dataSize: Int, bufferSize: Int)
}
```

### PE Errors

```swift
public enum PEError: Error, Sendable {
    case timeout(resource: String)
    case cancelled
    case requestIDExhausted
    case deviceError(status: Int, message: String?)
    case deviceNotFound(MUID)
    case invalidResponse(String)
    case transportError(Error)
    case noDestination
    case validationFailed(PERequestError)
    case nak(PENAKDetails)
}
```

---

## Best Practices

### 1. Use MUID-only API with Destination Resolver

```swift
// Setup once
peManager.destinationResolver = ciManager.makeDestinationResolver()

// Then use simple MUID-based calls
let info = try await peManager.getDeviceInfo(from: device.muid)
```

### 2. Handle Device Lifecycle

```swift
for await event in ciManager.events {
    switch event {
    case .deviceDiscovered(let device):
        // Add to UI
    case .deviceLost(let muid):
        // Remove from UI, cancel pending operations
    case .deviceUpdated(let device):
        // Refresh UI
    default:
        break
    }
}
```

### 3. Use Typed JSON API

```swift
// Type-safe GET
let resources: [PEResourceEntry] = try await peManager.getJSON("ResourceList", from: device)

// Type-safe SET
struct MySettings: Codable { var volume: Int }
try await peManager.setJSON("Settings", value: MySettings(volume: 80), to: device)
```

### 4. Handle Subscriptions

```swift
// Subscribe
let response = try await peManager.subscribe(to: "ProgramChange", on: device)

// Handle notifications
for await notification in peManager.startNotificationStream() {
    print("Changed: \(notification.resource)")
}

// Unsubscribe when done
try await peManager.unsubscribe(subscribeId: response.subscribeId!)
```

### 5. Graceful Shutdown

```swift
// Stop in reverse order of creation
await peManager.stopReceiving()
await ciManager.invalidateMUID()
await ciManager.stop()
await transport.shutdown()
```

---

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| macOS    | 13.0+           |
| iOS      | 16.0+           |
| iPadOS   | 16.0+           |

---

## References

- [MIDI 2.0 UMP Specification](https://www.midi.org/)
- [MIDI-CI Specification](https://www.midi.org/)
- [Property Exchange Specification](https://www.midi.org/)
