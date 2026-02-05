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

    /// Last communication trace
    private var _lastCommunicationTrace: CommunicationTrace?

    /// Warm-up cache for adaptive strategy
    private let warmUpCache: WarmUpCache

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
            registerFromInquiry: configuration.registerFromInquiry,
            categorySupport: configuration.categorySupport,
            deviceIdentity: configuration.deviceIdentity,
            maxSysExSize: configuration.maxSysExSize
        )
        self.ciManager = CIManager(
            transport: transport,
            muid: muid,
            configuration: ciConfig,
            logger: configuration.logger
        )
        
        // Initialize PE Manager
        self.peManager = PEManager(
            transport: transport,
            sourceMUID: muid,
            maxInflightPerDevice: configuration.maxInflightPerDevice,
            notifyAssemblyTimeout: 2.0,  // Use default
            destinationCacheTTL: configuration.destinationCacheTTL.asTimeInterval,
            sendStrategy: configuration.peSendStrategy,
            logger: configuration.logger
        )
        
        // Initialize event hub
        self.eventHub = ReceiveHub<MIDI2ClientEvent>()
        
        // Initialize destination resolver
        self.destinationResolver = DestinationResolver(
            strategy: configuration.destinationStrategy,
            transport: transport
        )

        // Initialize warm-up cache for adaptive strategy
        self.warmUpCache = WarmUpCache()
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

        let info = try await executeWithDestinationFallback(
            muid: muid,
            operation: .getDeviceInfo,
            resource: "DeviceInfo"
        ) { [peManager] handle in
            try await peManager.getDeviceInfo(from: handle)
        }

        // Cache the result
        deviceInfoCache[muid] = info
        return info
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
    /// Uses the configured `warmUpStrategy` to determine warm-up behavior:
    /// - `.always`: Always fetch DeviceInfo before ResourceList
    /// - `.never`: Skip warm-up entirely
    /// - `.adaptive`: Try without warm-up, retry with warm-up on failure
    /// - `.vendorBased`: Use vendor-specific optimizations
    ///
    /// On timeout, the method tries the next destination candidate (max 1 retry).
    ///
    /// - Parameter muid: The device MUID
    /// - Returns: Array of available resources
    /// - Throws: `MIDI2Error` on failure after all retries
    public func getResourceList(from muid: MUID) async throws -> [PEResourceEntry] {
        guard isRunning else { throw MIDI2Error.clientNotRunning }

        let startTime = Date()
        let destination = try await resolveDestination(for: muid)
        let handle = PEDeviceHandle(muid: muid, destination: destination)

        // Calculate timeout for multi-chunk request
        let timeout = Duration.seconds(
            configuration.peTimeout.asTimeInterval * configuration.multiChunkTimeoutMultiplier
        )

        // Determine warm-up behavior based on strategy
        let shouldWarmUp = await determineWarmUpNeeded(for: muid, strategy: configuration.warmUpStrategy)
        let useVendorWarmUp = configuration.warmUpStrategy == .vendorBased

        if shouldWarmUp {
            await performWarmUp(handle: handle, useVendorWarmUp: useVendorWarmUp)
        }

        // First attempt
        do {
            let result = try await fetchResourceList(handle: handle, timeout: timeout, muid: muid, startTime: startTime)

            // Record success for adaptive strategy
            if configuration.warmUpStrategy == .adaptive && !shouldWarmUp {
                let deviceKey = await getDeviceKey(for: muid)
                await warmUpCache.recordNoWarmUpNeeded(deviceKey)
            }

            return result
        } catch let error as PEError {
            // For adaptive strategy: if we didn't warm up, retry with warm-up
            if configuration.warmUpStrategy == .adaptive && !shouldWarmUp {
                if case .timeout = error {
                    MIDI2Logger.pe.midi2Info("Adaptive: ResourceList failed without warm-up, retrying with warm-up")

                    // Record that this device needs warm-up
                    let deviceKey = await getDeviceKey(for: muid)
                    await warmUpCache.recordNeedsWarmUp(deviceKey)

                    // Perform warm-up and retry
                    await performWarmUp(handle: handle)

                    do {
                        let result = try await fetchResourceList(handle: handle, timeout: timeout, muid: muid, startTime: startTime)
                        MIDI2Logger.pe.midi2Info("Adaptive: ResourceList succeeded with warm-up")
                        return result
                    } catch {
                        // Fall through to destination fallback
                        MIDI2Logger.pe.midi2Warning("Adaptive: ResourceList still failed after warm-up")
                    }
                }
            }

            // Try destination fallback on timeout
            if case .timeout = error {
                if let nextDest = await destinationResolver.getNextCandidate(after: destination, for: muid) {
                    MIDI2Logger.pe.midi2Info("ResourceList timeout, trying fallback destination: \(nextDest)")
                    let retryHandle = PEDeviceHandle(muid: muid, destination: nextDest)

                    // Warm-up for fallback destination if needed
                    if shouldWarmUp || configuration.warmUpStrategy == .adaptive {
                        await performWarmUp(handle: retryHandle)
                    }

                    do {
                        let result = try await peManager.getResourceList(
                            from: retryHandle,
                            timeout: timeout,
                            maxRetries: configuration.maxRetries
                        )
                        await destinationResolver.cacheDestination(nextDest, for: muid)
                        MIDI2Logger.pe.midi2Info("ResourceList succeeded with fallback destination")
                        recordTrace(
                            operation: .getResourceList,
                            muid: muid,
                            resource: "ResourceList",
                            result: .success,
                            destination: nextDest,
                            duration: Date().timeIntervalSince(startTime)
                        )
                        return result
                    } catch {
                        MIDI2Logger.pe.midi2Error("ResourceList failed on fallback destination: \(error)")
                        recordTrace(
                            operation: .getResourceList,
                            muid: muid,
                            resource: "ResourceList",
                            result: .timeout,
                            destination: nextDest,
                            duration: Date().timeIntervalSince(startTime),
                            errorMessage: error.localizedDescription
                        )
                        throw MIDI2Error(from: error as? PEError ?? .timeout(resource: "ResourceList"), muid: muid, timeout: timeout)
                    }
                }
            }

            let resultType: CommunicationTrace.Result = {
                if case .timeout = error { return .timeout }
                return .error
            }()
            recordTrace(
                operation: .getResourceList,
                muid: muid,
                resource: "ResourceList",
                result: resultType,
                destination: destination,
                duration: Date().timeIntervalSince(startTime),
                errorMessage: error.localizedDescription
            )
            throw MIDI2Error(from: error, muid: muid, timeout: timeout)
        }
    }

    // MARK: - Private: Warm-Up Helpers

    /// Determine if warm-up is needed based on strategy and cache
    private func determineWarmUpNeeded(for muid: MUID, strategy: WarmUpStrategy) async -> Bool {
        switch strategy {
        case .always:
            return true

        case .never:
            return false

        case .adaptive:
            let deviceKey = await getDeviceKey(for: muid)
            // Check cache - if device is known to need warm-up, do it
            if await warmUpCache.needsWarmUp(for: deviceKey) {
                return true
            }
            // If device is known to work without warm-up, skip it
            if await warmUpCache.canSkipWarmUp(for: deviceKey) {
                return false
            }
            // Unknown device - try without warm-up first
            return false

        case .vendorBased:
            // Check vendor optimizations
            let vendor = await detectVendor(for: muid)
            if vendor == .korg {
                // KORG with vendor optimizations: use X-ParameterList as warmup
                if configuration.vendorOptimizations.isEnabled(.useXParameterListAsWarmup, for: .korg) {
                    // Use X-ParameterList as warm-up (handled in performWarmUp)
                    return true
                }
            }
            // Fall back to adaptive behavior for other vendors
            let deviceKey = await getDeviceKey(for: muid)
            if await warmUpCache.needsWarmUp(for: deviceKey) {
                return true
            }
            if await warmUpCache.canSkipWarmUp(for: deviceKey) {
                return false
            }
            // Unknown device - try without warm-up first (adaptive behavior)
            return false
        }
    }

    /// Perform warm-up request
    ///
    /// For vendorBased strategy with KORG, uses X-ParameterList instead of DeviceInfo
    /// as warm-up, which can provide useful data while stabilizing the connection.
    private func performWarmUp(handle: PEDeviceHandle, useVendorWarmUp: Bool = false) async {
        if useVendorWarmUp {
            let vendor = await detectVendor(for: handle.muid)
            if vendor == .korg && configuration.vendorOptimizations.isEnabled(.useXParameterListAsWarmup, for: .korg) {
                MIDI2Logger.pe.midi2Debug("KORG vendor warm-up: fetching X-ParameterList for device \(handle.muid)")
                do {
                    let response = try await peManager.get("X-ParameterList", from: handle, timeout: .seconds(3))
                    MIDI2Logger.pe.midi2Debug("KORG vendor warm-up successful (X-ParameterList: \(response.decodedBody.count) bytes)")
                } catch {
                    MIDI2Logger.pe.midi2Warning("KORG vendor warm-up failed (\(error)), falling back to DeviceInfo")
                    // Fall back to standard warm-up
                    await performStandardWarmUp(handle: handle)
                }
                try? await Task.sleep(for: .milliseconds(50))
                return
            }
        }

        // Standard warm-up using DeviceInfo
        await performStandardWarmUp(handle: handle)
    }

    /// Standard warm-up using DeviceInfo
    private func performStandardWarmUp(handle: PEDeviceHandle) async {
        MIDI2Logger.pe.midi2Debug("Performing standard warm-up (DeviceInfo) for device \(handle.muid)")
        do {
            _ = try await peManager.getDeviceInfo(from: handle)
            MIDI2Logger.pe.midi2Debug("Warm-up successful")
        } catch {
            MIDI2Logger.pe.midi2Warning("Warm-up failed (\(error)), proceeding anyway")
        }
        // Small delay to let connection stabilize
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// Fetch ResourceList with tracing
    private func fetchResourceList(
        handle: PEDeviceHandle,
        timeout: Duration,
        muid: MUID,
        startTime: Date
    ) async throws -> [PEResourceEntry] {
        let result = try await peManager.getResourceList(
            from: handle,
            timeout: timeout,
            maxRetries: configuration.maxRetries
        )
        recordTrace(
            operation: .getResourceList,
            muid: muid,
            resource: "ResourceList",
            result: .success,
            destination: handle.destination,
            duration: Date().timeIntervalSince(startTime)
        )
        return result
    }

    /// Get device key for warm-up cache
    private func getDeviceKey(for muid: MUID) async -> String {
        if let info = deviceInfoCache[muid] {
            return WarmUpCache.deviceKey(manufacturer: info.manufacturerName, model: info.productName)
        }
        // Fallback to MUID-based key
        return WarmUpCache.deviceKey(muid: muid)
    }

    /// Detect vendor for a device
    private func detectVendor(for muid: MUID) async -> MIDIVendor {
        if let info = deviceInfoCache[muid] {
            return MIDIVendor.detect(from: info.manufacturerName)
        }
        return .unknown
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
        try await executeWithDestinationFallback(
            muid: muid,
            operation: .getProperty,
            resource: resource
        ) { [peManager, configuration] handle in
            try await peManager.get(
                resource,
                from: handle,
                timeout: timeout ?? configuration.peTimeout
            )
        }
    }

    /// Get a channel-specific property
    public func get(
        _ resource: String,
        channel: Int,
        from muid: MUID,
        timeout: Duration? = nil
    ) async throws -> PEResponse {
        try await executeWithDestinationFallback(
            muid: muid,
            operation: .getProperty,
            resource: resource
        ) { [peManager, configuration] handle in
            try await peManager.get(
                resource,
                channel: channel,
                from: handle,
                timeout: timeout ?? configuration.peTimeout
            )
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
        try await executeWithDestinationFallback(
            muid: muid,
            operation: .setProperty,
            resource: resource
        ) { [peManager, configuration] handle in
            try await peManager.set(
                resource,
                data: data,
                to: handle,
                timeout: timeout ?? configuration.peTimeout
            )
        }
    }

    // MARK: - Diagnostics
    
    /// Last destination resolution diagnostics
    public var lastDestinationDiagnostics: DestinationDiagnostics? {
        get async {
            await destinationResolver.lastDiagnostics
        }
    }

    /// Last communication trace
    ///
    /// Provides detailed information about the most recent Property Exchange
    /// operation for debugging purposes.
    public var lastCommunicationTrace: CommunicationTrace? {
        _lastCommunicationTrace
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
    
    // MARK: - Private: Trace Recording

    /// Record a communication trace
    private func recordTrace(
        operation: CommunicationTrace.Operation,
        muid: MUID,
        resource: String? = nil,
        result: CommunicationTrace.Result,
        destination: MIDIDestinationID? = nil,
        duration: TimeInterval,
        errorMessage: String? = nil
    ) {
        _lastCommunicationTrace = CommunicationTrace(
            operation: operation,
            muid: muid,
            resource: resource,
            result: result,
            destination: destination,
            duration: duration,
            errorMessage: errorMessage
        )
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
    
    // MARK: - Private: Operation Execution with Fallback

    /// Execute an operation with automatic destination fallback on timeout
    ///
    /// This method centralizes the common pattern of:
    /// 1. Resolving destination for a device
    /// 2. Executing an operation
    /// 3. On timeout, trying the next destination candidate
    /// 4. Recording traces for diagnostics
    ///
    /// - Parameters:
    ///   - muid: Target device MUID
    ///   - operation: Operation type for tracing
    ///   - resource: Optional resource name for tracing
    ///   - execute: The operation to execute, receives a PEDeviceHandle
    /// - Returns: The operation result
    /// - Throws: MIDI2Error on failure
    private func executeWithDestinationFallback<T: Sendable>(
        muid: MUID,
        operation: CommunicationTrace.Operation,
        resource: String? = nil,
        execute: @Sendable @escaping (PEDeviceHandle) async throws -> T
    ) async throws -> T {
        guard isRunning else { throw MIDI2Error.clientNotRunning }

        let startTime = Date()
        let destination = try await resolveDestination(for: muid)
        let handle = PEDeviceHandle(muid: muid, destination: destination)

        do {
            let result = try await execute(handle)
            recordTrace(
                operation: operation,
                muid: muid,
                resource: resource,
                result: .success,
                destination: destination,
                duration: Date().timeIntervalSince(startTime)
            )
            return result
        } catch let error as PEError {
            // Try fallback on timeout
            if case .timeout = error {
                if let nextDest = await destinationResolver.getNextCandidate(after: destination, for: muid) {
                    MIDI2Logger.pe.midi2Debug("\(operation) timeout, trying fallback destination")
                    let retryHandle = PEDeviceHandle(muid: muid, destination: nextDest)
                    do {
                        let result = try await execute(retryHandle)
                        await destinationResolver.cacheDestination(nextDest, for: muid)
                        recordTrace(
                            operation: operation,
                            muid: muid,
                            resource: resource,
                            result: .success,
                            destination: nextDest,
                            duration: Date().timeIntervalSince(startTime)
                        )
                        return result
                    } catch {
                        recordTrace(
                            operation: operation,
                            muid: muid,
                            resource: resource,
                            result: .timeout,
                            destination: nextDest,
                            duration: Date().timeIntervalSince(startTime),
                            errorMessage: error.localizedDescription
                        )
                        if let peError = error as? PEError {
                            throw MIDI2Error(from: peError, muid: muid)
                        } else {
                            throw MIDI2Error.deviceNotResponding(
                                muid: muid,
                                resource: resource,
                                timeout: configuration.peTimeout
                            )
                        }
                    }
                }
            }
            let resultType: CommunicationTrace.Result = {
                if case .timeout = error { return .timeout }
                return .error
            }()
            recordTrace(
                operation: operation,
                muid: muid,
                resource: resource,
                result: resultType,
                destination: destination,
                duration: Date().timeIntervalSince(startTime),
                errorMessage: error.localizedDescription
            )
            throw MIDI2Error(from: error, muid: muid)
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
