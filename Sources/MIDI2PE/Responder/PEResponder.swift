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
import os

private let peRespLog = Logger(subsystem: "com.example.M2DX", category: "PE-Resp")

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

    /// Specific destinations to reply to (nil = broadcast to all)
    public var replyDestinations: [MIDIDestinationID]?

    /// Running state
    private var isRunning = false

    /// Message handling task
    private var handleTask: Task<Void, Never>?

    /// Optional log callback for external diagnostics
    /// Called with (resource, bodyString, replyByteCount)
    public var logCallback: (@Sendable (String, String, Int) -> Void)?

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

    /// Set specific destinations for PE replies
    public func setReplyDestinations(_ destinations: [MIDIDestinationID]) {
        self.replyDestinations = destinations
    }

    /// Returns the set of all subscriber MUIDs (across all resources)
    public func subscriberMUIDs() -> Set<MUID> {
        Set(subscriptions.values.map(\.initiatorMUID))
    }

    /// Set log callback for external diagnostics
    public func setLogCallback(_ callback: @Sendable @escaping (String, String, Int) -> Void) {
        self.logCallback = callback
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
            let msg = "[M2DX] PE-Resp: MUID mismatch dest=\(parsed.destinationMUID) ours=\(muid) type=\(parsed.messageType)"
            print(msg)
            peRespLog.info("\(msg)")
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
        let reqHeaderStr = String(data: inquiry.headerData, encoding: .utf8) ?? "(non-utf8)"
        print("[M2DX] PE-Resp: GET \(resourceName) from \(inquiry.sourceMUID) reqHdr=\(reqHeaderStr)")

        do {
            let responseData = try await resource.get(header: header)

            let headerJSON = resource.responseHeader(for: header, bodyData: responseData)
            let reply = CIMessageBuilder.peGetReply(
                sourceMUID: muid,
                destinationMUID: inquiry.sourceMUID,
                requestID: inquiry.requestID,
                headerData: headerJSON,
                propertyData: responseData
            )

            // Debug: log response details
            let bodyStr = String(data: responseData, encoding: .utf8) ?? "(non-utf8)"
            let headerStr = String(data: headerJSON, encoding: .utf8) ?? "(non-utf8)"
            let replyHex = reply.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[M2DX] PE-Resp: \(resourceName) body=\(responseData.count)B reply=\(reply.count)B hdr=\(headerStr)")
            print("[M2DX] PE-Resp: body=\(bodyStr.prefix(120))")
            print("[M2DX] PE-Resp: hex=\(replyHex)")

            // External log callback
            logCallback?(resourceName, String(bodyStr.prefix(200)), reply.count)

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
        case "notify":
            // Ignore notify commands received as 0x38 — these are our own
            // outbound notifications echoed back, or Initiator acknowledgements.
            break
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
            print("[M2DX] PE-Resp: Subscribe REJECTED \(resourceName) — supportsSubscription=false")
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
        print("[M2DX] PE-Resp: Subscribe OK \(resourceName) subscribeId=\(subscribeId)")
        logCallback?(resourceName, "Subscribe OK subscribeId=\(subscribeId)", 0)
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
    ///   - excludeMUIDs: Set of MUIDs to exclude from notification (e.g. macOS entity)
    public func notify(resource: String, data: Data, excludeMUIDs: Set<MUID> = []) async {
        for (_, subscription) in subscriptions where subscription.resource == resource {
            // Skip excluded MUIDs (e.g. macOS built-in MIDI-CI entity)
            if excludeMUIDs.contains(subscription.initiatorMUID) {
                print("[M2DX] PE-Resp: Notify SKIP \(resource) → \(subscription.initiatorMUID) (excluded)")
                continue
            }

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
        if let targets = replyDestinations, !targets.isEmpty {
            // Send to specific destinations via UMP SysEx7 if possible, else legacy send
            print("[M2DX] PE-Resp: sending \(data.count)B to \(targets.count) targeted dests → \(destinationMUID)")
            if let coreMIDI = transport as? CoreMIDITransport {
                // Use UMP SysEx7 API for reliable delivery on MIDI 2.0 connections
                for dest in targets {
                    do {
                        try await coreMIDI.sendSysEx7AsUMP(data, to: dest)
                    } catch {
                        print("[M2DX] PE-Resp: UMP send to \(dest.value) FAILED: \(error)")
                    }
                }
                print("[M2DX] PE-Resp: UMP targeted send OK")
            } else {
                for dest in targets {
                    do {
                        try await transport.send(data, to: dest)
                    } catch {
                        print("[M2DX] PE-Resp: send to \(dest.value) FAILED: \(error)")
                    }
                }
                print("[M2DX] PE-Resp: targeted send OK")
            }
        } else {
            // Broadcast reply to all destinations
            let dests = await transport.destinations
            print("[M2DX] PE-Resp: broadcasting \(data.count)B to \(dests.count) dests → \(destinationMUID)")
            do {
                try await transport.broadcast(data)
                print("[M2DX] PE-Resp: broadcast OK")
            } catch {
                print("[M2DX] PE-Resp: broadcast FAILED: \(error)")
            }
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
