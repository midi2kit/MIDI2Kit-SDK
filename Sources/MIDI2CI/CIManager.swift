//
//  CIManager.swift
//  MIDI2Kit
//
//  High-level MIDI-CI management with automatic discovery
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - Configuration

/// Configuration for CIManager
public struct CIManagerConfiguration: Sendable {
    /// How often to send Discovery Inquiry (seconds)
    public var discoveryInterval: TimeInterval
    
    /// How long before a device is considered lost (seconds)
    public var deviceTimeout: TimeInterval
    
    /// Whether to automatically start discovery when start() is called
    public var autoStartDiscovery: Bool
    
    /// Whether to respond to Discovery Inquiries (act as Responder)
    public var respondToDiscovery: Bool
    
    /// Category support to advertise
    public var categorySupport: CategorySupport
    
    /// Device identity to advertise
    public var deviceIdentity: DeviceIdentity
    
    /// Maximum SysEx size (0 = no limit)
    public var maxSysExSize: UInt32
    
    public init(
        discoveryInterval: TimeInterval = 5.0,
        deviceTimeout: TimeInterval = 15.0,
        autoStartDiscovery: Bool = true,
        respondToDiscovery: Bool = true,
        categorySupport: CategorySupport = .propertyExchange,
        deviceIdentity: DeviceIdentity = .default,
        maxSysExSize: UInt32 = 0
    ) {
        self.discoveryInterval = discoveryInterval
        self.deviceTimeout = deviceTimeout
        self.autoStartDiscovery = autoStartDiscovery
        self.respondToDiscovery = respondToDiscovery
        self.categorySupport = categorySupport
        self.deviceIdentity = deviceIdentity
        self.maxSysExSize = maxSysExSize
    }
    
    /// Default configuration
    public static let `default` = CIManagerConfiguration()
}

// MARK: - Events

/// Device discovery and lifecycle events
public enum CIManagerEvent: Sendable {
    case deviceDiscovered(DiscoveredDevice)
    case deviceLost(MUID)
    case deviceUpdated(DiscoveredDevice)
    case discoveryStarted
    case discoveryStopped
}

// MARK: - CIManager

