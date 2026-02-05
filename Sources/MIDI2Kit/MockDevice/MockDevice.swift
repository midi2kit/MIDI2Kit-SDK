//
//  MockDevice.swift
//  MIDI2Kit
//
//  Simulated MIDI-CI device for same-process testing
//

import Foundation
import MIDI2Core
import MIDI2Transport
import MIDI2CI
import MIDI2PE

/// Simulated MIDI-CI device for testing
///
/// MockDevice acts as a complete MIDI-CI Responder, handling:
/// - Discovery Inquiry → Discovery Reply
/// - PE Capability Inquiry → PE Capability Reply
/// - PE GET/SET → Resource responses
/// - PE Subscribe → Subscription management
///
/// ## Usage
/// ```swift
/// // Create loopback transport pair
/// let (initiatorTransport, responderTransport) = await LoopbackTransport.createPair()
///
/// // Create mock device
/// let mockDevice = MockDevice(
///     preset: .korgModulePro,
///     transport: responderTransport
/// )
/// await mockDevice.start()
///
/// // Create client using initiator transport
/// let client = MIDI2Client(
///     configuration: .standard,
///     transport: initiatorTransport
/// )
/// try await client.start()
///
/// // Client will discover mockDevice and can perform PE operations
/// ```
public actor MockDevice {

    // MARK: - Properties

    /// Device MUID
    public let muid: MUID

    /// Device identity
    public let identity: DeviceIdentity

    /// Category support
    public let categorySupport: CategorySupport

    /// Transport for communication
    private let transport: any MIDITransport

    /// PE Responder
    private let peResponder: PEResponder

    /// Running state
    private var isRunning = false

    /// Message handling task
    private var handleTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Create a mock device
    ///
    /// - Parameters:
    ///   - muid: Device MUID (random if not specified)
    ///   - identity: Device identity
    ///   - categorySupport: Supported categories
    ///   - transport: MIDI transport
    public init(
        muid: MUID = MUID.random(),
        identity: DeviceIdentity = .default,
        categorySupport: CategorySupport = .propertyExchange,
        transport: any MIDITransport
    ) {
        self.muid = muid
        self.identity = identity
        self.categorySupport = categorySupport
        self.transport = transport
        self.peResponder = PEResponder(muid: muid, transport: transport)
    }

    /// Create a mock device from a preset
    ///
    /// - Parameters:
    ///   - preset: Device preset configuration
    ///   - transport: MIDI transport
    public init(preset: MockDevicePreset, transport: any MIDITransport) {
        self.muid = MUID.random()
        self.identity = preset.identity
        self.categorySupport = preset.categorySupport
        self.transport = transport
        self.peResponder = PEResponder(muid: muid, transport: transport)

        // Register preset resources - done in start() because we're in init
    }

    // MARK: - Lifecycle

    /// Start the mock device
    ///
    /// Begins handling MIDI-CI messages and responding to inquiries.
    public func start() async {
        guard !isRunning else { return }
        isRunning = true

        // Start PE responder
        await peResponder.start()

        // Start handling CI messages
        handleTask = Task { [weak self] in
            guard let self = self else { return }
            for await received in transport.received {
                guard await self.isRunning else { break }
                await self.handleMessage(received.data)
            }
        }
    }

    /// Stop the mock device
    public func stop() async {
        isRunning = false
        handleTask?.cancel()
        handleTask = nil
        await peResponder.stop()
    }

    // MARK: - Resource Management

    /// Register a resource
    ///
    /// - Parameters:
    ///   - name: Resource name (e.g., "DeviceInfo")
    ///   - resource: Resource implementation
    public func registerResource(_ name: String, resource: any PEResponderResource) async {
        await peResponder.registerResource(name, resource: resource)
    }

    /// Register a static JSON resource
    ///
    /// - Parameters:
    ///   - name: Resource name
    ///   - json: JSON string content
    public func registerStaticResource(_ name: String, json: String) async {
        await peResponder.registerResource(name, resource: StaticResource(json: json))
    }

    /// Register resources from a preset
    public func registerPresetResources(_ preset: MockDevicePreset) async {
        for (name, json) in preset.resources {
            await registerStaticResource(name, json: json)
        }
    }

    /// Set a resource value (for InMemoryResource)
    public func setResourceValue<T: Encodable & Sendable>(_ name: String, value: T) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let resource = InMemoryResource(data: data)
        await peResponder.registerResource(name, resource: resource)
    }

    // MARK: - Message Handling

    private func handleMessage(_ data: [UInt8]) async {
        // Parse as CI message
        guard let parsed = CIMessageParser.parse(data) else { return }

        // Check if message is for us or broadcast
        guard parsed.destinationMUID == muid || parsed.destinationMUID == MUID.broadcast else {
            return
        }

        switch parsed.messageType {
        case .discoveryInquiry:
            await handleDiscoveryInquiry(parsed)

        case .peCapabilityInquiry, .peGetInquiry, .peSetInquiry, .peSubscribe:
            // PE messages are handled by PEResponder
            await peResponder.handleMessage(data)

        default:
            break
        }
    }

    // MARK: - Discovery

    private func handleDiscoveryInquiry(_ parsed: CIMessageParser.ParsedMessage) async {
        let reply = CIMessageBuilder.discoveryReply(
            sourceMUID: muid,
            destinationMUID: parsed.sourceMUID,
            deviceIdentity: identity,
            categorySupport: categorySupport,
            maxSysExSize: 0,
            initiatorOutputPath: 0,
            functionBlock: 0
        )

        await sendMessage(reply)
    }

    // MARK: - Helpers

    private func sendMessage(_ data: [UInt8]) async {
        let destinations = await transport.destinations
        guard let dest = destinations.first else { return }

        do {
            try await transport.send(data, to: dest.destinationID)
        } catch {
            // Log but don't throw
        }
    }

    // MARK: - Notification

    /// Send notification to subscribers
    ///
    /// - Parameters:
    ///   - resource: Resource name
    ///   - data: Notification data
    public func notify(resource: String, data: Data) async {
        await peResponder.notify(resource: resource, data: data)
    }

    /// Send notification with JSON value
    public func notify<T: Encodable & Sendable>(resource: String, value: T) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        await notify(resource: resource, data: data)
    }
}

// MARK: - Convenience Factory Methods

extension MockDevice {

    /// Create a mock KORG Module Pro device
    public static func korgModulePro(transport: any MIDITransport) async -> MockDevice {
        let device = MockDevice(preset: .korgModulePro, transport: transport)
        await device.registerPresetResources(.korgModulePro)
        return device
    }

    /// Create a generic MIDI 2.0 device
    public static func generic(
        name: String = "Mock Device",
        transport: any MIDITransport
    ) async -> MockDevice {
        let preset = MockDevicePreset.generic(name: name)
        let device = MockDevice(preset: preset, transport: transport)
        await device.registerPresetResources(preset)
        return device
    }
}
