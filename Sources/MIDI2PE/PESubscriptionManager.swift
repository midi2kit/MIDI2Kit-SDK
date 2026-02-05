//
//  PESubscriptionManager.swift
//  MIDI2Kit
//
//  Automatic subscription management with reconnection support
//

import Foundation
import MIDI2Core
import MIDI2CI
import MIDI2Transport

// MARK: - Subscription Intent

/// Represents the user's intent to subscribe to a resource
///
/// Unlike `PESubscription`, this tracks what the user *wants* to subscribe to,
/// regardless of whether the subscription is currently active.
public struct PESubscriptionIntent: Sendable, Identifiable {
    public let id: UUID
    
    /// Resource to subscribe to
    public let resource: String
    
    /// Device MUID (may change on reconnection)
    public let deviceMUID: MUID
    
    /// Device identity (for matching after MUID change)
    public let deviceIdentity: DeviceIdentity?
    
    /// Current subscription state
    public enum State: Sendable {
        /// Subscription is active
        case active(subscribeId: String, muid: MUID)
        
        /// Subscription pending (device not currently available)
        case pending
        
        /// Subscription failed
        case failed(String)
    }
    
    public init(
        id: UUID = UUID(),
        resource: String,
        deviceMUID: MUID,
        deviceIdentity: DeviceIdentity?
    ) {
        self.id = id
        self.resource = resource
        self.deviceMUID = deviceMUID
        self.deviceIdentity = deviceIdentity
    }
}

// MARK: - Subscription Event

/// Events from the subscription manager
public enum PESubscriptionEvent: Sendable {
    /// Subscription was established
    case subscribed(intentID: UUID, subscribeId: String)
    
    /// Subscription was lost (device disconnected)
    case suspended(intentID: UUID, reason: String)
    
    /// Subscription was restored after device reconnection
    case restored(intentID: UUID, newSubscribeId: String)
    
    /// Subscription failed
    case failed(intentID: UUID, reason: String)
    
    /// Received notification
    case notification(PENotification)
}

// MARK: - PESubscriptionManager

