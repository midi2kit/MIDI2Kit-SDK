//
//  CoreMIDITransport.swift
//  MIDI2Kit
//
//  CoreMIDI-based transport implementation
//

#if canImport(CoreMIDI)

import Foundation
import CoreMIDI
import MIDI2Core

/// Thread-safe virtual endpoint state management
private final class VirtualEndpointState: @unchecked Sendable {
    private let lock = NSLock()
    private var virtualDestinations: [MIDIDestinationID: MIDIEndpointRef] = [:]
    private var virtualSources: [MIDISourceID: MIDIEndpointRef] = [:]

    func addDestination(_ id: MIDIDestinationID, ref: MIDIEndpointRef) {
        lock.lock()
        defer { lock.unlock() }
        virtualDestinations[id] = ref
    }

    func addSource(_ id: MIDISourceID, ref: MIDIEndpointRef) {
        lock.lock()
        defer { lock.unlock() }
        virtualSources[id] = ref
    }

    func removeDestination(_ id: MIDIDestinationID) -> MIDIEndpointRef? {
        lock.lock()
        defer { lock.unlock() }
        return virtualDestinations.removeValue(forKey: id)
    }

    func removeSource(_ id: MIDISourceID) -> MIDIEndpointRef? {
        lock.lock()
        defer { lock.unlock() }
        return virtualSources.removeValue(forKey: id)
    }

    func sourceRef(for id: MIDISourceID) -> MIDIEndpointRef? {
        lock.lock()
        defer { lock.unlock() }
        return virtualSources[id]
    }

    func isVirtualDestination(_ id: MIDIDestinationID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return virtualDestinations[id] != nil
    }

    func allDestinations() -> [MIDIDestinationID: MIDIEndpointRef] {
        lock.lock()
        defer { lock.unlock() }
        return virtualDestinations
    }

    func allSources() -> [MIDISourceID: MIDIEndpointRef] {
        lock.lock()
        defer { lock.unlock() }
        return virtualSources
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        virtualDestinations.removeAll()
        virtualSources.removeAll()
    }
}

/// Thread-safe connection state management (sync + async compatible)
private final class ConnectionState: @unchecked Sendable {
    private let lock = NSLock()
    private var connectedSources: Set<MIDIEndpointRef> = .init()
    
    func isConnected(_ source: MIDIEndpointRef) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return connectedSources.contains(source)
    }
    
    func markConnected(_ source: MIDIEndpointRef) {
        lock.lock()
        defer { lock.unlock() }
        connectedSources.insert(source)
    }
    
    func markDisconnected(_ source: MIDIEndpointRef) {
        lock.lock()
        defer { lock.unlock() }
        connectedSources.remove(source)
    }
    
    func getConnected() -> Set<MIDIEndpointRef> {
        lock.lock()
        defer { lock.unlock() }
        return connectedSources
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        connectedSources.removeAll()
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return connectedSources.count
    }
}

/// CoreMIDI-based transport implementation
///
/// Key features:
/// - Connection state tracking to prevent duplicate connections
/// - Automatic reconnection on setup changes
/// - SysEx assembly for fragmented messages
/// - Source ID tracking for received messages
/// - Optional message tracing for diagnostics
/// - MIDI 2.0 UMP support via `sendUMP` method
public final class CoreMIDITransport: MIDITransport, @unchecked Sendable {
    
    // MARK: - Private State
    
    private var client: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var inputPort: MIDIPortRef = 0
    
    private let sysExAssembler = SysExAssembler()
    
    /// Connection state (thread-safe, sync accessible for deinit)
    private let connectionState = ConnectionState()

    /// Virtual endpoint state (thread-safe)
    private let virtualEndpointState = VirtualEndpointState()

    /// Shutdown state (thread-safe)
    private let shutdownLock = NSLock()
    private var didShutdown = false

    
    private var receivedContinuation: AsyncStream<MIDIReceivedData>.Continuation?
    private var setupChangedContinuation: AsyncStream<Void>.Continuation?
    
    // MARK: - Public Properties
    