/// High-level MIDI-CI manager with automatic device discovery
///
/// CIManager handles:
/// - Automatic Discovery Inquiry broadcasts
/// - Device lifecycle tracking (discovered/updated/lost)
/// - Device timeout detection
/// - PE capability filtering
/// - Optionally responds to Discovery Inquiries (Responder mode)
///
/// Example usage:
/// ```swift
/// let transport = try CoreMIDITransport(clientName: "MyApp")
/// let manager = CIManager(transport: transport)
/// try await manager.start()
///
/// for await event in manager.events {
///     switch event {
///     case .deviceDiscovered(let device):
///         print("Found: \(device.displayName)")
///     case .deviceLost(let muid):
///         print("Lost: \(muid)")
///     default:
///         break
///     }
/// }
/// ```
public actor CIManager {
    
    // MARK: - Properties
    
    /// This manager's MUID
    public nonisolated let muid: MUID
    
    /// Configuration
    public nonisolated let configuration: CIManagerConfiguration
    
    /// Underlying transport
    private let transport: any MIDITransport
    
    /// Discovered devices indexed by MUID
    private var devices: [MUID: DeviceEntry] = [:]
    
    /// Device entry with metadata
    private struct DeviceEntry {
        let device: DiscoveredDevice
        var lastSeen: Date
        var sourceID: MIDISourceID?
        var destination: MIDIDestinationID?
    }
    
    /// Event stream continuation
    private var eventContinuation: AsyncStream<CIManagerEvent>.Continuation?
    
    /// Event stream
    @available(*, deprecated, message: "Use MIDI2Client.makeEventStream() instead")
    public nonisolated let events: AsyncStream<CIManagerEvent>
    
    /// Running state
    private var isRunning = false
    
    /// Discovery task
    private var discoveryTask: Task<Void, Never>?
    
    /// Receive task
    private var receiveTask: Task<Void, Never>?
    
    /// Timeout check task
    private var timeoutTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Initialize with transport and configuration
    public init(
        transport: any MIDITransport,
        muid: MUID? = nil,
        configuration: CIManagerConfiguration = .default
    ) {
        self.transport = transport
        self.muid = muid ?? MUID.random()
        self.configuration = configuration
        
        var continuation: AsyncStream<CIManagerEvent>.Continuation?
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }
    
    /// Convenience initializer with default configuration
    public init(transport: any MIDITransport) {
        self.init(transport: transport, muid: nil, configuration: .default)
    }
    
    /// Convenience initializer with specific MUID
    public init(transport: any MIDITransport, muid: MUID) {
        self.init(transport: transport, muid: muid, configuration: .default)
    }
    
    deinit {
        // Cancel all background tasks
        discoveryTask?.cancel()
        receiveTask?.cancel()
        timeoutTask?.cancel()
        
        // Finish event stream
        eventContinuation?.finish()
        
        // Note: Device lost events will NOT be emitted during deinit.
        // For proper cleanup with events, call stop() before releasing CIManager.
    }
    
    // MARK: - Lifecycle
    
    /// Start the CI manager
    @available(*, deprecated, message: "Use MIDI2Client.start() instead")
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        
        // Start receiving messages
        receiveTask = Task { [weak self] in
            guard let self else { return }
            for await received in transport.received {
                // Check cancellation inside loop since AsyncStream doesn't throw on cancel
                if Task.isCancelled { break }
                await self.handleReceived(received)
            }
        }
        
        // Start timeout checking
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            await self.runTimeoutChecker()
        }
        
        // Auto-start discovery if configured
        if configuration.autoStartDiscovery {
            startDiscovery()
        }
    }
    
    /// Stop the CI manager
    @available(*, deprecated, message: "Use MIDI2Client.stop() instead")
    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        
        discoveryTask?.cancel()
        receiveTask?.cancel()
        timeoutTask?.cancel()
        
        discoveryTask = nil
        receiveTask = nil
        timeoutTask = nil
        
        eventContinuation?.yield(.discoveryStopped)
    }
    
    // MARK: - Discovery
    
    /// Start periodic discovery broadcasts
    @available(*, deprecated, message: "Use MIDI2Client (discovery starts automatically)")
    public func startDiscovery() {
        guard discoveryTask == nil else { return }
        
        eventContinuation?.yield(.discoveryStarted)
        
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                await self.sendDiscoveryInquiry()
                
                do {
                    try await Task.sleep(for: .seconds(configuration.discoveryInterval))
                } catch {
                    break
                }
            }
        }
    }
    
    /// Stop periodic discovery
    @available(*, deprecated, message: "Use MIDI2Client (discovery stops automatically)")
    public func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        eventContinuation?.yield(.discoveryStopped)
    }
    
    /// Send a single Discovery Inquiry
    public func sendDiscoveryInquiry() async {
        let message = CIMessageBuilder.discoveryInquiry(
            sourceMUID: muid,
            deviceIdentity: configuration.deviceIdentity,
            categorySupport: configuration.categorySupport,
            maxSysExSize: configuration.maxSysExSize
        )
        
        // Send to all destinations (broadcast)
        let destinations = await transport.destinations
        for dest in destinations {
            do {
                try await transport.send(message, to: dest.destinationID)
            } catch {
                // Continue with other destinations
            }
        }
    }
    
    /// Invalidate this manager's MUID (call when shutting down)
    public func invalidateMUID() async {
        let message = CIMessageBuilder.invalidateMUID(
            sourceMUID: muid,
            targetMUID: MUID.broadcast
        )
        
        let destinations = await transport.destinations
        for dest in destinations {
            try? await transport.send(message, to: dest.destinationID)
        }
    }
    
    // MARK: - Device Access
    
    /// All discovered devices
    public var discoveredDevices: [DiscoveredDevice] {
        devices.values.map(\.device)
    }
    
    /// Devices that support Property Exchange
    public var peCapableDevices: [DiscoveredDevice] {
        discoveredDevices.filter(\.supportsPropertyExchange)
    }
    
    /// Get a specific device by MUID
    public func device(for muid: MUID) -> DiscoveredDevice? {
        devices[muid]?.device
    }
    
    /// Get destination for a device
    @available(*, deprecated, message: "Use MIDI2Client (destination resolved automatically)")
    public func destination(for muid: MUID) -> MIDIDestinationID? {
        devices[muid]?.destination
    }
    
    /// Create a destination resolver closure for PEManager
    ///
    /// This provides a convenient way to configure PEManager's
    /// `destinationResolver` to use this CIManager for MUID → destination lookup.
    ///
    /// The resolver dynamically prioritizes "Module" destinations for PE communication,
    /// which is required for devices like KORG that use separate ports for Discovery vs PE.
    ///
    /// ## Example
    /// ```swift
    /// peManager.destinationResolver = ciManager.makeDestinationResolver()
    /// // Now you can use MUID-only API:
    /// let response = try await peManager.get("DeviceInfo", from: deviceMUID)
    /// ```
    @available(*, deprecated, message: "Use MIDI2Client (destination resolver integrated)")
    public nonisolated func makeDestinationResolver() -> @Sendable (MUID) async -> MIDIDestinationID? {
        { [weak self] muid in
            await self?.resolveDestinationForPE(muid: muid)
        }
    }
    
    /// Resolve destination for PE communication
    ///
    /// This method dynamically finds the best destination for Property Exchange,
    /// prioritizing "Module" ports over cached Discovery destinations.
    private func resolveDestinationForPE(muid: MUID) async -> MIDIDestinationID? {
        // First, check if we know about this device at all
        guard devices[muid] != nil else {
            return nil
        }
        
        // Dynamically find the best destination for PE
        // Priority 1: "Module" destination (MIDI-CI/PE standard port)
        let destinations = await transport.destinations
        if let moduleDest = destinations.first(where: { $0.name.lowercased().contains("module") }) {
            return moduleDest.destinationID
        }
        
        // Priority 2: Use cached destination from Discovery
        return devices[muid]?.destination
    }
    
    // MARK: - Device Management
    
    /// Remove a device manually
    public func removeDevice(_ muid: MUID) {
        if devices.removeValue(forKey: muid) != nil {
            eventContinuation?.yield(.deviceLost(muid))
        }
    }
    
    /// Clear all devices
    public func clearDevices() {
        let muids = Array(devices.keys)
        devices.removeAll()
        for muid in muids {
            eventContinuation?.yield(.deviceLost(muid))
        }
    }
    
    // MARK: - Message Handling
    
    /// Handle received data from external dispatcher
    /// 
    /// Use this when you need to manually dispatch messages to CIManager
    /// instead of having CIManager consume the transport stream directly.
    public func handleReceivedExternal(_ received: MIDIReceivedData) {
        handleReceived(received)
    }
    
    private func handleReceived(_ received: MIDIReceivedData) {
        guard let parsed = CIMessageParser.parse(received.data) else { return }
        
        // Ignore messages from ourselves
        guard parsed.sourceMUID != muid else { return }
        
        // Ignore messages not addressed to us (unless broadcast)
        guard parsed.destinationMUID == muid || parsed.destinationMUID.isBroadcast else { return }
        
        switch parsed.messageType {
        case .discoveryInquiry:
            // Always register the device from Discovery Inquiry (they may not respond to our inquiry)
            // Only send reply if respondToDiscovery is true
            Task { await handleDiscoveryInquiry(parsed, sourceID: received.sourceID, sendReply: configuration.respondToDiscovery) }

        case .discoveryReply:
            handleDiscoveryReply(parsed, sourceID: received.sourceID)
            
        case .invalidateMUID:
            handleInvalidateMUID(parsed)
            
        default:
            break
        }
    }
    
    private func handleDiscoveryInquiry(_ parsed: CIMessageParser.ParsedMessage, sourceID: MIDISourceID?, sendReply: Bool) async {
        // Register the inquiring device (they may not respond to our inquiry)
        // Discovery Inquiry uses the same payload format as Discovery Reply
        if let payload = CIMessageParser.parseDiscoveryReply(parsed.payload) {
            let device = DiscoveredDevice(
                muid: parsed.sourceMUID,
                identity: payload.identity,
                categorySupport: payload.categorySupport,
                maxSysExSize: payload.maxSysExSize,
                initiatorOutputPath: payload.initiatorOutputPath,
                functionBlock: payload.functionBlock
            )

            let destination = await self.findDestination(for: sourceID)
            await self.registerDevice(
                device,
                sourceMUID: parsed.sourceMUID,
                sourceID: sourceID,
                destination: destination
            )
        }

        // Send reply if configured
        guard sendReply else { return }

        let reply = CIMessageBuilder.discoveryReply(
            sourceMUID: muid,
            destinationMUID: parsed.sourceMUID,
            deviceIdentity: configuration.deviceIdentity,
            categorySupport: configuration.categorySupport,
            maxSysExSize: configuration.maxSysExSize,
            initiatorOutputPath: 0,
            functionBlock: 0
        )

        let destinations = await transport.destinations
        for dest in destinations {
            try? await transport.send(reply, to: dest.destinationID)
        }
    }
    
    private func handleDiscoveryReply(_ parsed: CIMessageParser.ParsedMessage, sourceID: MIDISourceID?) {
        guard let payload = CIMessageParser.parseDiscoveryReply(parsed.payload) else { return }
        
        let device = DiscoveredDevice(
            muid: parsed.sourceMUID,
            identity: payload.identity,
            categorySupport: payload.categorySupport,
            maxSysExSize: payload.maxSysExSize,
            initiatorOutputPath: payload.initiatorOutputPath,
            functionBlock: payload.functionBlock
        )
        
        // Resolve destination asynchronously via transport
        Task {
            let destination = await self.findDestination(for: sourceID)
            await self.registerDevice(
                device,
                sourceMUID: parsed.sourceMUID,
                sourceID: sourceID,
                destination: destination
            )
        }
    }
    
    private func registerDevice(
        _ device: DiscoveredDevice,
        sourceMUID: MUID,
        sourceID: MIDISourceID?,
        destination: MIDIDestinationID?
    ) {
        let isNew = devices[sourceMUID] == nil
        devices[sourceMUID] = DeviceEntry(
            device: device,
            lastSeen: Date(),
            sourceID: sourceID,
            destination: destination
        )
        
        if isNew {
            eventContinuation?.yield(.deviceDiscovered(device))
        } else {
            eventContinuation?.yield(.deviceUpdated(device))
        }
    }
    
    private func handleInvalidateMUID(_ parsed: CIMessageParser.ParsedMessage) {
        if let payload = CIMessageParser.parseInvalidateMUID(parsed.payload) {
            if payload.targetMUID.isBroadcast {
                // Source is invalidating itself
                removeDevice(parsed.sourceMUID)
            } else {
                // Specific MUID being invalidated
                removeDevice(payload.targetMUID)
            }
        }
    }
    
    // MARK: - Timeout Checking
    
    private func runTimeoutChecker() async {
        while !Task.isCancelled && isRunning {
            let now = Date()
            let timeout = configuration.deviceTimeout
            
            // Find timed-out devices
            let timedOut = devices.filter { _, entry in
                now.timeIntervalSince(entry.lastSeen) > timeout
            }
            
            // Remove them
            for (muid, _) in timedOut {
                removeDevice(muid)
            }
            
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                break
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Find the destination endpoint that pairs with a source for MIDI-CI/PE communication
    ///
    /// This method resolves the correct destination for Property Exchange requests.
    /// Many MIDI devices (KORG, Roland, etc.) have dedicated "Module" ports for MIDI-CI/PE,
    /// which may differ from the port that Discovery replies arrive from.
    ///
    /// Priority order:
    /// 1. "Module" destination (MIDI-CI/PE standard port) - highest priority for PE
    /// 2. Entity-based matching (source index → destination index)
    /// 3. Name-based matching (source name = destination name)
    ///
    /// ## Why "Module" First?
    ///
    /// KORG and similar devices have this port structure:
    /// - Sources: "Bluetooth", "Session 1"
    /// - Destinations: "Bluetooth", "Session 1", "Module"
    ///
    /// Discovery replies come from "Bluetooth" source, but PE requests must go to
    /// "Module" destination. Entity-based matching would incorrectly return "Bluetooth".
    private func findDestination(for sourceID: MIDISourceID?) async -> MIDIDestinationID? {
        let destinations = await transport.destinations
        
        // Priority 1: Look for "Module" destination first (HIGHEST PRIORITY for PE)
        // Many MIDI devices (KORG, etc.) have a "Module" port for MIDI-CI/PE communication.
        // This MUST take precedence over entity-based matching because:
        // - Discovery replies often come from "Bluetooth" source
        // - Entity-based matching would return "Bluetooth" destination (wrong!)
        // - PE requests must go to "Module" destination
        if let moduleDest = destinations.first(where: { $0.name.lowercased().contains("module") }) {
            return moduleDest.destinationID
        }
        
        // Priority 2: Entity-based matching (via transport layer)
        // This is reliable for devices without dedicated Module ports
        if let sourceID,
           let destination = await transport.findMatchingDestination(for: sourceID) {
            return destination
        }
        
        // Priority 3: Name-based matching (source name = destination name)
        if let sourceID {
            let sources = await transport.sources
            
            if let sourceInfo = sources.first(where: { $0.sourceID == sourceID }) {
                // Look for a destination with the same name
                if let matchingDest = destinations.first(where: { $0.name == sourceInfo.name }) {
                    return matchingDest.destinationID
                }
            }
        }
        
        // No fallback to "first destination" - return nil if no match found
        // This prevents sending to wrong port
        return nil
    }
}

// MARK: - DeviceIdentity Extension

extension DeviceIdentity {
    /// Default identity for MIDI2Kit apps
    public static let `default` = DeviceIdentity(
        manufacturerID: .extended(0x00, 0x00),  // Development/prototype
        familyID: 0x0001,
        modelID: 0x0001,
        versionID: 0x00010000
    )
}
