//
//  MockMIDITransport.swift
//  MIDI2Kit
//
//  Mock transport for testing
//

import Foundation
import MIDI2Core

/// Mock MIDI transport for testing without actual MIDI hardware
public actor MockMIDITransport: MIDITransport {
    
    // MARK: - Recorded Data
    
    /// Messages sent through this transport
    public private(set) var sentMessages: [SentMessage] = []
    
    /// Structure to record sent messages
    public struct SentMessage: Sendable {
        public let data: [UInt8]
        public let destination: MIDIDestinationID
        public let timestamp: Date
    }
    
    // MARK: - Mock State
    
    /// Mock sources to report
    public var mockSources: [MIDISourceInfo] = []
    
    /// Mock destinations to report
    public var mockDestinations: [MIDIDestinationInfo] = []
    
    // MARK: - Streams
    
    public nonisolated let received: AsyncStream<MIDIReceivedData>
    public nonisolated let setupChanged: AsyncStream<Void>
    
    private var receivedContinuation: AsyncStream<MIDIReceivedData>.Continuation?
    private var setupChangedContinuation: AsyncStream<Void>.Continuation?
    
    // MARK: - Initialization
    
    public init() {
        var receivedCont: AsyncStream<MIDIReceivedData>.Continuation?
        self.received = AsyncStream { continuation in
            receivedCont = continuation
        }
        
        var setupCont: AsyncStream<Void>.Continuation?
        self.setupChanged = AsyncStream { continuation in
            setupCont = continuation
        }
        
        self.receivedContinuation = receivedCont
        self.setupChangedContinuation = setupCont
    }
    
    // MARK: - MIDITransport Protocol
    
    public func send(_ data: [UInt8], to destination: MIDIDestinationID) async throws {
        let message = SentMessage(
            data: data,
            destination: destination,
            timestamp: Date()
        )
        sentMessages.append(message)
    }
    
    public var sources: [MIDISourceInfo] {
        get async { mockSources }
    }
    
    public var destinations: [MIDIDestinationInfo] {
        get async { mockDestinations }
    }
    
    public func connect(to source: MIDISourceID) async throws {
        // No-op for mock
    }
    
    public func disconnect(from source: MIDISourceID) async throws {
        // No-op for mock
    }
    
    public func connectToAllSources() async throws {
        // No-op for mock
    }
    
    /// Source to destination mapping for testing
    ///
    /// Configure this to control what `findMatchingDestination` returns.
    /// Key: sourceID.value, Value: destinationID.value
    public var sourceToDestinationMap: [UInt32: UInt32] = [:]
    
    public func findMatchingDestination(for source: MIDISourceID) async -> MIDIDestinationID? {
        // Check explicit mapping first
        if let destValue = sourceToDestinationMap[source.value] {
            return MIDIDestinationID(destValue)
        }
        
        // Default: try to find destination with matching name
        let sourceInfo = mockSources.first { $0.sourceID == source }
        guard let sourceName = sourceInfo?.name else { return nil }
        
        let matchingDest = mockDestinations.first { $0.name == sourceName }
        return matchingDest?.destinationID
    }
    
    // MARK: - Test Helpers
    
    /// Set mock destinations
    public func setMockDestinations(_ destinations: [MIDIDestinationInfo]) {
        mockDestinations = destinations
    }
    
    /// Add a mock destination
    public func addDestination(_ destination: MIDIDestinationInfo) {
        mockDestinations.append(destination)
    }
    
    /// Add a mock source
    public func addSource(_ source: MIDISourceInfo) {
        mockSources.append(source)
    }
    
    /// Set mock sources
    public func setMockSources(_ sources: [MIDISourceInfo]) {
        mockSources = sources
    }
    
    /// Inject a received message (simulates device sending data)
    public func injectReceived(_ data: [UInt8], from source: MIDISourceID? = nil) {
        let received = MIDIReceivedData(data: data, sourceID: source)
        receivedContinuation?.yield(received)
    }
    
    /// Simulate receiving data (alias for injectReceived)
    public func simulateReceive(_ data: [UInt8], from source: MIDISourceID? = nil) {
        injectReceived(data, from: source)
    }
    
    /// Inject multiple received messages
    public func injectReceived(_ messages: [[UInt8]], from source: MIDISourceID? = nil) {
        for data in messages {
            injectReceived(data, from: source)
        }
    }
    
    /// Notify setup changed
    public func notifySetupChanged() {
        setupChangedContinuation?.yield(())
    }
    
    /// Clear recorded sent messages
    public func clearSentMessages() {
        sentMessages.removeAll()
    }
    
    /// Get last sent message
    public var lastSentMessage: SentMessage? {
        sentMessages.last
    }
    
    /// Check if a specific CI message type was sent (checks byte 4)
    public func wasSent(ciMessageType: UInt8) -> Bool {
        sentMessages.contains { message in
            message.data.count >= 5 && message.data[4] == ciMessageType
        }
    }
}

// MARK: - Test Scenarios

extension MockMIDITransport {
    
    /// Create a mock with simulated KORG device
    public static func withKORGDevice() -> MockMIDITransport {
        let mock = MockMIDITransport()
        Task {
            await mock.setupKORGDevice()
        }
        return mock
    }
    
    private func setupKORGDevice() {
        mockSources = [
            MIDISourceInfo(
                sourceID: MIDISourceID(1),
                name: "KORG Module Pro",
                manufacturer: "KORG",
                isOnline: true,
                uniqueID: 0x4B4F5247  // "KORG" in hex (example persistent ID)
            )
        ]
        mockDestinations = [
            MIDIDestinationInfo(
                destinationID: MIDIDestinationID(1),
                name: "KORG Module Pro",
                manufacturer: "KORG",
                isOnline: true,
                uniqueID: 0x4B4F5248  // Different from source (example)
            )
        ]
    }
}