    /// Optional tracer for message logging
    ///
    /// Set this to enable automatic tracing of all sent/received messages:
    /// ```swift
    /// transport.tracer = MIDITracer(capacity: 500)
    /// // ... later ...
    /// print(transport.tracer?.dump() ?? "")
    /// ```
    public var tracer: MIDITracer?
    
    // MARK: - Public Streams
    
    public let received: AsyncStream<MIDIReceivedData>
    public let setupChanged: AsyncStream<Void>
    
    // MARK: - Initialization
    
    public init(clientName: String = "MIDI2Kit") throws {
        // Use makeStream() to ensure continuations are available immediately
        // The old closure-based approach had a race condition where continuation
        // was nil until the stream was first iterated
        let (receivedStream, receivedCont) = AsyncStream<MIDIReceivedData>.makeStream()
        let (setupStream, setupCont) = AsyncStream<Void>.makeStream()

        self.received = receivedStream
        self.setupChanged = setupStream
        self.receivedContinuation = receivedCont
        self.setupChangedContinuation = setupCont

        // Setup CoreMIDI
        try setupCoreMIDI(clientName: clientName)
    }
    
    deinit {
        // Warn in debug builds if shutdown() was not called explicitly
        #if DEBUG
        shutdownLock.lock()
        let wasProperlyShutdown = didShutdown
        shutdownLock.unlock()
        if !wasProperlyShutdown {
            // This is not a crash - just a development warning
            // The shutdownSync() below will safely clean up
            assertionFailure("CoreMIDITransport released without calling shutdown() - this may race with in-flight sends")
        }
        #endif
        shutdownSync()
    }
    
    // MARK: - Setup
    
    private func setupCoreMIDI(clientName: String) throws {
        // Create MIDI client
        var clientRef: MIDIClientRef = 0
        let status = MIDIClientCreateWithBlock(
            clientName as CFString,
            &clientRef
        ) { [weak self] notification in
            self?.handleNotification(notification)
        }
        
        guard status == noErr else {
            throw MIDITransportError.clientCreationFailed(status)
        }
        self.client = clientRef
        
        // Create output port
        var outPort: MIDIPortRef = 0
        let outStatus = MIDIOutputPortCreate(client, "Output" as CFString, &outPort)
        guard outStatus == noErr else {
            throw MIDITransportError.portCreationFailed(outStatus)
        }
        self.outputPort = outPort
        
        // Create input port using protocol-aware API (supports MIDI 2.0 devices)
        // Using ._1_0 so CoreMIDI translates all incoming data to MIDI 1.0 byte stream,
        // which is compatible with the existing handlePacketList/handleReceivedData path.
        var inPort: MIDIPortRef = 0
        let inStatus = MIDIInputPortCreateWithProtocol(
            client,
            "Input" as CFString,
            ._1_0,
            &inPort
        ) { [weak self] eventList, srcConnRefCon in
            // Extract source from connRefCon (passed via MIDIPortConnectSource)
            let sourceRef: MIDIEndpointRef?
            if let refCon = srcConnRefCon {
                sourceRef = MIDIEndpointRef(UInt(bitPattern: refCon))
            } else {
                sourceRef = nil
            }
            self?.handleEventList(eventList, from: sourceRef)
        }

        guard inStatus == noErr else {
            throw MIDITransportError.portCreationFailed(inStatus)
        }
        self.inputPort = inPort
    }
    
    // MARK: - MIDITransport Protocol

    /// Shut down the transport and finish all streams.
    ///
    /// This is safe to call multiple times (idempotent).
    ///
    /// - Important: Call this method before releasing the transport to ensure
    ///   all pending sends complete gracefully. If not called, deinit will
    ///   perform synchronous shutdown which may race with in-flight operations.
    public func shutdown() async {
        shutdownSync()
    }

