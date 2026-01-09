//
//  CIManager.swift
//  MIDI2Kit
//
//  High-level MIDI-CI management with automatic discovery
//

import Foundation
import MIDI2Core
import MIDI2CI
import MIDI2Transport

/// Device discovery and lifecycle events
public enum CIManagerEvent: Sendable {
    case deviceDiscovered(DiscoveredDevice)
    case deviceLost(MUID)
    case deviceUpdated(DiscoveredDevice)
    case discoveryStarted
    case discoveryStopped
}

/// Configuration for CIManager
public struct CIManagerConfiguration: Sendable {
    /// How often to send Discovery Inquiry (seconds)
    public var discoveryInterval: TimeInterval
    
    /// How long before a device is considered lost (seconds)
    public var deviceTimeout: TimeInterval
    
    /// Category support to advertise
    public var categorySupport: CategorySupport
    
    /// Device identity to advertise
    public var deviceIdentity: DeviceIdentity
    
    /// Maximum SysEx size (0 = no limit)
    public var maxSysExSize: UInt32
    
    public init(
        discoveryInterval: TimeInterval = 5.0,
        deviceTimeout: TimeInterval = 15.0,
        categorySupport: CategorySupport = .propertyExchange,
        deviceIdentity: DeviceIdentity = .default,
        maxSysExSize: UInt32 = 0
    ) {
        self.discoveryInterval = discoveryInterval
        self.deviceTimeout = deviceTimeout
        self.categorySupport = categorySupport
        self.deviceIdentity = deviceIdentity
        self.maxSysExSize = maxSysExSize
    }
    
    public static let `default` = CIManagerConfiguration()
}

