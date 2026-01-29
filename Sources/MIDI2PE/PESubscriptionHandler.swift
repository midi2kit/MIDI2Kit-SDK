//
//  PESubscriptionHandler.swift
//  MIDI2Kit
//
//  Handles Property Exchange Subscribe/Unsubscribe/Notify operations
//  Extracted from PEManager for better modularity (Phase 5-1)
//

import Foundation
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
    ///   - transactionManager: Transaction manager for Request ID allocation
    ///   - notifyAssemblyManager: Notify assembly manager for multi-chunk Notify
    ///   - logger: Logger for debugging
    ///   - scheduleTimeout: Callback to schedule timeout tasks
    ///   - cancelTimeout: Callback to cancel timeout tasks
    ///   - scheduleSend: Callback to schedule send tasks
    ///   - cancelSend: Callback to cancel send tasks
    init(
        transactionManager: PETransactionManager,
        notifyAssemblyManager: PENotifyAssemblyManager,
        logger: any MIDI2Logger,
        scheduleTimeout: @escaping @Sendable (UInt8, Duration, @escaping @Sendable () async -> Void) -> Void,
        cancelTimeout: @escaping @Sendable (UInt8) -> Void,
        scheduleSend: @escaping @Sendable (UInt8, [UInt8], MIDIDestinationID) -> Void,
        cancelSend: @escaping @Sendable (UInt8) -> Void
    ) {
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
        // TODO: Phase 3 - Implement Subscribe request initiation
        fatalError("Not yet implemented")
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
        // TODO: Phase 3 - Implement Unsubscribe request initiation
        fatalError("Not yet implemented")
    }

    /// Handle a Subscribe reply message
    /// - Parameter reply: Parsed Subscribe reply
    func handleSubscribeReply(_ reply: CIMessageParser.FullSubscribeReply) async {
        // TODO: Phase 5 - Implement Subscribe reply processing
    }

    /// Handle a Notify message (single-chunk)
    /// - Parameter notify: Parsed Notify message
    func handleNotify(_ notify: CIMessageParser.FullNotify) async {
        // TODO: Phase 4 - Implement single-chunk Notify handling
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
        // TODO: Phase 4 - Implement multi-chunk Notify processing
    }

    /// Handle a Subscribe timeout
    /// - Parameter requestID: Request ID that timed out
    func handleTimeout(requestID: UInt8) async {
        // TODO: Phase 5 - Implement timeout handling
    }

    /// Cancel all pending Subscribe requests and clean up state
    /// Called during PEManager.stopReceiving()
    func cancelAll() async {
        // TODO: Phase 2 - Implement cleanup
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