    private func shutdownSync() {
        shutdownLock.lock()
        defer { shutdownLock.unlock() }
        guard !didShutdown else { return }
        didShutdown = true

        // Dispose all virtual endpoints before ports
        let virtualDests = virtualEndpointState.allDestinations()
        for (_, ref) in virtualDests {
            MIDIEndpointDispose(ref)
        }
        let virtualSrcs = virtualEndpointState.allSources()
        for (_, ref) in virtualSrcs {
            MIDIEndpointDispose(ref)
        }
        virtualEndpointState.clear()

        // Disconnect all sources synchronously
        let connected = connectionState.getConnected()
        for source in connected {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectionState.clear()

        // Dispose ports before disposing client
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
            outputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }

        receivedContinuation?.finish()
        setupChangedContinuation?.finish()
        receivedContinuation = nil
        setupChangedContinuation = nil
    }

    
    public func send(_ data: [UInt8], to destination: MIDIDestinationID) async throws {
        // Fast-fail if transport has been shut down.
        // Note: we still re-check under the lock right before calling MIDISend to avoid
        // a use-after-dispose race with shutdownSync().
        let isShutdown = shutdownLock.withLock { didShutdown || outputPort == 0 }

        guard !isShutdown else {
            throw MIDITransportError.notInitialized
        }
        let destRef = MIDIEndpointRef(destination.value)
        
        // Trace send
        if let tracer = tracer {
            let label = MIDITraceEntry.detectLabel(for: data)
            tracer.recordSend(to: destination.value, data: data, label: label)
        }
        
        // Calculate buffer size:
        // MIDIPacketList header (4 bytes) + MIDIPacket header (10 bytes) + data + padding
        let bufferSize = 1024 + data.count
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        let packetList = UnsafeMutableRawPointer(buffer).bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(packetList)
        
        // Add packet to list
        // Note: MIDIPacketListAdd returns non-optional in Swift, check numPackets instead
        _ = MIDIPacketListAdd(packetList, bufferSize, packet, 0, data.count, data)
        
        // Verify packet was added (MIDIPacketListAdd fails silently if buffer too small)
        guard packetList.pointee.numPackets > 0 else {
            throw MIDITransportError.packetListAddFailed(dataSize: data.count, bufferSize: bufferSize)
        }
        
        // Perform MIDISend while holding shutdownLock to avoid a use-after-dispose
        // race with shutdownSync() disposing the output port.
        let status: OSStatus = try shutdownLock.withLock {
            guard !didShutdown, outputPort != 0 else {
                throw MIDITransportError.notInitialized
            }
            return MIDISend(outputPort, destRef, packetList)
        }
        
        guard status == noErr else {
            throw MIDITransportError.sendFailed(status)
        }
    }
    
    public var sources: [MIDISourceInfo] {
        get async {
            let count = MIDIGetNumberOfSources()
            var result: [MIDISourceInfo] = []
            
            for i in 0..<count {
                let source = MIDIGetSource(i)
                let info = MIDISourceInfo(
                    sourceID: MIDISourceID(UInt32(source)),
                    name: getEndpointName(source),
                    manufacturer: getEndpointManufacturer(source),
                    isOnline: isEndpointOnline(source),
                    uniqueID: getEndpointUniqueID(source)
                )
                result.append(info)
            }
            
            return result
        }
    }
    
    public var destinations: [MIDIDestinationInfo] {
        get async {
            let count = MIDIGetNumberOfDestinations()
            var result: [MIDIDestinationInfo] = []
            
            for i in 0..<count {
                let dest = MIDIGetDestination(i)
                let info = MIDIDestinationInfo(
                    destinationID: MIDIDestinationID(UInt32(dest)),
                    name: getEndpointName(dest),
                    manufacturer: getEndpointManufacturer(dest),
                    isOnline: isEndpointOnline(dest),
                    uniqueID: getEndpointUniqueID(dest)
                )
                result.append(info)
            }
            
            return result
        }
    }
    
    /// Connect to a specific source (idempotent - safe to call multiple times)
    public func connect(to source: MIDISourceID) async throws {
        let sourceRef = MIDIEndpointRef(source.value)
        
        // Skip if already connected
        guard !connectionState.isConnected(sourceRef) else {
            return
        }
        
        // Pass source ref as connRefCon so we can identify it in the callback
        let connRefCon = UnsafeMutableRawPointer(bitPattern: UInt(sourceRef))
        let status = MIDIPortConnectSource(inputPort, sourceRef, connRefCon)
        
        guard status == noErr else {
            throw MIDITransportError.connectionFailed(status)
        }
        
        connectionState.markConnected(sourceRef)
    }
    
