//
//  MIDI2Transport.swift
//  MIDI2Kit
//
//  Transport layer abstraction
//

/// # MIDI2Transport
///
/// CoreMIDI abstraction with connection management and testing support.
///
/// ## Overview
///
/// MIDI2Transport provides a clean abstraction over CoreMIDI with:
///
/// - **Connection Management**: Automatic handling of device connections
/// - **Duplicate Prevention**: Differential connection prevents double-connections
/// - **SysEx Assembly**: Handles fragmented SysEx messages
/// - **Setup Change Handling**: Notifications when MIDI configuration changes
/// - **Testing Support**: MockMIDITransport for hardware-free testing
///
/// ## Basic Usage
///
/// ```swift
/// import MIDI2Transport
///
/// // Create transport
/// let transport = try CoreMIDITransport(clientName: "MyApp")
///
/// // Connect to all MIDI sources
/// try await transport.connectToAllSources()
///
/// // Send MIDI data
/// let destination = (await transport.destinations).first!
/// try await transport.send([0x90, 0x3C, 0x7F], to: destination.destinationID)
///
/// // Receive MIDI data
/// Task {
///     for await data in transport.received {
///         print("Received: \(data.data)")
///     }
/// }
/// ```
///
/// ## Sending UMP Messages
///
/// ```swift
/// // Send MIDI 2.0 messages
/// let noteOn = UMP.noteOn(channel: 0, note: 60, velocity: 0x8000)
/// try await transport.send(noteOn, to: destination)
///
/// // Send MIDI 1.0 compatible messages
/// let cc = UMP.midi1.volume(channel: 0, value: 100)
/// try await transport.send(cc, to: destination)
///
/// // Convenience methods
/// try await transport.sendNoteOn(channel: 0, note: 60, velocity: 0x8000, to: destination)
/// try await transport.sendControlChange(channel: 0, controller: 7, value: 0x80000000, to: destination)
/// try await transport.sendAllNotesOff(channel: 0, to: destination)
/// ```
///
/// ## Handling Setup Changes
///
/// ```swift
/// // Monitor for MIDI device changes
/// Task {
///     for await _ in transport.setupChanged {
///         // Devices were added/removed - reconnect
///         try await transport.connectToAllSources()
///         
///         // Update UI with new device list
///         let sources = await transport.sources
///         let destinations = await transport.destinations
///     }
/// }
/// ```
///
/// ## Connection States
///
/// ```swift
/// // Check connection status
/// let isConnected = await transport.isConnected(to: sourceID)
/// let count = await transport.connectedSourceCount
///
/// // Differential connect (only connects new sources)
/// try await transport.connectToAllSources()
///
/// // Full reconnect (disconnects all, then connects all)
/// try await transport.reconnectAllSources()
///
/// // Disconnect specific source
/// try await transport.disconnect(from: sourceID)
/// ```
///
/// ## Finding Matching Destinations
///
/// For MIDI-CI communication, you need to send responses back to the same device:
///
/// ```swift
/// // Find the destination endpoint for a source
/// if let destination = await transport.findMatchingDestination(for: sourceID) {
///     try await transport.send(responseData, to: destination)
/// }
/// ```
///
/// ## Persistent Device Identification
///
/// The `MIDISourceID` and `MIDIDestinationID` are session-scoped handles that may
/// change across reboots. For persistent identification, use `uniqueID`:
///
/// ```swift
/// let source = (await transport.sources).first!
///
/// // Session-scoped (may change)
/// let sessionID = source.sourceID  // MIDISourceID
///
/// // Persistent across sessions
/// if let persistentID = source.uniqueID {
///     // Save this for later matching
///     UserDefaults.standard.set(persistentID, forKey: "lastDevice")
/// }
///
/// // Later, find device by persistent ID
/// let savedID = UserDefaults.standard.integer(forKey: "lastDevice")
/// let sources = await transport.sources
/// if let match = sources.first(where: { $0.uniqueID == Int32(savedID) }) {
///     try await transport.connect(to: match.sourceID)
/// }
/// ```
///
/// ## Testing with MockMIDITransport
///
/// ```swift
/// import MIDI2Transport
///
/// // Create mock transport
/// let mock = MockMIDITransport()
///
/// // Configure mock endpoints
/// await mock.addMockSource(MIDISourceInfo(
///     sourceID: MIDISourceID(1),
///     name: "Test Device",
///     uniqueID: 12345
/// ))
///
/// // Inject received data (simulates device sending data)
/// await mock.injectReceived([0xF0, 0x7E, 0x7F, ...])
///
/// // Check what was sent
/// let sent = await mock.sentMessages
/// XCTAssertTrue(await mock.wasSent(ciMessageType: 0x70))
/// ```
///
/// ## Topics
///
/// ### Protocol
/// - ``MIDITransport``
///
/// ### Implementations
/// - ``CoreMIDITransport``
/// - ``MockMIDITransport``
///
/// ### Endpoint Types
/// - ``MIDISourceID``
/// - ``MIDIDestinationID``
/// - ``MIDISourceInfo``
/// - ``MIDIDestinationInfo``
/// - ``MIDIReceivedData``
///
/// ### Errors
/// - ``MIDITransportError``
///
/// ### Internal
/// - ``SysExAssembler``

@_exported import MIDI2Core