/// High-level MIDI-CI manager
///
/// Features:
/// - Automatic periodic discovery
/// - Device lifecycle management (discovered/lost)
/// - Thread-safe device tracking
/// - Event stream for UI updates
public actor CIManager {
    
    // MARK: - State
    
    private let transport: any MIDITransport
    private let configuration: CIManagerConfiguration
    private let myMUID: MUID
    
    /// Known devices with last seen timestamp
    private var devices: [MUID: (device: DiscoveredDevice, lastSeen: Date, destination: MIDIDestinationID)] = [:]
    
    /// Event stream continuation
    private var eventContinuation: AsyncStream<CIManagerEvent>.Continuation?
    
    /// Discovery task
    private var discoveryTask: Task<Void, Never>?
    
    /// Cleanup task
    private var cleanupTask: Task<Void, Never>?
    
    /// Is discovery running
    private var isDiscoveryRunning = false
    
    // MARK: - Public Properties
    
    /// Stream of manager events
    public let events: AsyncStream<CIManagerEvent>
    
    /// Current discovered devices
    public var discoveredDevices: [DiscoveredDevice] {
        devices.values.map { $0.device }
    }
    
    /// Get device by MUID
    public func device(for muid: MUID) -> DiscoveredDevice? {
        devices[muid]?.device
    }
    
    /// Get destination for device
    public func destination(for muid: MUID) -> MIDIDestinationID? {
        devices[muid]?.destination
    }
    
    /// Our MUID
    public var muid: MUID { myMUID }
    
    // MARK: - Initialization
    
    public init(
        transport: any MIDITransport,
        configuration: CIManagerConfiguration = .default
    ) {
        self.transport = transport
        self.configuration = configuration
        self.myMUID = MUID.random()
        
        var continuation: AsyncStream<CIManagerEvent>.Continuation?
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }
    
    deinit {
        discoveryTask?.cancel()
        cleanupTask?.cancel()
        eventContinuation?.finish()
    }
    
    // MARK: - Discovery Control
    
    /// Start automatic discovery
    public func startDiscovery() {
        guard !isDiscoveryRunning else { return }
        isDiscoveryRunning = true
        
        eventContinuation?.yield(.discoveryStarted)
        
        // Start receive processing
        Task { await processIncomingMessages() }
        
        // Start periodic discovery
        discoveryTask = Task { await discoveryLoop() }
        
        // Start device cleanup
        cleanupTask = Task { await cleanupLoop() }
    }
    
    /// Stop automatic discovery
    public func stopDiscovery() {
        guard isDiscoveryRunning else { return }
        isDiscoveryRunning = false
        
        discoveryTask?.cancel()
        cleanupTask?.cancel()
        discoveryTask = nil
        cleanupTask = nil
        
        eventContinuation?.yield(.discoveryStopped)
    }
    
    /// Send a single discovery inquiry
    public func sendDiscoveryInquiry() async {
        let message = CIMessageBuilder.discoveryInquiry(
            sourceMUID: myMUID,
            deviceIdentity: configuration.deviceIdentity,
            categorySupport: configuration.categorySupport,
            maxSysExSize: configuration.maxSysExSize
        )
        
        // Send to all destinations
        let destinations = await transport.destinations
        for dest in destinations {
            try? await transport.send(message, to: dest.destinationID)
        }
    }
    
    /// Invalidate a device's MUID (e.g., when we're shutting down)
    public func invalidateMUID() async {
        let message = CIMessageBuilder.invalidateMUID(
            sourceMUID: myMUID,
            targetMUID: MUID.broadcast
        )
        
        let destinations = await transport.destinations
        for dest in destinations {
            try? await transport.send(message, to: dest.destinationID)
        }
    }
    
    // MARK: - Manual Device Management
    
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
    
    // MARK: - Private Methods
    
    private func discoveryLoop() async {
        while !Task.isCancelled && isDiscoveryRunning {
            await sendDiscoveryInquiry()
            
            try? await Task.sleep(for: .seconds(configuration.discoveryInterval))
        }
    }
    
    private func cleanupLoop() async {
        while !Task.isCancelled && isDiscoveryRunning {
            try? await Task.sleep(for: .seconds(1.0))
            
            let now = Date()
            var lost: [MUID] = []
            
            for (muid, entry) in devices {
                if now.timeIntervalSince(entry.lastSeen) > configuration.deviceTimeout {
                    lost.append(muid)
                }
            }
            
            for muid in lost {
                devices.removeValue(forKey: muid)
                eventContinuation?.yield(.deviceLost(muid))
            }
        }
    }
    
    private func processIncomingMessages() async {
        for await received in transport.received {
            guard let parsed = CIMessageParser.parse(received.data) else {
                continue
            }
            
            // Ignore messages from ourselves
            guard parsed.sourceMUID != myMUID else { continue }
            
            // Ignore messages not for us (unless broadcast)
            guard parsed.destinationMUID == myMUID || parsed.destinationMUID.isBroadcast else {
                continue
            }
            
            await handleCIMessage(parsed, from: received.sourceID)
        }
    }
    
    private func handleCIMessage(_ parsed: CIMessageParser.ParsedMessage, from sourceID: MIDISourceID?) async {
        switch parsed.messageType {
        case .discoveryInquiry:
            // Another device is discovering - respond if we want to be discoverable
            await handleDiscoveryInquiry(parsed)
            
        case .discoveryReply:
            // A device responded to our discovery
            await handleDiscoveryReply(parsed)
            
        case .invalidateMUID:
            // A device is invalidating its MUID
            handleInvalidateMUID(parsed)
            
        default:
            break
        }
    }
    
    private func handleDiscoveryInquiry(_ parsed: CIMessageParser.ParsedMessage) async {
        // Build reply
        let reply = CIMessageBuilder.discoveryReply(
            sourceMUID: myMUID,
            destinationMUID: parsed.sourceMUID,
            deviceIdentity: configuration.deviceIdentity,
            categorySupport: configuration.categorySupport,
            maxSysExSize: configuration.maxSysExSize,
            initiatorOutputPath: 0,
            functionBlock: 0
        )
        
        // Send to all destinations (we don't know which one the inquiry came from)
        let destinations = await transport.destinations
        for dest in destinations {
            try? await transport.send(reply, to: dest.destinationID)
        }
    }
    
    private func handleDiscoveryReply(_ parsed: CIMessageParser.ParsedMessage) async {
        guard let reply = CIMessageParser.parseDiscoveryReply(parsed.payload) else {
            return
        }
        
        let device = DiscoveredDevice(
            muid: parsed.sourceMUID,
            identity: reply.identity,
            categorySupport: reply.categorySupport,
            maxSysExSize: reply.maxSysExSize,
            initiatorOutputPath: reply.initiatorOutputPath,
            functionBlock: reply.functionBlock
        )
        
        // Find a destination for this device
        let destinations = await transport.destinations
        let destination = destinations.first?.destinationID ?? MIDIDestinationID(0)
        
        let isNew = devices[parsed.sourceMUID] == nil
        devices[parsed.sourceMUID] = (device, Date(), destination)
        
        if isNew {
            eventContinuation?.yield(.deviceDiscovered(device))
        } else {
            eventContinuation?.yield(.deviceUpdated(device))
        }
    }
    
    private func handleInvalidateMUID(_ parsed: CIMessageParser.ParsedMessage) {
        // Check if it's a specific MUID being invalidated
        if let invalidatePayload = CIMessageParser.parseInvalidateMUID(parsed.payload) {
            let targetMUID = invalidatePayload.targetMUID
            if targetMUID.isBroadcast {
                // Source is invalidating itself
                removeDevice(parsed.sourceMUID)
            } else {
                // Specific MUID being invalidated
                removeDevice(targetMUID)
            }
        }
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