    /// Disconnect from a specific source
    public func disconnect(from source: MIDISourceID) async throws {
        let sourceRef = MIDIEndpointRef(source.value)
        
        // Skip if not connected
        guard connectionState.isConnected(sourceRef) else {
            return
        }
        
        let status = MIDIPortDisconnectSource(inputPort, sourceRef)
        
        guard status == noErr else {
            throw MIDITransportError.connectionFailed(status)
        }
        
        connectionState.markDisconnected(sourceRef)
    }
    
    /// Broadcast MIDI data to all destinations
    ///
    /// This sends the same data to every available destination.
    /// Useful for MIDI-CI messages where the correct destination is unknown.
    ///
    /// - Parameter data: MIDI bytes to broadcast
    public func broadcast(_ data: [UInt8]) async throws {
        let count = MIDIGetNumberOfDestinations()
        guard count > 0 else { return }
        
        for i in 0..<count {
            let destRef = MIDIGetDestination(i)
            if destRef != 0 {
                let destID = MIDIDestinationID(UInt32(destRef))
                // Skip our own virtual destinations to prevent feedback loops
                guard !virtualEndpointState.isVirtualDestination(destID) else { continue }
                try await send(data, to: destID)
            }
        }
    }
    
    /// Connect to all available sources (differential - only connects new sources)
    public func connectToAllSources() async throws {
        let count = MIDIGetNumberOfSources()
        var currentSources: Set<MIDIEndpointRef> = .init()
        
        // Gather current sources
        for i in 0..<count {
            let source = MIDIGetSource(i)
            if source != 0 {
                currentSources.insert(source)
            }
        }
        
        let connectedSources = connectionState.getConnected()
        
        // Disconnect removed sources
        let removed = connectedSources.subtracting(currentSources)
        for source in removed {
            MIDIPortDisconnectSource(inputPort, source)
            connectionState.markDisconnected(source)
        }
        
        // Connect new sources (differential) with connRefCon
        let newSources = currentSources.subtracting(connectedSources)
        for source in newSources {
            let connRefCon = UnsafeMutableRawPointer(bitPattern: UInt(source))
            let status = MIDIPortConnectSource(inputPort, source, connRefCon)
            if status == noErr {
                connectionState.markConnected(source)
            }
        }
    }
    
    /// Reconnect all sources (full disconnect then connect)
    /// Use this when you need a clean slate
    public func reconnectAllSources() async throws {
        await disconnectAllSources()
        try await connectToAllSources()
    }
    
