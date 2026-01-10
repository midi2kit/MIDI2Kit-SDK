//
//  MIDITransport.swift
//  MIDI2Kit
//
//  MIDI Transport Protocol Abstraction
//

import Foundation

// MARK: - Endpoint Identifiers

/// MIDI Source endpoint identifier
///
/// This wraps a CoreMIDI `MIDIEndpointRef` value, which is a **session-scoped**
/// handle to a MIDI source endpoint.
///
/// ## Important Notes
///
/// - **Not a persistent ID**: The underlying value is a `MIDIEndpointRef` (runtime handle),
///   not a `kMIDIPropertyUniqueID`. It may change across:
///   - System reboots
///   - MIDI device reconnection
///   - Audio/MIDI setup changes
///
/// - **Valid only within current session**: Do not persist this value to disk or
///   use it to identify devices across app launches.
///
/// - **For persistent device identification**, use:
///   - `MIDISourceInfo.name` + manufacturer (human-readable)
///   - CoreMIDI's `kMIDIPropertyUniqueID` property (Int32, stable across sessions)
///
/// ## CoreMIDI Relationship
///
/// ```swift
/// // This value corresponds to:
/// let endpointRef: MIDIEndpointRef = MIDIGetSource(index)
/// let sourceID = MIDISourceID(endpointRef)  // wraps the ref
/// ```
public struct MIDISourceID: Sendable, Hashable {
    /// The CoreMIDI `MIDIEndpointRef` value.
    ///
    /// - Warning: This is a session-scoped handle, not a persistent unique ID.
    public let value: UInt32
    
    public init(_ value: UInt32) {
        self.value = value
    }
}

/// MIDI Destination endpoint identifier
///
/// This wraps a CoreMIDI `MIDIEndpointRef` value, which is a **session-scoped**
/// handle to a MIDI destination endpoint.
///
/// ## Important Notes
///
/// - **Not a persistent ID**: The underlying value is a `MIDIEndpointRef` (runtime handle),
///   not a `kMIDIPropertyUniqueID`. It may change across:
///   - System reboots
///   - MIDI device reconnection
///   - Audio/MIDI setup changes
///
/// - **Valid only within current session**: Do not persist this value to disk or
///   use it to identify devices across app launches.
///
/// - **For persistent device identification**, use:
///   - `MIDIDestinationInfo.name` + manufacturer (human-readable)
///   - CoreMIDI's `kMIDIPropertyUniqueID` property (Int32, stable across sessions)
///
/// ## CoreMIDI Relationship
///
/// ```swift
/// // This value corresponds to:
/// let endpointRef: MIDIEndpointRef = MIDIGetDestination(index)
/// let destID = MIDIDestinationID(endpointRef)  // wraps the ref
/// ```
public struct MIDIDestinationID: Sendable, Hashable {
    /// The CoreMIDI `MIDIEndpointRef` value.
    ///
    /// - Warning: This is a session-scoped handle, not a persistent unique ID.
    public let value: UInt32
    
    public init(_ value: UInt32) {
        self.value = value
    }
}

// MARK: - Endpoint Information

/// Represents a MIDI source endpoint with metadata
///
/// ## Persistence
///
/// The `sourceID` is a session-scoped handle and should not be persisted.
/// For identifying devices across sessions, use `uniqueID` (stable) or
/// `name` + `manufacturer` (human-readable).
public struct MIDISourceInfo: Sendable, Identifiable, Hashable {
    /// Session-scoped identifier (not persistent)
    public var id: UInt32 { sourceID.value }
    
    public let sourceID: MIDISourceID
    public let name: String
    public let manufacturer: String?
    public let isOnline: Bool
    
    /// Persistent unique ID from CoreMIDI (`kMIDIPropertyUniqueID`)
    ///
    /// This value survives reboots and device reconnections. Use this
    /// for persistent device identification across app launches.
    ///
    /// - Note: May be `nil` for virtual endpoints or if the property is unavailable.
    public let uniqueID: Int32?
    
    public init(
        sourceID: MIDISourceID,
        name: String,
        manufacturer: String? = nil,
        isOnline: Bool = true,
        uniqueID: Int32? = nil
    ) {
        self.sourceID = sourceID
        self.name = name
        self.manufacturer = manufacturer
        self.isOnline = isOnline
        self.uniqueID = uniqueID
    }
}

/// Represents a MIDI destination endpoint with metadata
///
/// ## Persistence
///
/// The `destinationID` is a session-scoped handle and should not be persisted.
/// For identifying devices across sessions, use `uniqueID` (stable) or
/// `name` + `manufacturer` (human-readable).
public struct MIDIDestinationInfo: Sendable, Identifiable, Hashable {
    /// Session-scoped identifier (not persistent)
    public var id: UInt32 { destinationID.value }
    
