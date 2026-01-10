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
public final class CoreMIDITransport: MIDITransport, @unchecked Sendable {
    
    // MARK: - Private State
    
    private var client: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var inputPort: MIDIPortRef = 0
    
    private let sysExAssembler = SysExAssembler()
    
    /// Connection state (thread-safe, sync accessible for deinit)
    private let connectionState = ConnectionState()
    
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
        // Initialize streams
        var receivedCont: AsyncStream<MIDIReceivedData>.Continuation?
        self.received = AsyncStream { continuation in
            receivedCont = continuation
        }
        
        var setupCont: AsyncStream<Void>.Continuation?
        self.setupChanged = AsyncStream { continuation in
            setupCont = continuation
        }
        
        // Store continuations
        self.receivedContinuation = receivedCont
        self.setupChangedContinuation = setupCont
        
        // Setup CoreMIDI
        try setupCoreMIDI(clientName: clientName)
    }
    
    deinit {
        // Disconnect all sources synchronously
        let connected = connectionState.getConnected()
        for source in connected {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectionState.clear()
        
        if client != 0 {
            MIDIClientDispose(client)
        }
        receivedContinuation?.finish()
        setupChangedContinuation?.finish()
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
        
        // Create input port with source tracking via connRefCon
        var inPort: MIDIPortRef = 0
        let inStatus = MIDIInputPortCreateWithBlock(
            client,
            "Input" as CFString,
            &inPort
        ) { [weak self] packetList, srcConnRefCon in
            // Extract source from connRefCon (passed via MIDIPortConnectSource)
            let sourceRef: MIDIEndpointRef?
            if let refCon = srcConnRefCon {
                sourceRef = MIDIEndpointRef(UInt(bitPattern: refCon))
            } else {
                sourceRef = nil
            }
            self?.handlePacketList(packetList, from: sourceRef)
        }
        
        guard inStatus == noErr else {
            throw MIDITransportError.portCreationFailed(inStatus)
        }
        self.inputPort = inPort
    }
    
    // MARK: - MIDITransport Protocol
    
    public func send(_ data: [UInt8], to destination: MIDIDestinationID) async throws {
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
        
        let status = MIDISend(outputPort, destRef, packetList)
        
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
    
    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>, from sourceRef: MIDIEndpointRef?) {
        var packet = packetList.pointee.packet
        let numPackets = packetList.pointee.numPackets
        
        // Convert sourceRef to MIDISourceID
        let sourceID: MIDISourceID?
        if let ref = sourceRef, ref != 0 {
            sourceID = MIDISourceID(UInt32(ref))
        } else {
            sourceID = nil
        }
        
        // Collect all packet data first to preserve order
        var allPacketData: [[UInt8]] = []
        allPacketData.reserveCapacity(Int(numPackets))
        
        for _ in 0..<numPackets {
            let length = Int(packet.length)
            // Use withUnsafeBytes instead of Mirror for performance
            let data: [UInt8] = withUnsafeBytes(of: packet.data) { ptr in
                Array(ptr.prefix(length))
            }
            allPacketData.append(data)
            packet = MIDIPacketNext(&packet).pointee
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
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        return (name?.takeRetainedValue() as String?) ?? "Unknown"
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
}

#endif
