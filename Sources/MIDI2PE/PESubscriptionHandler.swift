//
//  PESubscriptionHandler.swift
//  MIDI2Kit
//
//  Handles Property Exchange Subscribe/Unsubscribe/Notify operations
//  Extracted from PEManager for better modularity (Phase 5-1)
//

import Foundation
import MIDI2CI
import MIDI2Core
import MIDI2Transport

// MARK: - PESubscriptionHandler

/// Actor responsible for handling Property Exchange Subscribe/Unsubscribe/Notify operations
///
/// This actor was extracted from PEManager to reduce complexity and improve maintainability.
/// It manages:
/// - Subscribe/Unsubscribe request lifecycle
/// - Active subscription tracking
/// - Notification stream distribution
/// - Subscribe reply processing
/// - Notify message dispatch
///
/// ## Architecture
///
/// PESubscriptionHandler uses dependency injection to coordinate with PEManager:
/// - **Shared dependencies**: transactionManager, notifyAssemblyManager, logger
/// - **Callbacks**: Coordinates timeout/send task management via callbacks
/// - **Delegation**: PEManager delegates Subscribe/Notify messages to this handler
///
/// ## Thread Safety
///
/// All state is actor-isolated, ensuring thread-safe access to:
/// - pendingSubscribeContinuations (awaiting Subscribe responses)
/// - activeSubscriptions (currently active subscriptions)
/// - notificationContinuation (notification stream listener)
///
internal actor PESubscriptionHandler {

    // MARK: - State

    /// Pending Subscribe/Unsubscribe continuations keyed by Request ID
    private var pendingSubscribeContinuations: [UInt8: CheckedContinuation<PESubscribeResponse, Error>] = [:]

    /// Active subscriptions keyed by subscribeId
    private var activeSubscriptions: [String: PESubscription] = [:]

    /// Notification stream continuation (single listener)
    private var notificationContinuation: AsyncStream<PENotification>.Continuation?

    // MARK: - Dependencies

    /// Our MUID for constructing messages
    private let sourceMUID: MUID

    /// Transaction manager for Request ID allocation
    private let transactionManager: PETransactionManager

    /// Notify assembly manager for multi-chunk Notify reassembly
    private let notifyAssemblyManager: PENotifyAssemblyManager

    /// Logger for debugging
    private let logger: any MIDI2Logger

    // MARK: - Callbacks to PEManager

    /// Schedule a timeout task
    /// - Parameters:
    ///   - requestID: Request ID to timeout
    ///   - duration: Timeout duration
    ///   - action: Action to execute on timeout
    private let scheduleTimeout: @Sendable (UInt8, Duration, @escaping @Sendable () async -> Void) -> Void

    /// Cancel a timeout task
    /// - Parameter requestID: Request ID to cancel timeout for
    private let cancelTimeout: @Sendable (UInt8) -> Void

    /// Schedule a send task
    /// - Parameters:
    ///   - requestID: Request ID
    ///   - message: Message bytes to send
    ///   - destination: MIDI destination
    private let scheduleSend: @Sendable (UInt8, [UInt8], MIDIDestinationID) -> Void

    /// Cancel a send task
    /// - Parameter requestID: Request ID to cancel send for
    private let cancelSend: @Sendable (UInt8) -> Void

    // MARK: - Initialization

    /// Create a new subscription handler
    /// - Parameters:
    ///   - sourceMUID: Our MUID for constructing messages
    ///   - transactionManager: Transaction manager for Request ID allocation
    ///   - notifyAssemblyManager: Notify assembly manager for multi-chunk Notify
    ///   - logger: Logger for debugging
    ///   - scheduleTimeout: Callback to schedule timeout tasks
    ///   - cancelTimeout: Callback to cancel timeout tasks
    ///   - scheduleSend: Callback to schedule send tasks
    ///   - cancelSend: Callback to cancel send tasks
    init(
        sourceMUID: MUID,
        transactionManager: PETransactionManager,
        notifyAssemblyManager: PENotifyAssemblyManager,
        logger: any MIDI2Logger,
        scheduleTimeout: @escaping @Sendable (UInt8, Duration, @escaping @Sendable () async -> Void) -> Void,
        cancelTimeout: @escaping @Sendable (UInt8) -> Void,
        scheduleSend: @escaping @Sendable (UInt8, [UInt8], MIDIDestinationID) -> Void,
        cancelSend: @escaping @Sendable (UInt8) -> Void
    ) {
        self.sourceMUID = sourceMUID
        self.transactionManager = transactionManager
        self.notifyAssemblyManager = notifyAssemblyManager
        self.logger = logger
        self.scheduleTimeout = scheduleTimeout
        self.cancelTimeout = cancelTimeout
        self.scheduleSend = scheduleSend
        self.cancelSend = cancelSend
    }

    // MARK: - Public API (Called by PEManager)

    /// Begin a Subscribe request
    /// - Parameters:
    ///   - resource: Resource to subscribe to
    ///   - device: Device handle
    ///   - timeout: Timeout duration
    /// - Returns: Request ID and message bytes to send
    /// - Throws: PEError if request cannot be initiated
    func beginSubscribe(
        resource: String,
        device: PEDeviceHandle,
        timeout: Duration
    ) async throws -> (requestID: UInt8, message: [UInt8]) {
        logger.debug("SUBSCRIBE \(resource) on \(device.debugDescription)", category: "PESubscriptionHandler")

        guard let requestID = await transactionManager.begin(
            resource: resource,
            destinationMUID: device.muid,
            timeout: timeout.asTimeInterval
        ) else {
            throw PEError.requestIDExhausted
        }

        let headerData = CIMessageBuilder.subscribeStartHeader(resource: resource)
        let message = CIMessageBuilder.peSubscribeInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: device.muid,
            requestID: requestID,
            headerData: headerData
        )

        return (requestID: requestID, message: message)
    }

    /// Begin an Unsubscribe request
    /// - Parameters:
    ///   - subscribeId: Subscription ID to unsubscribe
    ///   - timeout: Timeout duration
    /// - Returns: Request ID, message bytes, and destination
    /// - Throws: PEError if request cannot be initiated
    func beginUnsubscribe(
        subscribeId: String,
        timeout: Duration
    ) async throws -> (requestID: UInt8, message: [UInt8], destination: MIDIDestinationID) {
        guard let subscription = activeSubscriptions[subscribeId] else {
            throw PEError.invalidResponse("Unknown subscribeId: \(subscribeId)")
        }

        logger.debug("UNSUBSCRIBE \(subscription.resource) [\(subscribeId)]", category: "PESubscriptionHandler")

        guard let requestID = await transactionManager.begin(
            resource: subscription.resource,
            destinationMUID: subscription.device.muid,
            timeout: timeout.asTimeInterval
        ) else {
            throw PEError.requestIDExhausted
        }

        let headerData = CIMessageBuilder.subscribeEndHeader(
            resource: subscription.resource,
            subscribeId: subscribeId
        )
        let message = CIMessageBuilder.peSubscribeInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: subscription.device.muid,
            requestID: requestID,
            headerData: headerData
        )

        return (requestID: requestID, message: message, destination: subscription.device.destination)
    }

    /// Handle a Subscribe reply message
    /// - Parameter reply: Parsed Subscribe reply
    func handleSubscribeReply(_ reply: CIMessageParser.FullSubscribeReply) async {
        let requestID = reply.requestID

        // Cancel timeout and send tasks via callbacks
        cancelTimeout(requestID)
        cancelSend(requestID)

        // Release transaction
        await transactionManager.cancel(requestID: requestID)

        // Get pending continuation
        guard let continuation = pendingSubscribeContinuations.removeValue(forKey: requestID) else {
            logger.warning("No continuation for subscribe [\(requestID)]", category: "PESubscriptionHandler")
            return
        }

        // Build response
        let response = PESubscribeResponse(
            status: reply.status ?? 200,
            subscribeId: reply.subscribeId
        )

        logger.debug(
            "Subscribe reply [\(requestID)] status=\(response.status) id=\(response.subscribeId ?? "nil")",
            category: "PESubscriptionHandler"
        )

        continuation.resume(returning: response)
    }

    /// Handle a Notify message (single-chunk)
    /// - Parameter notify: Parsed Notify message
    func handleNotify(_ notify: CIMessageParser.FullNotify) async {
        await handleNotifyParts(
            sourceMUID: notify.sourceMUID,
            subscribeId: notify.subscribeId,
            resource: notify.resource,
            headerData: notify.headerData,
            propertyData: notify.propertyData
        )
    }

    /// Handle assembled Notify parts (multi-chunk complete)
    /// - Parameters:
    ///   - sourceMUID: Source device MUID
    ///   - subscribeId: Subscription ID
    ///   - resource: Resource name
    ///   - headerData: Header data
    ///   - propertyData: Property data
    func handleNotifyParts(
        sourceMUID: MUID,
        subscribeId: String?,
        resource: String?,
        headerData: Data,
        propertyData: Data
    ) async {
        guard let subscribeId = subscribeId else {
            logger.warning("Notify without subscribeId", category: "PESubscriptionHandler")
            return
        }

        guard let subscription = activeSubscriptions[subscribeId] else {
            logger.debug("Notify for unknown subscription: \(subscribeId)", category: "PESubscriptionHandler")
            return
        }

        // Parse header
        let parsedHeader: PEHeader?
        if !headerData.isEmpty {
            parsedHeader = try? JSONDecoder().decode(PEHeader.self, from: headerData)
        } else {
            parsedHeader = nil
        }

        // Decode property data if Mcoded7
        let decodedData: Data
        if parsedHeader?.isMcoded7 == true {
            decodedData = Mcoded7.decode(propertyData) ?? propertyData
        } else {
            decodedData = propertyData
        }

        // Build notification
        let notification = PENotification(
            resource: resource ?? subscription.resource,
            subscribeId: subscribeId,
            header: parsedHeader,
            data: decodedData,
            sourceMUID: sourceMUID
        )

        logger.debug(
            "Notify \(notification.resource) [\(subscribeId)] \(decodedData.count)B",
            category: "PESubscriptionHandler"
        )

        // Yield to stream
        notificationContinuation?.yield(notification)
    }

    /// Handle a Subscribe timeout
    /// - Parameter requestID: Request ID that timed out
    func handleTimeout(requestID: UInt8) async {
        // Cancel send task
        cancelSend(requestID)

        // Release transaction
        await transactionManager.cancel(requestID: requestID)

        // Get pending continuation and resume with timeout error
        guard let continuation = pendingSubscribeContinuations.removeValue(forKey: requestID) else {
            logger.debug("Timeout for unknown subscribe [\(requestID)]", category: "PESubscriptionHandler")
            return
        }

        logger.warning("Subscribe timeout [\(requestID)]", category: "PESubscriptionHandler")
        continuation.resume(throwing: PEError.timeout(resource: "subscribe"))
    }

    /// Cancel all pending Subscribe requests and clean up state
    /// Called during PEManager.stopReceiving()
    func cancelAll() async {
        // Resume all pending Subscribe continuations with cancellation
        for continuation in pendingSubscribeContinuations.values {
            continuation.resume(throwing: PEError.cancelled)
        }
        pendingSubscribeContinuations.removeAll()

        // Clear active subscriptions
        activeSubscriptions.removeAll()

        // Finish notification stream
        notificationContinuation?.finish()
        notificationContinuation = nil

        logger.debug("Subscription handler cancelled all pending requests", category: "PESubscriptionHandler")
    }

    /// Start a notification stream
    /// - Returns: AsyncStream of notifications
    func startNotificationStream() -> AsyncStream<PENotification> {
        // TODO: Phase 4 - Implement notification stream creation
        let oldContinuation = notificationContinuation
        notificationContinuation = nil
        oldContinuation?.finish()

        return AsyncStream { continuation in
            self.notificationContinuation = continuation
        }
    }

    /// Get all active subscriptions
    var subscriptions: [PESubscription] {
        get async {
            Array(activeSubscriptions.values)
        }
    }

    // MARK: - State Management (Phase 2)

    /// Add a pending continuation
    /// - Parameters:
    ///   - requestID: Request ID
    ///   - continuation: Continuation to store
    func addPendingContinuation(
        _ requestID: UInt8,
        _ continuation: CheckedContinuation<PESubscribeResponse, Error>
    ) {
        // TODO: Phase 2 - Implement state management
        pendingSubscribeContinuations[requestID] = continuation
    }

    /// Remove a pending continuation
    /// - Parameter requestID: Request ID
    /// - Returns: The continuation if found
    func removePendingContinuation(_ requestID: UInt8) -> CheckedContinuation<PESubscribeResponse, Error>? {
        // TODO: Phase 2 - Implement state management
        return pendingSubscribeContinuations.removeValue(forKey: requestID)
    }

    /// Add an active subscription
    /// - Parameters:
    ///   - subscribeId: Subscription ID
    ///   - subscription: Subscription to store
    func addActiveSubscription(_ subscribeId: String, _ subscription: PESubscription) {
        // TODO: Phase 2 - Implement state management
        activeSubscriptions[subscribeId] = subscription
    }

    /// Remove an active subscription
    /// - Parameter subscribeId: Subscription ID
    /// - Returns: The subscription if found
    func removeActiveSubscription(_ subscribeId: String) -> PESubscription? {
        // TODO: Phase 2 - Implement state management
        return activeSubscriptions.removeValue(forKey: subscribeId)
    }
}