    /// Disconnect all sources
    public func disconnectAllSources() async {
        let connected = connectionState.getConnected()
        for source in connected {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectionState.clear()
    }
    
    /// Number of currently connected sources
    public var connectedSourceCount: Int {
        get async {
            connectionState.count
        }
    }
    
    /// Check if a source is connected
    public func isConnected(to source: MIDISourceID) async -> Bool {
        let sourceRef = MIDIEndpointRef(source.value)
        return connectionState.isConnected(sourceRef)
    }
    
    // MARK: - Private Helpers
    
    /// Handle MIDIEventList from MIDIInputPortCreateWithProtocol
    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>, from sourceRef: MIDIEndpointRef?) {
        let sourceID: MIDISourceID?
        if let ref = sourceRef, ref != 0 {
            sourceID = MIDISourceID(UInt32(ref))
        } else {
            sourceID = nil
        }

        // Extract MIDI 1.0 bytes from UMP words in the event list
        var allPacketData: [[UInt8]] = []
        for packet in eventList.unsafeSequence() {
            let wordCount = Int(packet.pointee.wordCount)
            guard wordCount > 0 else { continue }

            // Access UMP words from the packet
            let words: [UInt32] = withUnsafePointer(to: packet.pointee.words) { wordsPtr in
                wordsPtr.withMemoryRebound(to: UInt32.self, capacity: wordCount) { ptr in
                    Array(UnsafeBufferPointer(start: ptr, count: wordCount))
                }
            }

            for word in words {
                let messageType = (word >> 28) & 0x0F

                switch messageType {
                case 0x1:
                    // System Real-Time / System Common (1 word)
                    let status = UInt8((word >> 16) & 0xFF)
                    if status >= 0xF0 {
                        allPacketData.append([status])
                    }

                case 0x2:
                    // MIDI 1.0 Channel Voice (1 word)
                    let status = UInt8((word >> 16) & 0xFF)
                    let data1 = UInt8((word >> 8) & 0xFF)
                    let data2 = UInt8(word & 0xFF)
                    let statusNibble = status >> 4
                    if statusNibble == 0xC || statusNibble == 0xD {
                        // Program Change, Channel Pressure: 2 bytes
                        allPacketData.append([status, data1])
                    } else {
                        // Note On/Off, CC, Pitch Bend, etc.: 3 bytes
                        allPacketData.append([status, data1, data2])
                    }

                case 0x3:
                    // Data / SysEx (64-bit, 2 words)
                    // Extract SysEx bytes from word pair
                    break

                default:
                    break
                }
            }
        }

        Task { [weak self, allPacketData, sourceID] in
            for data in allPacketData {
                await self?.processReceivedData(data, from: sourceID)
            }
        }
    }

    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>, from sourceRef: MIDIEndpointRef?) {
        // Convert sourceRef to MIDISourceID
        let sourceID: MIDISourceID?
        if let ref = sourceRef, ref != 0 {
            sourceID = MIDISourceID(UInt32(ref))
        } else {
            sourceID = nil
        }

        // Use unsafeSequence for safe iteration (macOS 11+)
        // This avoids manual pointer arithmetic which can cause Bus errors
        var allPacketData: [[UInt8]] = []
        for packet in packetList.unsafeSequence() {
            let length = Int(packet.pointee.length)
            guard length > 0 else { continue }
            let data: [UInt8] = withUnsafeBytes(of: packet.pointee.data) { ptr in
                Array(ptr.prefix(length))
            }
            allPacketData.append(data)
        }

        // Process all packets in a single Task to guarantee order
        Task { [weak self, allPacketData, sourceID] in
            for data in allPacketData {
                await self?.processReceivedData(data, from: sourceID)
            }
        }
    }
    
    private func processReceivedData(_ data: [UInt8], from sourceID: MIDISourceID?) async {
        // Assemble SysEx messages
        let messages = await sysExAssembler.process(data)
        
        for message in messages {
            // Trace receive
            if let tracer = tracer {
                let label = MIDITraceEntry.detectLabel(for: message)
                tracer.recordReceive(from: sourceID?.value ?? 0, data: message, label: label)
            }
            
            let received = MIDIReceivedData(data: message, sourceID: sourceID)
            receivedContinuation?.yield(received)
        }
    }
    
    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved:
            setupChangedContinuation?.yield(())
        default:
            break
        }
    }
    
