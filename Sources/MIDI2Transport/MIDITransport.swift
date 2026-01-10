//
//  MIDITransport.swift
//  MIDI2Kit
//
//  MIDI Transport Protocol Abstraction
//

import Foundation

/// MIDI Source ID wrapper
public struct MIDISourceID: Sendable, Hashable {
    public let value: UInt32
    
    public init(_ value: UInt32) {
        self.value = value
    }
}

/// MIDI Destination ID wrapper
public struct MIDIDestinationID: Sendable, Hashable {
    public let value: UInt32
    
    public init(_ value: UInt32) {
        self.value = value
    }
}

/// Represents a MIDI source endpoint
public struct MIDISourceInfo: Sendable, Identifiable, Hashable {
    public var id: UInt32 { sourceID.value }
    
    public let sourceID: MIDISourceID
    public let name: String
    public let manufacturer: String?
    public let isOnline: Bool
    
    public init(sourceID: MIDISourceID, name: String, manufacturer: String? = nil, isOnline: Bool = true) {
        self.sourceID = sourceID
        self.name = name
        self.manufacturer = manufacturer
        self.isOnline = isOnline
    }
}

/// Represents a MIDI destination endpoint
public struct MIDIDestinationInfo: Sendable, Identifiable, Hashable {
    public var id: UInt32 { destinationID.value }
    
    public let destinationID: MIDIDestinationID
    public let name: String
    public let manufacturer: String?
    public let isOnline: Bool
    
    public init(destinationID: MIDIDestinationID, name: String, manufacturer: String? = nil, isOnline: Bool = true) {
        self.destinationID = destinationID
        self.name = name
        self.manufacturer = manufacturer
        self.isOnline = isOnline
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