/// Manages PE subscriptions with automatic reconnection
///
/// This manager wraps `PEManager` and adds:
/// - Automatic re-subscription when devices reconnect
/// - Handling of InvalidateMUID events
/// - Persistent subscription intent tracking
/// - Unified notification stream that survives reconnections
///
/// ## Usage
///
/// ```swift
/// let subscriptionManager = PESubscriptionManager(
///     peManager: peManager,
///     ciManager: ciManager
/// )
/// await subscriptionManager.start()
///
/// // Subscribe - will auto-reconnect on device reconnection
/// try await subscriptionManager.subscribe(
///     to: "ProgramList",
///     on: device.muid,
///     identity: device.identity
/// )
///
/// // Handle events
/// for await event in subscriptionManager.events {
///     switch event {
///     case .notification(let notification):
///         print("Got: \(notification.resource)")
///     case .restored(let intentID, _):
///         print("Restored: \(intentID)")
///     case .suspended(let intentID, let reason):
///         print("Suspended: \(intentID) - \(reason)")
///     }
/// }
/// ```
public actor PESubscriptionManager {
    
    // MARK: - Configuration
    
    /// Delay before attempting re-subscription after device reconnects
    public var resubscribeDelay: Duration = .milliseconds(500)
    
    /// Maximum retry attempts for re-subscription
    public var maxRetryAttempts: Int = 3
    
    /// Log category
    private static let logCategory = "PESubscription"
    
    // MARK: - Dependencies
    
    private let peManager: PEManager
    private let ciManager: CIManager
    private let logger: any MIDI2Logger
    
    // MARK: - State
    
    /// Subscription intents by ID
    private var intents: [UUID: PESubscriptionIntent] = [:]
    
    /// Current state for each intent
    private var intentStates: [UUID: PESubscriptionIntent.State] = [:]
    
    /// Maps subscribeId -> intent ID for quick lookup
    private var subscribeIdToIntent: [String: UUID] = [:]
    
    /// Event stream continuation
    private var eventContinuation: AsyncStream<PESubscriptionEvent>.Continuation?
    
    /// Notification forwarding task
    private var notificationTask: Task<Void, Never>?
    
    /// CI event monitoring task
    private var ciEventTask: Task<Void, Never>?
    
    // MARK: - Public Streams
    
    /// Stream of subscription events
    public private(set) var events: AsyncStream<PESubscriptionEvent>!
    
    // MARK: - Initialization
    
    /// Initialize subscription manager
    /// - Parameters:
    ///   - peManager: PE manager for subscription operations
    ///   - ciManager: CI manager for device events
    ///   - logger: Optional logger
    public init(
        peManager: PEManager,
        ciManager: CIManager,
        logger: any MIDI2Logger = NullMIDI2Logger()
    ) {
        self.peManager = peManager
        self.ciManager = ciManager
        self.logger = logger

        // Use makeStream() to ensure continuation is available immediately
        // The old closure-based approach had a race condition where continuation
        // was nil until the stream was first iterated
        let (stream, continuation) = AsyncStream<PESubscriptionEvent>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
    }
    
    // MARK: - Lifecycle
    
    /// Start monitoring for device events and notifications
    public func start() async {
        // Start notification forwarding
        notificationTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = await peManager.startNotificationStream()
            
            for await notification in stream {
                await self.handleNotification(notification)
            }
        }
        
        // Start CI event monitoring
        ciEventTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await event in ciManager.events {
                await self.handleCIEvent(event)
            }
        }
        
        logger.info("Started subscription manager", category: Self.logCategory)
    }
    
    /// Stop monitoring and cancel all subscriptions
    public func stop() async {
        notificationTask?.cancel()
        notificationTask = nil
        
        ciEventTask?.cancel()
        ciEventTask = nil
        
        // Cancel all active subscriptions
        for (intentId, state) in intentStates {
            if case .active(let subscribeId, _) = state {
                do {
                    _ = try await peManager.unsubscribe(subscribeId: subscribeId)
                } catch {
                    // Ignore errors during shutdown
                }
                
                eventContinuation?.yield(.suspended(intentID: intentId, reason: "Manager stopped"))
            }
        }
        
        intents.removeAll()
        intentStates.removeAll()
        subscribeIdToIntent.removeAll()
        
        eventContinuation?.finish()
        
        logger.info("Stopped subscription manager", category: Self.logCategory)
    }
    
    // MARK: - Public API
    
    /// Subscribe to a resource with automatic reconnection
    ///
    /// - Parameters:
    ///   - resource: Resource name to subscribe to
    ///   - muid: Device MUID
    ///   - identity: Device identity for matching after reconnection (optional)
    /// - Returns: Intent ID for tracking
    /// - Throws: `PEError` if initial subscription fails
    @discardableResult
    public func subscribe(
        to resource: String,
        on muid: MUID,
        identity: DeviceIdentity? = nil
    ) async throws -> UUID {
        let intent = PESubscriptionIntent(
            resource: resource,
            deviceMUID: muid,
            deviceIdentity: identity
        )
        
        intents[intent.id] = intent
        intentStates[intent.id] = .pending
        
        logger.debug(
            "Creating subscription intent: \(resource) on \(muid)",
            category: Self.logCategory
        )
        
        // Try to subscribe immediately if device is available
        if let device = await findDevice(muid: muid, identity: identity) {
            do {
                _ = try await performSubscribe(intent: intent, device: device)
                return intent.id
            } catch {
                intentStates[intent.id] = .failed(error.localizedDescription)
                eventContinuation?.yield(.failed(intentID: intent.id, reason: error.localizedDescription))
                throw error
            }
        } else {
            // Device not available - will subscribe when it appears
            logger.info(
                "Device not available, subscription pending: \(resource)",
                category: Self.logCategory
            )
            return intent.id
        }
    }
    
    /// Remove a subscription intent
    ///
    /// - Parameter intentID: Intent ID returned from subscribe()
    public func unsubscribe(intentID: UUID) async throws {
        guard let intent = intents[intentID] else {
            return
        }
        
        // If active, unsubscribe from device
        if case .active(let subscribeId, _) = intentStates[intentID] {
            _ = try await peManager.unsubscribe(subscribeId: subscribeId)
            subscribeIdToIntent.removeValue(forKey: subscribeId)
        }
        
        intents.removeValue(forKey: intentID)
        intentStates.removeValue(forKey: intentID)
        
        logger.info("Removed subscription intent: \(intent.resource)", category: Self.logCategory)
    }
    
    /// Get all current subscription intents
    public var subscriptionIntents: [(intent: PESubscriptionIntent, state: PESubscriptionIntent.State)] {
        intents.compactMap { (id, intent) in
            guard let state = intentStates[id] else { return nil }
            return (intent, state)
        }
    }
    
    // MARK: - Private: Device Discovery
    
    /// Find a device by MUID or identity
    private func findDevice(muid: MUID, identity: DeviceIdentity?) async -> PEDeviceHandle? {
        // First try direct MUID lookup
        if let destination = await ciManager.destination(for: muid) {
            return PEDeviceHandle(muid: muid, destination: destination)
        }
        
        // Fall back to identity matching if provided
        if let identity = identity {
            let devices = await ciManager.discoveredDevices
            if let device = devices.first(where: { $0.identity == identity }) {
                if let destination = await ciManager.destination(for: device.muid) {
                    return PEDeviceHandle(muid: device.muid, destination: destination)
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Private: Subscription Operations
    
    /// Perform the actual subscription
    private func performSubscribe(intent: PESubscriptionIntent, device: PEDeviceHandle) async throws -> String {
        let response = try await peManager.subscribe(to: intent.resource, on: device)
        
        guard response.isSuccess, let subscribeId = response.subscribeId else {
            throw PEError.deviceError(status: response.status, message: "Subscribe failed")
        }
        
        // Update state
        intentStates[intent.id] = .active(subscribeId: subscribeId, muid: device.muid)
        subscribeIdToIntent[subscribeId] = intent.id
        
        logger.info(
            "Subscribed: \(intent.resource) -> \(subscribeId)",
            category: Self.logCategory
        )
        
        eventContinuation?.yield(.subscribed(intentID: intent.id, subscribeId: subscribeId))
        
        return subscribeId
    }
    
    /// Attempt to restore a subscription
    private func attemptResubscribe(intent: PESubscriptionIntent) async {
        logger.debug(
            "Attempting to restore subscription: \(intent.resource)",
            category: Self.logCategory
        )
        
        // Wait a bit for device to stabilize
        try? await Task.sleep(for: resubscribeDelay)
        
        guard let device = await findDevice(
            muid: intent.deviceMUID,
            identity: intent.deviceIdentity
        ) else {
            logger.debug(
                "Device still not available for: \(intent.resource)",
                category: Self.logCategory
            )
            return
        }
        
        var lastError: String = "Unknown error"
        
        for attempt in 1...maxRetryAttempts {
            do {
                let subscribeId = try await performSubscribe(intent: intent, device: device)
                eventContinuation?.yield(.restored(intentID: intent.id, newSubscribeId: subscribeId))
                return
            } catch {
                lastError = error.localizedDescription
                logger.warning(
                    "Resubscribe attempt \(attempt) failed: \(error)",
                    category: Self.logCategory
                )
                
                if attempt < maxRetryAttempts {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        
        intentStates[intent.id] = .failed(lastError)
        eventContinuation?.yield(.failed(intentID: intent.id, reason: lastError))
    }
    
    // MARK: - Private: Event Handling
    
    /// Handle notification from PEManager
    private func handleNotification(_ notification: PENotification) {
        // Forward to event stream
        eventContinuation?.yield(.notification(notification))
    }
    
    /// Handle CI event
    private func handleCIEvent(_ event: CIManagerEvent) async {
        switch event {
        case .deviceDiscovered(let device):
            await handleDeviceDiscovered(device)
            
        case .deviceLost(let muid):
            await handleDeviceLost(muid: muid)
            
        case .deviceUpdated:
            // Ignored for subscription purposes
            break
            
        case .discoveryStarted, .discoveryStopped:
            break
        }
    }
    
    /// Handle device discovered
    private func handleDeviceDiscovered(_ device: DiscoveredDevice) async {
        // Check if any pending intents match this device
        for (intentId, intent) in intents {
            guard case .pending = intentStates[intentId] else { continue }
            
            // Match by MUID or identity
            let matchesMUID = device.muid == intent.deviceMUID
            let matchesIdentity = intent.deviceIdentity != nil && device.identity == intent.deviceIdentity
            
            if matchesMUID || matchesIdentity {
                logger.info(
                    "Device reconnected, restoring subscription: \(intent.resource)",
                    category: Self.logCategory
                )
                
                await attemptResubscribe(intent: intent)
            }
        }
    }
    
    /// Handle device lost
    private func handleDeviceLost(muid: MUID) async {
        // Find intents associated with this MUID
        for (intentId, state) in intentStates {
            if case .active(let subscribeId, let activeMuid) = state, activeMuid == muid {
                guard let intent = intents[intentId] else { continue }
                
                // Mark as pending (will resubscribe when device returns)
                intentStates[intentId] = .pending
                subscribeIdToIntent.removeValue(forKey: subscribeId)
                
                logger.info(
                    "Device lost, subscription suspended: \(intent.resource)",
                    category: Self.logCategory
                )
                
                eventContinuation?.yield(.suspended(intentID: intentId, reason: "Device disconnected"))
            }
        }
    }
}