private func getEndpointName(_ endpoint: MIDIEndpointRef) -> String {
    func read(_ prop: CFString) -> String? {
        var unmanaged: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, prop, &unmanaged)
        guard status == noErr, let cf = unmanaged?.takeRetainedValue() else { return nil }
        let s = (cf as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // Prefer the raw name (often closer to a “port/module name”)
    if let name = read(kMIDIPropertyName) {
        return name
    }
    // Fallback to display name
    if let display = read(kMIDIPropertyDisplayName) {
        return display
    }
    return "Unknown"
}


    
    private func getEndpointManufacturer(_ endpoint: MIDIEndpointRef) -> String? {
        var manufacturer: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyManufacturer, &manufacturer)
        return manufacturer?.takeRetainedValue() as String?
    }
    
    private func isEndpointOnline(_ endpoint: MIDIEndpointRef) -> Bool {
        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
        return offline == 0
    }
    
    /// Get the persistent unique ID for an endpoint
    ///
    /// - Parameter endpoint: The MIDI endpoint reference
    /// - Returns: The unique ID, or `nil` if unavailable
    ///
    /// - Note: `kMIDIPropertyUniqueID` returns 0 for some virtual endpoints.
    ///         We treat 0 as "unavailable" and return `nil`.
    private func getEndpointUniqueID(_ endpoint: MIDIEndpointRef) -> Int32? {
        var uniqueID: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
        
        // Return nil if property unavailable or if uniqueID is 0 (invalid/unset)
        guard status == noErr, uniqueID != 0 else {
            return nil
        }
        return uniqueID
    }
    
    // MARK: - Entity-based Destination Lookup
    
    /// Find the destination that belongs to the same entity as a source
    ///
    /// In CoreMIDI, endpoints are organized as:
    /// ```
    /// Device
    ///   └── Entity (physical port)
    ///        ├── Source (input from device)
    ///        └── Destination (output to device)
    /// ```
    ///
    /// This method finds the destination endpoint that shares the same entity
    /// as the given source, enabling proper bidirectional communication.
    ///
    /// ## Fallback Strategy
    /// 1. Entity-based lookup (most reliable for physical devices)
    /// 2. Name-based matching (for virtual endpoints without entities)
    ///
    /// - Parameter source: The source to find a matching destination for
    /// - Returns: The matching destination, or `nil` if none found
    public func findMatchingDestination(for source: MIDISourceID) async -> MIDIDestinationID? {
        let sourceRef = MIDIEndpointRef(source.value)
        
        // Strategy 1: Entity-based lookup
        if let destination = findDestinationViaEntity(for: sourceRef) {
            return destination
        }
        
        // Strategy 2: Name-based fallback (for virtual endpoints)
        return findDestinationByName(for: sourceRef)
    }
    
    /// Find destination via entity relationship
    ///
    /// For multiport devices (multiple sources/destinations per entity),
    /// we match the source index to the destination index to avoid
    /// sending to the wrong port.
    private func findDestinationViaEntity(for sourceRef: MIDIEndpointRef) -> MIDIDestinationID? {
        var entity: MIDIEntityRef = 0
        let status = MIDIEndpointGetEntity(sourceRef, &entity)
        
        // Virtual endpoints may not have an entity
        guard status == noErr, entity != 0 else {
            return nil
        }
        
        // Find destinations belonging to the same entity
        let destCount = MIDIEntityGetNumberOfDestinations(entity)
        guard destCount > 0 else {
            return nil
        }
        
        // Find which source index this sourceRef is within the entity
        let sourceCount = MIDIEntityGetNumberOfSources(entity)
        var sourceIndex: Int = 0
        
        for i in 0..<sourceCount {
            if MIDIEntityGetSource(entity, i) == sourceRef {
                sourceIndex = i
                break
            }
        }
        
        // Use matching destination index if available, otherwise fallback to 0
        let destIndex = sourceIndex < destCount ? sourceIndex : 0
        let destRef = MIDIEntityGetDestination(entity, destIndex)
        
        guard destRef != 0 else {
            return nil
        }
        
        return MIDIDestinationID(UInt32(destRef))
    }
    
    /// Fallback: find destination by matching name (for virtual endpoints)
    private func findDestinationByName(for sourceRef: MIDIEndpointRef) -> MIDIDestinationID? {
        let sourceName = getEndpointName(sourceRef)
        
        // Common naming patterns for paired endpoints
        let candidateNames = [
            sourceName,
            sourceName.replacingOccurrences(of: " In", with: " Out"),
            sourceName.replacingOccurrences(of: " Input", with: " Output"),
            sourceName.replacingOccurrences(of: " Source", with: " Destination")
        ]
        
        let destCount = MIDIGetNumberOfDestinations()
        for i in 0..<destCount {
            let destRef = MIDIGetDestination(i)
            let destName = getEndpointName(destRef)
            
            if candidateNames.contains(destName) {
                return MIDIDestinationID(UInt32(destRef))
            }
        }
        
        return nil
    }
    
    // MARK: - MIDI 2.0 UMP Support
    
    /// Send UMP (Universal MIDI Packet) words to a destination
    ///
    /// This method uses `MIDIEventList` for MIDI 2.0 protocol transmission.
    /// Use this for sending high-resolution MIDI 2.0 Channel Voice messages.
    ///
    /// ## Usage Example
    ///
    /// ```swift
    /// import MIDI2Core
    ///
    /// // Build a MIDI 2.0 Control Change message
    /// let words = UMPBuilder.midi2ControlChange(
    ///     group: 0,
    ///     channel: 0,
    ///     controller: 74,
    ///     value: 0x80000000
    /// )
    ///
    /// // Send via UMP
    /// try await transport.sendUMP(words, to: destination)
    /// ```
    ///
    /// - Parameters:
    ///   - words: Array of 32-bit UMP words (1, 2, or 4 words depending on message type)
    ///   - destination: Destination endpoint ID
    ///   - protocol: MIDI protocol version (default: MIDI 2.0)
    /// - Throws: `MIDITransportError` if send fails
    public func sendUMP(
        _ words: [UInt32],
        to destination: MIDIDestinationID,
        protocol midiProtocol: MIDIProtocolID = ._2_0
    ) async throws {
        guard !words.isEmpty else { return }
        
        let destRef = MIDIEndpointRef(destination.value)
        
        // Trace send (convert words to bytes for logging)
        if let tracer = tracer {
            var bytes: [UInt8] = []
            for word in words {
                bytes.append(UInt8((word >> 24) & 0xFF))
                bytes.append(UInt8((word >> 16) & 0xFF))
                bytes.append(UInt8((word >> 8) & 0xFF))
                bytes.append(UInt8(word & 0xFF))
            }
            tracer.recordSend(to: destination.value, data: bytes, label: "UMP")
        }
        
        // Build MIDIEventList
        var eventList = MIDIEventList()
        var packet = MIDIEventPacket()
        packet.timeStamp = 0
        packet.wordCount = UInt32(words.count)
        
        // Copy words to packet
        withUnsafeMutablePointer(to: &packet.words) { ptr in
            let wordsPtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: UInt32.self)
            for (index, word) in words.enumerated() {
                wordsPtr[index] = word
            }
        }
        
        eventList.protocol = midiProtocol
        eventList.numPackets = 1
        eventList.packet = packet
        
        let status = MIDISendEventList(outputPort, destRef, &eventList)
        
        guard status == noErr else {
            throw MIDITransportError.sendFailed(status)
        }
    }
    
    /// Send multiple UMP messages in a single call
    ///
    /// - Parameters:
    ///   - messages: Array of UMP word arrays
    ///   - destination: Destination endpoint ID
    ///   - protocol: MIDI protocol version (default: MIDI 2.0)
    /// - Throws: `MIDITransportError` if send fails
    public func sendUMPBatch(
        _ messages: [[UInt32]],
        to destination: MIDIDestinationID,
        protocol midiProtocol: MIDIProtocolID = ._2_0
    ) async throws {
        for words in messages {
            try await sendUMP(words, to: destination, protocol: midiProtocol)
        }
    }
    
    /// Check if a destination supports MIDI 2.0 protocol
    ///
    /// - Parameter destination: Destination endpoint ID
    /// - Returns: `true` if the destination supports MIDI 2.0
    public func supportsMIDI2(_ destination: MIDIDestinationID) -> Bool {
        let destRef = MIDIEndpointRef(destination.value)
        var protocolID: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(destRef, kMIDIPropertyProtocolID, &protocolID)
        
        if status == noErr {
            // kMIDIProtocol_2_0 = 2
            return protocolID == 2
        }
        return false
    }
    
    /// Get the supported MIDI protocol for a destination
    ///
    /// - Parameter destination: Destination endpoint ID
    /// - Returns: The protocol ID, or `._1_0` if unavailable
    public func midiProtocol(for destination: MIDIDestinationID) -> MIDIProtocolID {
        let destRef = MIDIEndpointRef(destination.value)
        var protocolID: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(destRef, kMIDIPropertyProtocolID, &protocolID)

        if status == noErr, protocolID == 2 {
            return ._2_0
        }
        return ._1_0
    }

    /// Detect the transport type for a destination endpoint
    ///
    /// - Parameter destination: Destination endpoint ID
    /// - Returns: Detected transport type
    public func transportType(for destination: MIDIDestinationID) -> MIDITransportType {
        MIDITransportType.detect(for: MIDIEndpointRef(destination.value))
    }
}

