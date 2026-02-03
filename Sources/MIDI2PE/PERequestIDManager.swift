//
//  PERequestIDManager.swift
//  MIDI2Kit
//
//  Manages 7-bit Request IDs for Property Exchange
//

import Foundation

/// Manages 7-bit Request IDs for Property Exchange transactions
///
/// MIDI-CI PE Request IDs are 7-bit values (0-127).
/// This manager ensures unique IDs and handles recycling.
///
/// ## Key features
/// - Enforces 7-bit constraint (0-127)
/// - Tracks in-use IDs to avoid collisions
/// - Automatic recycling with wrap-around
/// - **Cooldown period** to prevent stale response mismatch
///
/// ## Cooldown Feature
///
/// When a Request ID is released (after timeout or completion), it enters a
/// "cooldown" period before it can be reused. This prevents a scenario where:
///
/// 1. Request A uses ID 5, times out
/// 2. ID 5 is released and immediately reused for Request B
/// 3. Late response for Request A arrives and is incorrectly matched to B
///
/// With cooldown, ID 5 won't be reused until the cooldown period expires,
/// giving time for any stale responses to arrive and be discarded.
public struct PERequestIDManager: Sendable {

    /// Maximum Request ID value (7-bit)
    public static let maxRequestID: UInt8 = 127

    /// Default cooldown period in seconds
    ///
    /// This should be longer than typical network latency plus device processing time.
    /// 2 seconds is a reasonable default for most MIDI-CI devices.
    public static let defaultCooldownSeconds: TimeInterval = 2.0

    /// Cooldown period for released IDs
    public let cooldownPeriod: TimeInterval

    /// Next ID to try
    private var nextID: UInt8 = 0

    /// Currently in-use Request IDs
    private var inUseIDs: Set<UInt8> = []

    /// IDs in cooldown: maps ID to release time
    private var coolingIDs: [UInt8: Date] = [:]

    // MARK: - Initialization

    /// Initialize with optional cooldown period
    /// - Parameter cooldownPeriod: Seconds before a released ID can be reused (default: 2.0)
    public init(cooldownPeriod: TimeInterval = defaultCooldownSeconds) {
        self.cooldownPeriod = cooldownPeriod
    }

    // MARK: - ID Management

    /// Acquire next available Request ID
    /// - Parameter now: Current time (default: Date())
    /// - Returns: Available ID, or nil if all 128 IDs are in use or cooling
    public mutating func acquire(now: Date = Date()) -> UInt8? {
        // First, check for expired cooldowns and make them available
        expireCooldowns(now: now)

        // Try up to 128 times to find an unused ID
        for _ in 0...Self.maxRequestID {
            let id = nextID
            nextID = (nextID + 1) & 0x7F  // Wrap at 128

            // Skip if in use
            if inUseIDs.contains(id) {
                continue
            }

            // Skip if still cooling
            if coolingIDs[id] != nil {
                continue
            }

            inUseIDs.insert(id)
            return id
        }

        // All IDs in use or cooling
        return nil
    }

    /// Release a Request ID, starting its cooldown period
    /// - Parameters:
    ///   - id: ID to release
    ///   - now: Current time (default: Date())
    public mutating func release(_ id: UInt8, at now: Date = Date()) {
        let normalizedID = id & 0x7F
        guard inUseIDs.remove(normalizedID) != nil else {
            return // Was not in use
        }

        // Start cooldown
        if cooldownPeriod > 0 {
            coolingIDs[normalizedID] = now
        }
    }

    /// Release multiple Request IDs
    /// - Parameters:
    ///   - ids: IDs to release
    ///   - now: Current time (default: Date())
    public mutating func release(_ ids: [UInt8], at now: Date = Date()) {
        for id in ids {
            release(id, at: now)
        }
    }

    /// Expire cooldowns that have passed their period
    private mutating func expireCooldowns(now: Date) {
        coolingIDs = coolingIDs.filter { _, releaseTime in
            now.timeIntervalSince(releaseTime) < cooldownPeriod
        }
    }

    /// Check if a Request ID is currently in use
    /// - Parameter id: ID to check
    /// - Returns: true if in use
    public func isInUse(_ id: UInt8) -> Bool {
        inUseIDs.contains(id & 0x7F)
    }

    /// Check if a Request ID is in cooldown
    /// - Parameter id: ID to check
    /// - Returns: true if cooling
    public func isCooling(_ id: UInt8) -> Bool {
        coolingIDs[id & 0x7F] != nil
    }

    /// Number of IDs currently in use
    public var usedCount: Int {
        inUseIDs.count
    }

    /// Number of IDs currently in cooldown
    public var coolingCount: Int {
        coolingIDs.count
    }

    /// Number of truly available IDs (not in use and not cooling)
    public var availableCount: Int {
        Int(Self.maxRequestID) + 1 - inUseIDs.count - coolingIDs.count
    }

    /// Release all IDs immediately (skips cooldown)
    ///
    /// Use this for manager shutdown/reset scenarios.
    public mutating func releaseAll() {
        inUseIDs.removeAll()
        coolingIDs.removeAll()
    }

    /// Force release an ID from cooldown (for testing or emergency recovery)
    /// - Parameter id: ID to force release from cooldown
    public mutating func forceCooldownExpire(_ id: UInt8) {
        coolingIDs.removeValue(forKey: id & 0x7F)
    }

    /// Force expire all cooldowns (for testing or emergency recovery)
    public mutating func forceExpireAllCooldowns() {
        coolingIDs.removeAll()
    }
}
