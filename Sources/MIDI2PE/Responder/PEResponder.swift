//
//  PEResponder.swift
//  MIDI2Kit
//
//  Property Exchange Responder for handling incoming PE requests
//

import Foundation
import MIDI2Core
import MIDI2Transport
import MIDI2CI

/// Property Exchange Responder
///
/// Handles incoming PE Inquiry messages and returns appropriate replies.
/// Use with LoopbackTransport for same-process testing or with CoreMIDITransport
/// to act as a real MIDI-CI Responder.
///
/// ## Usage
/// ```swift
/// let responder = PEResponder(muid: myMUID, transport: transport)
///
/// // Register resources
/// await responder.registerResource(
///     "DeviceInfo",
///     resource: StaticResource(json: "{\"manufacturer\":\"Test\"}")
/// )
///
/// // Start handling messages
/// await responder.start()
/// ```
public actor PEResponder {

    // MARK: - Types

    /// Subscription info
    private struct Subscription: Sendable {
        let subscribeId: String
        let resource: String
        let initiatorMUID: MUID
    }

    // MARK: - Properties

    /// This responder's MUID
    public let muid: MUID

    /// Transport for sending/receiving messages
    private let transport: any MIDITransport

    /// Registered resources
    private var resources: [String: any PEResponderResource] = [:]

    /// Active subscriptions
    private var subscriptions: [String: Subscription] = [:]

    /// Next subscription ID counter
    private var nextSubscriptionId: UInt32 = 1

    /// Running state
    private var isRunning = false

    /// Message handling task
    private var handleTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Create a PE Responder
    ///
    /// - Parameters:
    ///   - muid: MUID for this responder
    ///   - transport: MIDI transport for communication
    public init(muid: MUID, transport: any MIDITransport) {
        self.muid = muid
        self.transport = transport
    }

    // MARK: - Resource Management

    /// Register a resource
    ///
    /// - Parameters:
    ///   - name: Resource name (e.g., "DeviceInfo", "ResourceList")
    ///   - resource: Resource implementation
    public func registerResource(_ name: String, resource: any PEResponderResource) {
        resources[name] = resource
    }

    /// Unregister a resource
    public func unregisterResource(_ name: String) {
        resources.removeValue(forKey: name)
    }

    /// Get registered resource names
    public var registeredResources: [String] {
        Array(resources.keys)
    }

    // MARK: - Lifecycle

    /// Start handling PE messages
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        handleTask = Task {
            for await received in self.transport.received {
                guard self.isRunning else { break }
                await self.handleMessage(received.data)
            }
        }
    }

    /// Stop handling PE messages
    public func stop() {
        isRunning = false
        handleTask?.cancel()
        handleTask = nil
    }

    // MARK: - Message Handling

    /// Handle incoming MIDI message
    ///
    /// - Parameter data: Raw MIDI data
    public func handleMessage(_ data: [UInt8]) async {
        // Parse as CI message
        guard let parsed = CIMessageParser.parse(data) else { return }

        // Check if message is for us
        guard parsed.destinationMUID == muid || parsed.destinationMUID == MUID.broadcast else {
            return
        }

        switch parsed.messageType {
        case .peCapabilityInquiry:
            await handlePECapabilityInquiry(parsed)

        case .peGetInquiry:
            await handlePEGetInquiry(data)

        case .peSetInquiry:
            await handlePESetInquiry(data)

        case .peSubscribe:
            await handlePESubscribeInquiry(data)

        default:
            // Ignore other message types
            break
        }
    }

    // MARK: - PE Capability

    private func handlePECapabilityInquiry(_ parsed: CIMessageParser.ParsedMessage) async {
        let reply = CIMessageBuilder.peCapabilityReply(
            sourceMUID: muid,
            destinationMUID: parsed.sourceMUID,
            numSimultaneousRequests: 4,
            majorVersion: 0,
            minorVersion: 2
        )

        await sendReply(reply, to: parsed.sourceMUID)
    }

    // MARK: - PE GET

    private func handlePEGetInquiry(_ data: [UInt8]) async {
        guard let inquiry = CIMessageParser.parseFullPEGetInquiry(data) else { return }

        guard let resourceName = inquiry.resource else {
            await sendErrorReply(
                type: .peGetReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 400,
                message: "Missing resource name"
            )
            return
        }

        guard let resource = resources[resourceName] else {
            await sendErrorReply(
                type: .peGetReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 404,
                message: "Resource not found: \(resourceName)"
            )
            return
        }

        // Parse header
        let header = PERequestHeader(data: inquiry.headerData)

        do {
            let responseData = try await resource.get(header: header)

            let reply = CIMessageBuilder.peGetReply(
                sourceMUID: muid,
                destinationMUID: inquiry.sourceMUID,
                requestID: inquiry.requestID,
                headerData: CIMessageBuilder.successResponseHeader(),
                propertyData: responseData
            )

            await sendReply(reply, to: inquiry.sourceMUID)
        } catch {
            await sendErrorReply(
                type: .peGetReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 500,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - PE SET

    private func handlePESetInquiry(_ data: [UInt8]) async {
        guard let inquiry = CIMessageParser.parseFullPESetInquiry(data) else { return }

        guard let resourceName = inquiry.resource else {
            await sendErrorReply(
                type: .peSetReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 400,
                message: "Missing resource name"
            )
            return
        }

        guard let resource = resources[resourceName] else {
            await sendErrorReply(
                type: .peSetReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 404,
                message: "Resource not found: \(resourceName)"
            )
            return
        }

        // Parse header
        let header = PERequestHeader(data: inquiry.headerData)

        do {
            _ = try await resource.set(header: header, body: inquiry.propertyData)

            let reply = CIMessageBuilder.peSetReply(
                sourceMUID: muid,
                destinationMUID: inquiry.sourceMUID,
                requestID: inquiry.requestID,
                headerData: CIMessageBuilder.successResponseHeader()
            )

            await sendReply(reply, to: inquiry.sourceMUID)
        } catch PEResponderError.readOnly {
            await sendErrorReply(
                type: .peSetReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 405,
                message: "Resource is read-only"
            )
        } catch {
            await sendErrorReply(
                type: .peSetReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 500,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - PE Subscribe

    private func handlePESubscribeInquiry(_ data: [UInt8]) async {
        guard let inquiry = CIMessageParser.parseFullPESubscribeInquiry(data) else { return }

        let command = inquiry.command ?? "start"

        switch command {
        case "start":
            await handleSubscribeStart(inquiry)
        case "end":
            await handleSubscribeEnd(inquiry)
        default:
            await sendErrorReply(
                type: .peSubscribeReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 400,
                message: "Unknown command: \(command)"
            )
        }
    }

    private func handleSubscribeStart(_ inquiry: CIMessageParser.FullPESubscribeInquiry) async {
        guard let resourceName = inquiry.resource else {
            await sendErrorReply(
                type: .peSubscribeReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 400,
                message: "Missing resource name"
            )
            return
        }

        guard let resource = resources[resourceName] else {
            await sendErrorReply(
                type: .peSubscribeReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 404,
                message: "Resource not found"
            )
            return
        }

        guard resource.supportsSubscription else {
            await sendErrorReply(
                type: .peSubscribeReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 405,
                message: "Resource does not support subscriptions"
            )
            return
        }

        // Generate subscription ID
        let subscribeId = "sub-\(nextSubscriptionId)"
        nextSubscriptionId += 1

        // Store subscription
        subscriptions[subscribeId] = Subscription(
            subscribeId: subscribeId,
            resource: resourceName,
            initiatorMUID: inquiry.sourceMUID
        )

        // Send reply
        let headerData = CIMessageBuilder.subscribeResponseHeader(
            status: 200,
            subscribeId: subscribeId
        )

        let reply = CIMessageBuilder.peSubscribeReply(
            sourceMUID: muid,
            destinationMUID: inquiry.sourceMUID,
            requestID: inquiry.requestID,
            headerData: headerData
        )

        await sendReply(reply, to: inquiry.sourceMUID)
    }

    private func handleSubscribeEnd(_ inquiry: CIMessageParser.FullPESubscribeInquiry) async {
        guard let subscribeId = inquiry.subscribeId else {
            await sendErrorReply(
                type: .peSubscribeReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 400,
                message: "Missing subscribeId"
            )
            return
        }

        guard subscriptions[subscribeId] != nil else {
            await sendErrorReply(
                type: .peSubscribeReply,
                requestID: inquiry.requestID,
                to: inquiry.sourceMUID,
                status: 404,
                message: "Subscription not found"
            )
            return
        }

        // Remove subscription
        subscriptions.removeValue(forKey: subscribeId)

        // Send reply
        let reply = CIMessageBuilder.peSubscribeReply(
            sourceMUID: muid,
            destinationMUID: inquiry.sourceMUID,
            requestID: inquiry.requestID,
            headerData: CIMessageBuilder.successResponseHeader()
        )

        await sendReply(reply, to: inquiry.sourceMUID)
    }

    // MARK: - Notify

    /// Send notification to all subscribers of a resource
    ///
    /// - Parameters:
    ///   - resource: Resource name
    ///   - data: Notification data
    public func notify(resource: String, data: Data) async {
        for (_, subscription) in subscriptions where subscription.resource == resource {
            let headerData = CIMessageBuilder.notifyHeader(
                subscribeId: subscription.subscribeId,
                resource: resource
            )

            let message = CIMessageBuilder.peNotify(
                sourceMUID: muid,
                destinationMUID: subscription.initiatorMUID,
                requestID: 0,
                headerData: headerData,
                propertyData: data
            )

            await sendReply(message, to: subscription.initiatorMUID)
        }
    }

    // MARK: - Helpers

    private func sendReply(_ data: [UInt8], to destinationMUID: MUID) async {
        // Find destination for this MUID
        // In loopback, we just need any destination
        let destinations = await transport.destinations
        guard let dest = destinations.first else { return }

        do {
            try await transport.send(data, to: dest.destinationID)
        } catch {
            // TODO: Add logger parameter to PEResponder for proper logging
            #if DEBUG
            print("⚠️ PEResponder: failed to send reply to \(destinationMUID): \(error)")
            #endif
        }
    }

    private enum ReplyType {
        case peGetReply
        case peSetReply
        case peSubscribeReply
    }

    private func sendErrorReply(
        type: ReplyType,
        requestID: UInt8,
        to destinationMUID: MUID,
        status: Int,
        message: String
    ) async {
        let headerData = CIMessageBuilder.errorResponseHeader(status: status, message: message)

        let reply: [UInt8]
        switch type {
        case .peGetReply:
            reply = CIMessageBuilder.peGetReply(
                sourceMUID: muid,
                destinationMUID: destinationMUID,
                requestID: requestID,
                headerData: headerData,
                propertyData: Data()
            )
        case .peSetReply:
            reply = CIMessageBuilder.peSetReply(
                sourceMUID: muid,
                destinationMUID: destinationMUID,
                requestID: requestID,
                headerData: headerData
            )
        case .peSubscribeReply:
            reply = CIMessageBuilder.peSubscribeReply(
                sourceMUID: muid,
                destinationMUID: destinationMUID,
                requestID: requestID,
                headerData: headerData
            )
        }

        await sendReply(reply, to: destinationMUID)
    }
}