// MARK: - VirtualEndpointCapable

extension CoreMIDITransport: VirtualEndpointCapable {

    public func createVirtualDestination(name: String) async throws -> MIDIDestinationID {
        let isShutdown = shutdownLock.withLock { didShutdown }
        guard !isShutdown else {
            throw MIDITransportError.notInitialized
        }

        var endpointRef: MIDIEndpointRef = 0
        let status = MIDIDestinationCreateWithBlock(
            client,
            name as CFString,
            &endpointRef
        ) { [weak self] packetList, _ in
            self?.handleVirtualDestinationPacketList(packetList)
        }

        guard status == noErr else {
            throw MIDITransportError.virtualEndpointCreationFailed(status)
        }

        let destID = MIDIDestinationID(UInt32(endpointRef))
        virtualEndpointState.addDestination(destID, ref: endpointRef)
        return destID
    }

    public func createVirtualSource(name: String) async throws -> MIDISourceID {
        let isShutdown = shutdownLock.withLock { didShutdown }
        guard !isShutdown else {
            throw MIDITransportError.notInitialized
        }

        var endpointRef: MIDIEndpointRef = 0
        let status = MIDISourceCreate(client, name as CFString, &endpointRef)

        guard status == noErr else {
            throw MIDITransportError.virtualEndpointCreationFailed(status)
        }

        let sourceID = MIDISourceID(UInt32(endpointRef))
        virtualEndpointState.addSource(sourceID, ref: endpointRef)
        return sourceID
    }

