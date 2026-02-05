//
//  LoopbackTransport.swift
//  MIDI2Kit
//
//  Loopback transport for same-process MIDI-CI testing
//

import Foundation

/// Loopback MIDI transport for same-process communication
///
/// Creates paired transports where messages sent on one are received by the other.
/// This enables testing MIDI-CI Initiator ↔ Responder communication without hardware.
///
/// ## Usage
/// ```swift
/// let (initiatorTransport, responderTransport) = LoopbackTransport.createPair()
///
/// // Message sent by initiator appears on responder's received stream
/// await initiatorTransport.send(data, to: destination)
/// // responderTransport.received yields the data
/// ```
public actor LoopbackTransport: MIDITransport {

    // MARK: - Types

    /// Role of this transport in the pair
    public enum Role: Sendable {
        case initiator
        case responder
    }

    // MARK: - Properties

    /// Role of this transport
    public let role: Role

    /// The paired transport (weak to avoid retain cycle)
    private weak var _peer: LoopbackTransport?

    /// Mock sources reported by this transport
    public private(set) var mockSources: [MIDISourceInfo] = []

    /// Mock destinations reported by this transport
    public private(set) var mockDestinations: [MIDIDestinationInfo] = []

    // MARK: - Streams

    public nonisolated let received: AsyncStream<MIDIReceivedData>
    public nonisolated let setupChanged: AsyncStream<Void>

    private var receivedContinuation: AsyncStream<MIDIReceivedData>.Continuation?
    private var setupChangedContinuation: AsyncStream<Void>.Continuation?

    // MARK: - Initialization

    private init(role: Role) {
        self.role = role

        // Use makeStream() to ensure continuations are available immediately
        // The old closure-based approach had a race condition where continuation
        // was nil until the stream was first iterated
        let (receivedStream, receivedCont) = AsyncStream<MIDIReceivedData>.makeStream()
        let (setupStream, setupCont) = AsyncStream<Void>.makeStream()

        self.received = receivedStream
        self.setupChanged = setupStream
        self.receivedContinuation = receivedCont
        self.setupChangedContinuation = setupCont
    }

    // MARK: - Factory

    /// Create a pair of loopback transports
    ///
    /// - Returns: Tuple of (initiator, responder) transports
    ///
    /// Messages sent by the initiator are received by the responder and vice versa.
    public static func createPair() async -> (initiator: LoopbackTransport, responder: LoopbackTransport) {
        let initiator = LoopbackTransport(role: .initiator)
        let responder = LoopbackTransport(role: .responder)

        await initiator.setPeer(responder)
        await responder.setPeer(initiator)

        // Set up default endpoints
        // Initiator sees responder as a destination
        // Responder sees initiator as a destination
        let initiatorSource = MIDISourceInfo(
            sourceID: MIDISourceID(1),
            name: "Loopback Initiator",
            manufacturer: "MIDI2Kit",
            isOnline: true
        )
        let initiatorDest = MIDIDestinationInfo(
            destinationID: MIDIDestinationID(1),
            name: "Loopback Initiator",
            manufacturer: "MIDI2Kit",
            isOnline: true
        )
        let responderSource = MIDISourceInfo(
            sourceID: MIDISourceID(2),
            name: "Loopback Responder",
            manufacturer: "MIDI2Kit",
            isOnline: true
        )
        let responderDest = MIDIDestinationInfo(
            destinationID: MIDIDestinationID(2),
            name: "Loopback Responder",
            manufacturer: "MIDI2Kit",
            isOnline: true
        )

        // Initiator sees: responder as source (to receive from), responder as destination (to send to)
        await initiator.setEndpoints(sources: [responderSource], destinations: [responderDest])

        // Responder sees: initiator as source (to receive from), initiator as destination (to send to)
        await responder.setEndpoints(sources: [initiatorSource], destinations: [initiatorDest])

        return (initiator, responder)
    }

    private func setPeer(_ peer: LoopbackTransport) {
        self._peer = peer
    }

    private func setEndpoints(sources: [MIDISourceInfo], destinations: [MIDIDestinationInfo]) {
        self.mockSources = sources
        self.mockDestinations = destinations
    }

    // MARK: - MIDITransport Protocol

    public func send(_ data: [UInt8], to destination: MIDIDestinationID) async throws {
        guard let peer = _peer else {
            throw MIDITransportError.notInitialized
        }

        // Determine source ID based on role
        let sourceID: MIDISourceID
        switch role {
        case .initiator:
            sourceID = MIDISourceID(1)  // Initiator's source ID
        case .responder:
            sourceID = MIDISourceID(2)  // Responder's source ID
        }

        // Deliver to peer's received stream
        await peer.injectReceived(data, from: sourceID)
    }

    public var sources: [MIDISourceInfo] {
        get async { mockSources }
    }

    public var destinations: [MIDIDestinationInfo] {
        get async { mockDestinations }
    }

    public func connect(to source: MIDISourceID) async throws {
        // No-op for loopback
    }

    public func disconnect(from source: MIDISourceID) async throws {
        // No-op for loopback
    }

    public func connectToAllSources() async throws {
        // No-op for loopback
    }

    public func broadcast(_ data: [UInt8]) async throws {
        // Broadcast to all destinations (which delivers to peer)
        for dest in mockDestinations {
            try await send(data, to: dest.destinationID)
        }
    }

    public func findMatchingDestination(for source: MIDISourceID) async -> MIDIDestinationID? {
        // In loopback, source 1 matches destination 1, source 2 matches destination 2
        return mockDestinations.first?.destinationID
    }

    public func shutdown() async {
        receivedContinuation?.finish()
        setupChangedContinuation?.finish()
        receivedContinuation = nil
        setupChangedContinuation = nil
    }

    // MARK: - Internal

    /// Inject received data (called by peer's send)
    func injectReceived(_ data: [UInt8], from source: MIDISourceID) {
        guard receivedContinuation != nil else {
            // Transport has been shut down, ignore
            return
        }
        let received = MIDIReceivedData(data: data, sourceID: source)
        receivedContinuation?.yield(received)
    }

    /// Notify setup changed
    public func notifySetupChanged() {
        setupChangedContinuation?.yield(())
    }
}

// MARK: - Convenience Extensions

extension LoopbackTransport {

    /// Configure responder device identity
    ///
    /// Updates the source/destination names to reflect the device being simulated
    public func configureAsDevice(name: String, manufacturer: String = "MIDI2Kit") {
        let sourceID = role == .responder ? MIDISourceID(2) : MIDISourceID(1)
        let destID = role == .responder ? MIDIDestinationID(2) : MIDIDestinationID(1)

        mockSources = [
            MIDISourceInfo(
                sourceID: sourceID,
                name: name,
                manufacturer: manufacturer,
                isOnline: true
            )
        ]
        mockDestinations = [
            MIDIDestinationInfo(
                destinationID: destID,
                name: name,
                manufacturer: manufacturer,
                isOnline: true
            )
        ]
    }
}
