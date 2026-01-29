//
//  MIDI2Client.swift
//  MIDI2Kit
//
//  High-level unified client for MIDI 2.0 / MIDI-CI / Property Exchange
//

import Foundation
import MIDI2Core
import MIDI2CI
import MIDI2PE
import MIDI2Transport

// MARK: - MIDI2Client

/// High-level unified client for MIDI 2.0 communication
///
/// MIDI2Client provides a simplified, unified API for:
/// - MIDI-CI Device Discovery
/// - Property Exchange (Get/Set resources)
/// - Event subscription and notification
///
/// ## Benefits over Low-Level APIs
///
/// - **No AsyncStream conflicts**: Internal receive hub handles distribution
/// - **Automatic destination resolution**: KORG and similar devices work out of the box
/// - **Multicast events**: Multiple subscribers can listen to the same stream
/// - **Proper cleanup**: `stop()` guarantees all resources are released
///
/// ## Example
///
/// ```swift
/// // Create and start
/// let client = try MIDI2Client(name: "MyApp")
/// try await client.start()
///
/// // Listen for events
/// Task {
///     for await event in client.makeEventStream() {
///         switch event {
///         case .deviceDiscovered(let device):
///             print("Found: \(device.displayName)")
///             if device.supportsPropertyExchange {
///                 let info = try await client.getDeviceInfo(from: device.muid)
///                 print("Product: \(info.productName ?? "Unknown")")
///             }
///         case .deviceLost(let muid):
///             print("Lost: \(muid)")
///         default:
///             break
///         }
///     }
/// }
///
/// // Later: clean shutdown
/// await client.stop()
/// ```
public actor MIDI2Client {
    
    // MARK: - Properties
    
    /// Client name (used for CoreMIDI client name)
    public nonisolated let name: String
    
    /// Configuration
    public nonisolated let configuration: MIDI2ClientConfiguration
    
    /// This client's MUID
    public nonisolated let muid: MUID
    
    /// Whether the client is currently running
    public private(set) var isRunning: Bool = false
    
    // MARK: - Internal Components
    
    /// MIDI transport
    private let transport: CoreMIDITransport
    
    /// CI Manager for device discovery
    private let ciManager: CIManager
    
    /// PE Manager for property exchange
    private let peManager: PEManager
    
    /// Event distribution hub
    private let eventHub: ReceiveHub<MIDI2ClientEvent>
    
    /// Destination resolver
    private let destinationResolver: DestinationResolver
    
    /// Discovered devices by MUID
    private var devices: [MUID: MIDI2Device] = [:]
    
    /// Cached DeviceInfo by MUID
    private var deviceInfoCache: [MUID: PEDeviceInfo] = [:]
    
    /// Last destination diagnostics
    private var _lastDestinationDiagnostics: DestinationDiagnostics?
    
    // MARK: - Tasks
    
    /// Receive dispatcher task
    private var receiveDispatcherTask: Task<Void, Never>?
    
    /// CI event forwarding task
    private var ciEventForwardingTask: Task<Void, Never>?
    
    /// PE notification forwarding task
    private var peNotificationForwardingTask: Task<Void, Never>?
    
    /// Setup change handling task
    private var setupChangeTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Create a client with default configuration
    ///
    /// - Parameter name: Client name for CoreMIDI
    /// - Throws: `MIDI2Error.transportError` if CoreMIDI initialization fails
    public init(name: String) throws {
        try self.init(name: name, configuration: .default)
    }
    
    /// Create a client with preset configuration
    ///
    /// - Parameters:
    ///   - name: Client name for CoreMIDI
    ///   - preset: Configuration preset
    /// - Throws: `MIDI2Error.transportError` if CoreMIDI initialization fails
    public init(name: String, preset: ClientPreset) throws {
        try self.init(name: name, configuration: MIDI2ClientConfiguration(preset: preset))
    }
    
    /// Create a client with custom configuration
    ///
    /// - Parameters:
    ///   - name: Client name for CoreMIDI
    ///   - configuration: Custom configuration
    /// - Throws: `MIDI2Error.transportError` if CoreMIDI initialization fails
    public init(name: String, configuration: MIDI2ClientConfiguration) throws {
        self.name = name
        self.configuration = configuration
        self.muid = MUID.random()
        
        // Initialize transport
        do {
            self.transport = try CoreMIDITransport(clientName: name)
        } catch {
            throw MIDI2Error.transportError(error)
        }
        
        // Initialize CI Manager
        let ciConfig = CIManagerConfiguration(
            discoveryInterval: configuration.discoveryInterval.asTimeInterval,
            deviceTimeout: configuration.deviceTimeout.asTimeInterval,
            autoStartDiscovery: false,  // We'll start manually after setup
            respondToDiscovery: configuration.respondToDiscovery,
            categorySupport: configuration.categorySupport,
            deviceIdentity: configuration.deviceIdentity,
            maxSysExSize: configuration.maxSysExSize
        )
        self.ciManager = CIManager(
            transport: transport,
            muid: muid,
            configuration: ciConfig
        )
        
        // Initialize PE Manager
        self.peManager = PEManager(
            transport: transport,
            sourceMUID: muid,
            maxInflightPerDevice: configuration.maxInflightPerDevice,
            logger: configuration.logger
        )
        
        // Initialize event hub
        self.eventHub = ReceiveHub<MIDI2ClientEvent>()
        
        // Initialize destination resolver
        self.destinationResolver = DestinationResolver(
            strategy: configuration.destinationStrategy,
            transport: transport
        )
    }
    
    deinit {
        // Cancel all tasks synchronously
        receiveDispatcherTask?.cancel()
        ciEventForwardingTask?.cancel()
        peNotificationForwardingTask?.cancel()
        setupChangeTask?.cancel()
    }
    
    // MARK: - Lifecycle
    
    /// Start the client
    ///
    /// This will:
    /// 1. Connect to all MIDI sources
    /// 2. Start device discovery
    /// 3. Begin listening for events
    ///
    /// - Throws: `MIDI2Error` if startup fails
    public func start() async throws {
        guard !isRunning else { return }
        
        // Connect to all sources
        do {
            try await transport.connectToAllSources()
        } catch {
            throw MIDI2Error.transportError(error)
        }
        
        // Start receive dispatcher (unified message handling)
        startReceiveDispatcher()
        
        // Reset PE manager state (don't call startReceiving - we dispatch manually via handleReceivedExternal)
        // Note: startReceiving() would start its own receive loop that competes with our dispatcher
        await peManager.resetForExternalDispatch()
        
        // Start CI event forwarding
        startCIEventForwarding()
        
        // Start PE notification forwarding
        startPENotificationForwarding()
        
        // Start setup change handling
        startSetupChangeHandling()
        
        // Start discovery if configured
        if configuration.autoStartDiscovery {
            await ciManager.startDiscovery()
        }
        
        isRunning = true
        await eventHub.broadcast(.started)
    }
    
    /// Stop the client
    ///
    /// This will:
    /// 1. Cancel all pending PE requests (with `PEError.cancelled`)
    /// 2. Stop all background tasks
    /// 3. Finish all event streams
    /// 4. Invalidate this client's MUID
    ///
    /// After calling `stop()`:
    /// - `isRunning` will be `false`
    /// - `makeEventStream()` will return immediately-finished streams
    /// - All pending PE requests will throw `PEError.cancelled`
    public func stop() async {
        guard isRunning else { return }
        
        isRunning = false
        
        // 1. Cancel all pending PE requests (ID exhaustion prevention)
        await peManager.stopReceiving()
        
        // 2. Stop CI manager
        await ciManager.stop()
        
        // 3. Cancel all background tasks
        receiveDispatcherTask?.cancel()
        ciEventForwardingTask?.cancel()
        peNotificationForwardingTask?.cancel()
        setupChangeTask?.cancel()
        
        receiveDispatcherTask = nil
        ciEventForwardingTask = nil
        peNotificationForwardingTask = nil
        setupChangeTask = nil
        
        // 4. Broadcast stopped event before finishing hub
        await eventHub.broadcast(.stopped)
        
        // 5. Finish all event streams
        await eventHub.finishAll()
        
        // 6. Invalidate MUID
        await ciManager.invalidateMUID()
        
        // 7. Clear device cache
        devices.removeAll()
        deviceInfoCache.removeAll()
        await destinationResolver.clearCache()
    }
    
    // MARK: - Event Streams
    
    /// Create a new event stream
    ///
    /// Each call returns an independent stream. Multiple streams can be active
    /// simultaneously, each receiving all events.
    ///
    /// - Returns: An AsyncStream of client events
    ///
    /// ## Thread Safety
    ///
    /// The returned stream is safe to iterate from any context.
    ///
    /// ## After stop()
    ///
    /// If called after `stop()`, returns an immediately-finished stream.
    public func makeEventStream() async -> AsyncStream<MIDI2ClientEvent> {
        await eventHub.makeStream()
    }
    
    // MARK: - Devices
    
    /// All discovered devices
    public var discoveredDevices: [MIDI2Device] {
        Array(devices.values)
    }
    
    /// Devices that support Property Exchange
    public var peCapableDevices: [MIDI2Device] {
        devices.values.filter(\.supportsPropertyExchange)
    }
    
    /// Get a device by MUID
    public func device(for muid: MUID) -> MIDI2Device? {
        devices[muid]
    }
    
    // MARK: - Property Exchange
    
    /// Get DeviceInfo from a device (with caching)
    ///
    /// The result is cached for the lifetime of the device connection.
    /// Use `getCachedDeviceInfo(for:)` to check if a cached value exists
    /// without making a network request.
    ///
    /// - Parameter muid: The device MUID
    /// - Returns: The device's PE DeviceInfo
    /// - Throws: `MIDI2Error` on failure
    public func getDeviceInfo(from muid: MUID) async throws -> PEDeviceInfo {
        guard isRunning else { throw MIDI2Error.clientNotRunning }
        
        // Return cached value if available
        if let cached = deviceInfoCache[muid] {
            MIDI2Logger.pe.midi2Debug("DeviceInfo cache hit for \(muid)")
            return cached
        }
        
        let destination = try await resolveDestination(for: muid)
        let handle = PEDeviceHandle(muid: muid, destination: destination)
        
        do {
            let info = try await peManager.getDeviceInfo(from: handle)
            // Cache the result
            deviceInfoCache[muid] = info
            return info
        } catch let error as PEError {
            // Try fallback on timeout
            if case .timeout = error {
                if let nextDest = await destinationResolver.getNextCandidate(after: destination, for: muid) {
                    let retryHandle = PEDeviceHandle(muid: muid, destination: nextDest)
                    do {
                        let result = try await peManager.getDeviceInfo(from: retryHandle)
                        // Cache successful destination and result
                        await destinationResolver.cacheDestination(nextDest, for: muid)
                        deviceInfoCache[muid] = result
                        return result
                    } catch {
                        throw MIDI2Error(from: error as! PEError, muid: muid)
                    }
                }
            }
            throw MIDI2Error(from: error, muid: muid)
        }
    }
    
    /// Get cached DeviceInfo without making a network request
    ///
    /// - Parameter muid: The device MUID
    /// - Returns: The cached DeviceInfo, or nil if not cached
    public func getCachedDeviceInfo(for muid: MUID) -> PEDeviceInfo? {
        deviceInfoCache[muid]
    }
    
    /// Clear the DeviceInfo cache for a specific device
    ///
    /// Use this to force a fresh fetch on the next `getDeviceInfo()` call.
    ///
    /// - Parameter muid: The device MUID
    public func clearDeviceInfoCache(for muid: MUID) {
        deviceInfoCache.removeValue(forKey: muid)
    }
    
    /// Get ResourceList from a device (with automatic retry and destination fallback)
    ///
    /// When `configuration.warmUpBeforeResourceList` is enabled (default),
    /// this method first fetches DeviceInfo as a "warm-up". This helps
    /// establish a reliable BLE connection before requesting the multi-chunk
    /// ResourceList, which is more prone to packet loss on idle connections.
    ///
    /// On timeout, the method tries the next destination candidate (max 1 retry).
    ///
    /// - Parameter muid: The device MUID
    /// - Returns: Array of available resources
    /// - Throws: `MIDI2Error` on failure after all retries
    public func getResourceList(from muid: MUID) async throws -> [PEResourceEntry] {
        guard isRunning else { throw MIDI2Error.clientNotRunning }

        let destination = try await resolveDestination(for: muid)
        let handle = PEDeviceHandle(muid: muid, destination: destination)

        // Optional warm-up: Fetch DeviceInfo first to wake up BLE connection
        if configuration.warmUpBeforeResourceList {
            MIDI2Logger.pe.midi2Debug("Warm-up: fetching DeviceInfo before ResourceList")
            do {
                _ = try await peManager.getDeviceInfo(from: handle)
                MIDI2Logger.pe.midi2Debug("Warm-up successful, proceeding with ResourceList")
            } catch {
                // Warm-up failure is not fatal - proceed with ResourceList anyway
                MIDI2Logger.pe.midi2Warning("Warm-up failed (\(error)), proceeding anyway")
            }

            // Small delay to let BLE connection stabilize
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Calculate timeout for multi-chunk request
        let timeout = Duration.seconds(
            configuration.peTimeout.asTimeInterval * configuration.multiChunkTimeoutMultiplier
        )

        do {
            let result = try await peManager.getResourceList(from: handle)
            return result
        } catch let error as PEError {
            // Try fallback on timeout
            if case .timeout = error {
                if let nextDest = await destinationResolver.getNextCandidate(after: destination, for: muid) {
                    MIDI2Logger.pe.midi2Info("ResourceList timeout, trying fallback destination: \(nextDest)")
                    let retryHandle = PEDeviceHandle(muid: muid, destination: nextDest)
                    do {
                        let result = try await peManager.getResourceList(from: retryHandle)
                        // Cache successful destination
                        await destinationResolver.cacheDestination(nextDest, for: muid)
                        MIDI2Logger.pe.midi2Info("ResourceList succeeded with fallback destination")
                        return result
                    } catch {
                        MIDI2Logger.pe.midi2Error("ResourceList failed on fallback destination: \(error)")
                        throw MIDI2Error(from: error as? PEError ?? .timeout(resource: "ResourceList"), muid: muid, timeout: timeout)
                    }
                }
            }
            throw MIDI2Error(from: error, muid: muid, timeout: timeout)
        }
    }
    
    /// Get a property from a device
    ///
    /// - Parameters:
    ///   - resource: Resource name (e.g., "DeviceInfo", "ProgramList")
    ///   - muid: The device MUID
    ///   - timeout: Optional custom timeout
    /// - Returns: The PE response
    /// - Throws: `MIDI2Error` on failure
    public func get(
        _ resource: String,
        from muid: MUID,
        timeout: Duration? = nil
    ) async throws -> PEResponse {
        guard isRunning else { throw MIDI2Error.clientNotRunning }

        let destination = try await resolveDestination(for: muid)
        let handle = PEDeviceHandle(muid: muid, destination: destination)

        do {
            return try await peManager.get(
                resource,
                from: handle,
                timeout: timeout ?? configuration.peTimeout
            )
        } catch let error as PEError {
            // Try fallback on timeout
            if case .timeout = error {
                if let nextDest = await destinationResolver.getNextCandidate(after: destination, for: muid) {
                    MIDI2Logger.pe.midi2Debug("Get '\(resource)' timeout, trying fallback destination")
                    let retryHandle = PEDeviceHandle(muid: muid, destination: nextDest)
                    do {
                        let result = try await peManager.get(resource, from: retryHandle, timeout: timeout ?? configuration.peTimeout)
                        await destinationResolver.cacheDestination(nextDest, for: muid)
                        return result
                    } catch {
                        throw MIDI2Error(from: error as? PEError ?? .timeout(resource: resource), muid: muid)
                    }
                }
            }
            throw MIDI2Error(from: error, muid: muid)
        }
    }
    
    /// Get a channel-specific property
    public func get(
        _ resource: String,
        channel: Int,
        from muid: MUID,
        timeout: Duration? = nil
    ) async throws -> PEResponse {
        guard isRunning else { throw MIDI2Error.clientNotRunning }

        let destination = try await resolveDestination(for: muid)
        let handle = PEDeviceHandle(muid: muid, destination: destination)

        do {
            return try await peManager.get(
                resource,
                channel: channel,
                from: handle,
                timeout: timeout ?? configuration.peTimeout
            )
        } catch let error as PEError {
            // Try fallback on timeout
            if case .timeout = error {
                if let nextDest = await destinationResolver.getNextCandidate(after: destination, for: muid) {
                    MIDI2Logger.pe.midi2Debug("Get '\(resource)' (channel \(channel)) timeout, trying fallback destination")
                    let retryHandle = PEDeviceHandle(muid: muid, destination: nextDest)
                    do {
                        let result = try await peManager.get(resource, channel: channel, from: retryHandle, timeout: timeout ?? configuration.peTimeout)
                        await destinationResolver.cacheDestination(nextDest, for: muid)
                        return result
                    } catch {
                        throw MIDI2Error(from: error as? PEError ?? .timeout(resource: resource), muid: muid)
                    }
                }
            }
            throw MIDI2Error(from: error, muid: muid)
        }
    }
    
    /// Set a property on a device
    ///
    /// - Parameters:
    ///   - resource: Resource name
    ///   - data: Data to set
    ///   - muid: The device MUID
    ///   - timeout: Optional custom timeout
    /// - Returns: The PE response
    /// - Throws: `MIDI2Error` on failure
    public func set(
        _ resource: String,
        data: Data,
        to muid: MUID,
        timeout: Duration? = nil
    ) async throws -> PEResponse {
        guard isRunning else { throw MIDI2Error.clientNotRunning }

        let destination = try await resolveDestination(for: muid)
        let handle = PEDeviceHandle(muid: muid, destination: destination)

        do {
            return try await peManager.set(
                resource,
                data: data,
                to: handle,
                timeout: timeout ?? configuration.peTimeout
            )
        } catch let error as PEError {
            // Try fallback on timeout
            if case .timeout = error {
                if let nextDest = await destinationResolver.getNextCandidate(after: destination, for: muid) {
                    MIDI2Logger.pe.midi2Debug("Set '\(resource)' timeout, trying fallback destination")
                    let retryHandle = PEDeviceHandle(muid: muid, destination: nextDest)
                    do {
                        let result = try await peManager.set(resource, data: data, to: retryHandle, timeout: timeout ?? configuration.peTimeout)
                        await destinationResolver.cacheDestination(nextDest, for: muid)
                        return result
                    } catch {
                        throw MIDI2Error(from: error as? PEError ?? .timeout(resource: resource), muid: muid)
                    }
                }
            }
            throw MIDI2Error(from: error, muid: muid)
        }
    }
    
    // MARK: - Diagnostics
    
    /// Last destination resolution diagnostics
    public var lastDestinationDiagnostics: DestinationDiagnostics? {
        get async {
            await destinationResolver.lastDiagnostics
        }
    }
    
    /// Diagnostic information string
    public var diagnostics: String {
        get async {
            var lines: [String] = []
            lines.append("=== MIDI2Client ===")
            lines.append("Name: \(name)")
            lines.append("MUID: \(muid)")
            lines.append("Running: \(isRunning)")
            lines.append("Devices: \(devices.count)")
            
            for device in devices.values {
                lines.append("  - \(device.displayName) [\(device.muid)]")
            }
            
            lines.append("")
            lines.append(await peManager.diagnostics)
            
            if let diag = await destinationResolver.lastDiagnostics {
                lines.append("")
                lines.append("Last Destination Resolution:")
                lines.append(diag.description)
            }
            
            return lines.joined(separator: "\n")
        }
    }
    
    // MARK: - Private: Receive Dispatcher
    
    private func startReceiveDispatcher() {
        receiveDispatcherTask = Task { [weak self] in
            guard let self else { return }
            
            MIDI2Logger.dispatcher.midi2Info("Started receive dispatcher")
            
            for await received in transport.received {
                if Task.isCancelled { break }
                
                let data = received.data
                let sourceInfo = received.sourceID.map { "source \($0)" } ?? "no source"
                
                // Log SysEx messages
                if data.count >= 5 && data[0] == 0xF0 {
                    let subID2 = data.count > 4 ? data[4] : 0x00
                    
                    // Log message type
                    let messageType: String
                    switch subID2 {
                    case 0x35: messageType = "PE GET REPLY"
                    case 0x36: messageType = "PE SET REPLY"
                    case 0x34: messageType = "PE GET INQUIRY"
                    case 0x70: messageType = "Discovery Request"
                    case 0x71: messageType = "Discovery Reply"
                    case 0x7F: messageType = "NAK"
                    default: messageType = "SysEx"
                    }
                    
                    MIDI2Logger.dispatcher.midi2Debug("\(messageType) len=\(data.count) (\(sourceInfo))")
                    
                    // Verbose: hex dump
                    if MIDI2Logger.isVerbose {
                        let hexPreview = data.prefix(40).map { String(format: "%02X", $0) }.joined(separator: " ")
                        MIDI2Logger.dispatcher.midi2Verbose("Hex: \(hexPreview)\(data.count > 40 ? "..." : "")")
                    }
                } else {
                    // Non-SysEx: only log in verbose mode
                    if MIDI2Logger.isVerbose {
                        let hexPreview = data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
                        MIDI2Logger.dispatcher.midi2Verbose("Non-SysEx: len=\(data.count) \(hexPreview)")
                    }
                }
                
                // Dispatch to both CI and PE managers
                await ciManager.handleReceivedExternal(received)
                await peManager.handleReceivedExternal(received.data)
            }
            
            MIDI2Logger.dispatcher.midi2Info("Receive dispatcher ended")
        }
    }
    
    // MARK: - Private: CI Event Forwarding
    
    private func startCIEventForwarding() {
        ciEventForwardingTask = Task { [weak self] in
            guard let self else { return }
            
            for await event in ciManager.events {
                if Task.isCancelled { break }
                
                switch event {
                case .deviceDiscovered(let discovered):
                    let device = MIDI2Device(from: discovered, client: self)
                    await self.handleDeviceDiscovered(device)

                case .deviceLost(let muid):
                    await self.handleDeviceLost(muid)

                case .deviceUpdated(let discovered):
                    let device = MIDI2Device(from: discovered, client: self)
                    await self.handleDeviceUpdated(device)
                    
                case .discoveryStarted:
                    await eventHub.broadcast(.discoveryStarted)
                    
                case .discoveryStopped:
                    await eventHub.broadcast(.discoveryStopped)
                }
            }
        }
    }
    
    private func handleDeviceDiscovered(_ device: MIDI2Device) async {
        devices[device.muid] = device
        await eventHub.broadcast(.deviceDiscovered(device))
    }
    
    private func handleDeviceLost(_ muid: MUID) async {
        devices.removeValue(forKey: muid)
        deviceInfoCache.removeValue(forKey: muid)
        await destinationResolver.invalidate(muid: muid)
        await eventHub.broadcast(.deviceLost(muid))
    }
    
    private func handleDeviceUpdated(_ device: MIDI2Device) async {
        devices[device.muid] = device
        await eventHub.broadcast(.deviceUpdated(device))
    }
    
    // MARK: - Private: PE Notification Forwarding
    
    private func startPENotificationForwarding() {
        peNotificationForwardingTask = Task { [weak self] in
            guard let self else { return }
            
            let stream = await peManager.startNotificationStream()
            
            for await notification in stream {
                if Task.isCancelled { break }
                await eventHub.broadcast(.notification(notification))
            }
        }
    }
    
    // MARK: - Private: Setup Change Handling
    
    private func startSetupChangeHandling() {
        setupChangeTask = Task { [weak self] in
            guard let self else { return }
            
            for await _ in transport.setupChanged {
                if Task.isCancelled { break }
                
                // Reconnect to any new sources
                try? await transport.connectToAllSources()
            }
        }
    }
    
    // MARK: - Private: Destination Resolution
    
    private func resolveDestination(for muid: MUID) async throws -> MIDIDestinationID {
        // First check if device exists
        guard devices[muid] != nil else {
            throw MIDI2Error.deviceNotFound(muid: muid)
        }
        
        // Resolve destination
        guard let destination = await destinationResolver.resolve(muid: muid) else {
            _lastDestinationDiagnostics = await destinationResolver.lastDiagnostics
            throw MIDI2Error.deviceNotResponding(
                muid: muid,
                resource: nil,
                timeout: configuration.peTimeout
            )
        }
        
        return destination
    }
}

// MARK: - Duration Extension

extension Duration {
    /// Convert Duration to TimeInterval
    var asTimeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1_000_000_000_000_000_000
    }
}