    public func removeVirtualDestination(_ id: MIDIDestinationID) async throws {
        guard let ref = virtualEndpointState.removeDestination(id) else {
            throw MIDITransportError.virtualEndpointNotFound(id.value)
        }

        let status = MIDIEndpointDispose(ref)
        guard status == noErr else {
            throw MIDITransportError.virtualEndpointDisposeFailed(status)
        }
    }

    public func removeVirtualSource(_ id: MIDISourceID) async throws {
        guard let ref = virtualEndpointState.removeSource(id) else {
            throw MIDITransportError.virtualEndpointNotFound(id.value)
        }

        let status = MIDIEndpointDispose(ref)
        guard status == noErr else {
            throw MIDITransportError.virtualEndpointDisposeFailed(status)
        }
    }

    public func sendFromVirtualSource(_ data: [UInt8], source: MIDISourceID) async throws {
        guard let sourceRef = virtualEndpointState.sourceRef(for: source) else {
            throw MIDITransportError.virtualEndpointNotFound(source.value)
        }

        // Trace send
        if let tracer = tracer {
            let label = MIDITraceEntry.detectLabel(for: data)
            tracer.recordSend(to: source.value, data: data, label: "VS:\(label ?? "Unknown")")
        }

        let bufferSize = 1024 + data.count
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        let packetList = UnsafeMutableRawPointer(buffer).bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(packetList)

        _ = MIDIPacketListAdd(packetList, bufferSize, packet, 0, data.count, data)

        guard packetList.pointee.numPackets > 0 else {
            throw MIDITransportError.packetListAddFailed(dataSize: data.count, bufferSize: bufferSize)
        }

        // MIDIReceived under shutdownLock to prevent use-after-dispose
        let status: OSStatus = try shutdownLock.withLock {
            guard !didShutdown else {
                throw MIDITransportError.notInitialized
            }
            return MIDIReceived(sourceRef, packetList)
        }

        guard status == noErr else {
            throw MIDITransportError.sendFailed(status)
        }
    }

    // MARK: - Virtual Destination Packet Handling

    /// Handle packets received on a virtual destination.
    ///
    /// Called from CoreMIDI's internal thread when another app sends data
    /// to one of our virtual destinations.
    private func handleVirtualDestinationPacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        var allPacketData: [[UInt8]] = []
        for packet in packetList.unsafeSequence() {
            let length = Int(packet.pointee.length)
            guard length > 0 else { continue }
            let data: [UInt8] = withUnsafeBytes(of: packet.pointee.data) { ptr in
                Array(ptr.prefix(length))
            }
            allPacketData.append(data)
        }

        // Process on async context; sourceID is nil for virtual destinations
        Task { [weak self, allPacketData] in
            for data in allPacketData {
                await self?.processReceivedData(data, from: nil)
            }
        }
    }
}

#endif