    public let destinationID: MIDIDestinationID
    public let name: String
    public let manufacturer: String?
    public let isOnline: Bool
    
    /// Persistent unique ID from CoreMIDI (`kMIDIPropertyUniqueID`)
    ///
    /// This value survives reboots and device reconnections. Use this
    /// for persistent device identification across app launches.
    ///
    /// - Note: May be `nil` for virtual endpoints or if the property is unavailable.
    public let uniqueID: Int32?
    
    public init(
        destinationID: MIDIDestinationID,
        name: String,
        manufacturer: String? = nil,
        isOnline: Bool = true,
        uniqueID: Int32? = nil
    ) {
        self.destinationID = destinationID
        self.name = name
        self.manufacturer = manufacturer
        self.isOnline = isOnline
        self.uniqueID = uniqueID
    }
}

/// Received MIDI data with source information
public struct MIDIReceivedData: Sendable {
    public let data: [UInt8]
    public let sourceID: MIDISourceID?
    public let timestamp: UInt64
    
    public init(data: [UInt8], sourceID: MIDISourceID? = nil, timestamp: UInt64 = 0) {
        self.data = data
        self.sourceID = sourceID
        self.timestamp = timestamp
    }
}

/// Protocol for MIDI transport implementations
///
/// Abstracts the underlying MIDI system (CoreMIDI, virtual, mock, etc.)
/// to enable testing and platform flexibility.
public protocol MIDITransport: Sendable {
    
    /// Send MIDI data to a destination
    /// - Parameters:
    ///   - data: MIDI bytes to send
    ///   - destination: Destination endpoint ID
    func send(_ data: [UInt8], to destination: MIDIDestinationID) async throws
    
    /// Stream of received MIDI data
    var received: AsyncStream<MIDIReceivedData> { get }
    
    /// Available MIDI sources
    var sources: [MIDISourceInfo] { get async }
    
    /// Available MIDI destinations
    var destinations: [MIDIDestinationInfo] { get async }
    
    /// Stream of setup change notifications
    var setupChanged: AsyncStream<Void> { get }
    
    /// Connect to a MIDI source
    func connect(to source: MIDISourceID) async throws
    
    /// Disconnect from a MIDI source
    func disconnect(from source: MIDISourceID) async throws
    
    /// Connect to all available sources
    func connectToAllSources() async throws
    
    /// Find the matching destination for a source (same entity/device)
    ///
    /// This is essential for bidirectional communication with MIDI-CI devices.
    /// In CoreMIDI, a source (input from device) and destination (output to device)
    /// that belong to the same entity represent the same physical port.
    ///
    /// ## CoreMIDI Structure
    /// ```
    /// Device
    ///   └── Entity (physical port)
    ///        ├── Source (receive from device)
    ///        └── Destination (send to device)
    /// ```
    ///
    /// - Parameter source: The source to find a matching destination for
    /// - Returns: The matching destination, or `nil` if none found
    func findMatchingDestination(for source: MIDISourceID) async -> MIDIDestinationID?
}

/// MIDI Transport errors
public enum MIDITransportError: Error, Sendable {
    case notInitialized
    case clientCreationFailed(Int32)
    case portCreationFailed(Int32)
    case sendFailed(Int32)
    case connectionFailed(Int32)
    case destinationNotFound(UInt32)
    case sourceNotFound(UInt32)
    /// MIDIPacketListAdd failed (buffer too small or invalid parameters)
    case packetListAddFailed(dataSize: Int, bufferSize: Int)
}

extension MIDITransportError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notInitialized:
            return "MIDI transport not initialized"
        case .clientCreationFailed(let status):
            return "Failed to create MIDI client (OSStatus: \(status))"
        case .portCreationFailed(let status):
            return "Failed to create MIDI port (OSStatus: \(status))"
        case .sendFailed(let status):
            return "Failed to send MIDI data (OSStatus: \(status))"
        case .connectionFailed(let status):
            return "Failed to connect/disconnect MIDI source (OSStatus: \(status))"
        case .destinationNotFound(let id):
            return "MIDI destination not found (ID: \(id))"
        case .sourceNotFound(let id):
            return "MIDI source not found (ID: \(id))"
        case .packetListAddFailed(let dataSize, let bufferSize):
            return "MIDIPacketListAdd failed (data: \(dataSize) bytes, buffer: \(bufferSize) bytes)"
        }
    }
}
