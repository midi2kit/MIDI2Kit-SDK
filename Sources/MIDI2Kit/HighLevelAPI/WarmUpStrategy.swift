//
//  WarmUpStrategy.swift
//  MIDI2Kit
//
//  Adaptive warm-up strategies for Property Exchange
//
//  Some devices (especially over BLE) benefit from a "warm-up" request
//  before multi-chunk requests like ResourceList. This module provides
//  intelligent strategies to minimize unnecessary warm-ups while
//  maintaining reliability.
//

import Foundation
import MIDI2Core

// MARK: - WarmUpStrategy

/// Strategy for warming up connections before multi-chunk PE requests
///
/// BLE MIDI connections can be unreliable for the first request after
/// a period of inactivity. A "warm-up" request (typically DeviceInfo)
/// helps establish a stable connection before larger requests.
///
/// ## Strategies
///
/// - `.always`: Always warm up (most reliable, slowest)
/// - `.never`: Never warm up (fastest, may fail on some devices)
/// - `.adaptive`: Try without warm-up first, remember failures
/// - `.vendorBased`: Use vendor-specific optimizations
///
/// ## Example
///
/// ```swift
/// var config = MIDI2ClientConfiguration()
///
/// // Use adaptive strategy (recommended)
/// config.warmUpStrategy = .adaptive
///
/// // Always warm up for maximum reliability
/// config.warmUpStrategy = .always
///
/// // Use vendor-specific optimizations
/// config.warmUpStrategy = .vendorBased
/// ```
public enum WarmUpStrategy: Sendable, Equatable {
    /// Always perform warm-up before multi-chunk requests
    ///
    /// Most reliable but adds latency to every ResourceList request.
    /// Recommended for devices with known connectivity issues.
    case always

    /// Never perform warm-up
    ///
    /// Fastest but may fail on devices that need connection warm-up.
    /// Use only for devices known to work without warm-up.
    case never

    /// Adaptively decide based on past success/failure
    ///
    /// - First request: Try without warm-up
    /// - On failure: Retry with warm-up and remember the device needs it
    /// - Subsequent requests: Use the learned behavior
    ///
    /// This provides fast initial requests for devices that don't need
    /// warm-up while automatically adapting for those that do.
    case adaptive

    /// Use vendor-specific optimizations
    ///
    /// Consults `VendorOptimizationConfig` to determine warm-up behavior:
    /// - KORG with `useXParameterListAsWarmup`: Use X-ParameterList instead of DeviceInfo
    /// - KORG with `skipResourceListWhenPossible`: May skip warm-up entirely
    /// - Other vendors: Falls back to `.adaptive` behavior
    case vendorBased

    /// Convert legacy boolean to strategy
    public static func from(legacyWarmUp: Bool) -> WarmUpStrategy {
        legacyWarmUp ? .always : .never
    }

    /// Whether this strategy may require warm-up
    public var mayRequireWarmUp: Bool {
        switch self {
        case .never: return false
        case .always, .adaptive, .vendorBased: return true
        }
    }
}

// MARK: - WarmUpCache

/// Cache for tracking which devices need warm-up
///
/// Used by `.adaptive` strategy to remember devices that failed
/// without warm-up, avoiding repeated failures.
public actor WarmUpCache {
    /// Devices that need warm-up (failed without it)
    private var needsWarmUp: Set<String> = []

    /// Devices that succeeded without warm-up
    private var noWarmUpNeeded: Set<String> = []

    /// Maximum cache size
    private let maxCacheSize: Int

    /// Time-to-live for cache entries
    private let ttl: Duration

    /// Timestamps for cache entries
    private var timestamps: [String: Date] = [:]

    public init(maxCacheSize: Int = 100, ttl: Duration = .seconds(3600)) {
        self.maxCacheSize = maxCacheSize
        self.ttl = ttl
    }

    /// Check if a device needs warm-up
    ///
    /// - Parameter deviceKey: Unique key for the device (e.g., MUID or manufacturer+model)
    /// - Returns: `true` if device is known to need warm-up, `false` if unknown or doesn't need
    public func needsWarmUp(for deviceKey: String) -> Bool {
        cleanExpiredEntries()
        return needsWarmUp.contains(deviceKey)
    }

    /// Check if a device is known to work without warm-up
    ///
    /// - Parameter deviceKey: Unique key for the device
    /// - Returns: `true` if device is known to work without warm-up
    public func canSkipWarmUp(for deviceKey: String) -> Bool {
        cleanExpiredEntries()
        return noWarmUpNeeded.contains(deviceKey)
    }

    /// Record that a device needs warm-up (failed without it)
    ///
    /// - Parameter deviceKey: Unique key for the device
    public func recordNeedsWarmUp(_ deviceKey: String) {
        cleanExpiredEntries()
        ensureCacheSpace()

        noWarmUpNeeded.remove(deviceKey)
        needsWarmUp.insert(deviceKey)
        timestamps[deviceKey] = Date()
    }

    /// Record that a device succeeded without warm-up
    ///
    /// - Parameter deviceKey: Unique key for the device
    public func recordNoWarmUpNeeded(_ deviceKey: String) {
        cleanExpiredEntries()
        ensureCacheSpace()

        needsWarmUp.remove(deviceKey)
        noWarmUpNeeded.insert(deviceKey)
        timestamps[deviceKey] = Date()
    }

    /// Clear cache for a specific device
    ///
    /// - Parameter deviceKey: Unique key for the device
    public func clear(for deviceKey: String) {
        needsWarmUp.remove(deviceKey)
        noWarmUpNeeded.remove(deviceKey)
        timestamps.removeValue(forKey: deviceKey)
    }

    /// Clear all cached data
    public func clearAll() {
        needsWarmUp.removeAll()
        noWarmUpNeeded.removeAll()
        timestamps.removeAll()
    }

    /// Get cache status for diagnostics
    public var diagnostics: WarmUpCacheDiagnostics {
        WarmUpCacheDiagnostics(
            needsWarmUpCount: needsWarmUp.count,
            noWarmUpNeededCount: noWarmUpNeeded.count,
            totalEntries: timestamps.count
        )
    }

    // MARK: - Private

    private func cleanExpiredEntries() {
        let now = Date()
        let ttlSeconds = ttl.asTimeInterval

        let expiredKeys = timestamps.filter { now.timeIntervalSince($0.value) > ttlSeconds }.map(\.key)

        for key in expiredKeys {
            needsWarmUp.remove(key)
            noWarmUpNeeded.remove(key)
            timestamps.removeValue(forKey: key)
        }
    }

    private func ensureCacheSpace() {
        guard timestamps.count >= maxCacheSize else { return }

        // Remove oldest entries
        let sortedByAge = timestamps.sorted { $0.value < $1.value }
        let toRemove = sortedByAge.prefix(maxCacheSize / 4)

        for (key, _) in toRemove {
            needsWarmUp.remove(key)
            noWarmUpNeeded.remove(key)
            timestamps.removeValue(forKey: key)
        }
    }
}

// MARK: - WarmUpCacheDiagnostics

/// Diagnostic information about the warm-up cache
public struct WarmUpCacheDiagnostics: Sendable {
    /// Number of devices marked as needing warm-up
    public let needsWarmUpCount: Int

    /// Number of devices marked as not needing warm-up
    public let noWarmUpNeededCount: Int

    /// Total cache entries
    public let totalEntries: Int

    public var description: String {
        "WarmUpCache: \(needsWarmUpCount) need warm-up, \(noWarmUpNeededCount) don't, \(totalEntries) total"
    }
}

// MARK: - Device Key Generation

extension WarmUpCache {
    /// Generate a cache key from device identity
    ///
    /// Uses manufacturer + model for persistence across sessions
    /// (MUIDs change on device restart).
    public static func deviceKey(manufacturer: String?, model: String?) -> String {
        let mfr = manufacturer ?? "unknown"
        let mdl = model ?? "unknown"
        return "\(mfr):\(mdl)"
    }

    /// Generate a cache key from MUID
    ///
    /// Session-scoped key (won't persist across device restarts).
    public static func deviceKey(muid: MUID) -> String {
        "muid:\(muid)"
    }
}

// MARK: - Duration Extension (if not already defined)

#if !canImport(MIDI2PE)
extension Duration {
    var asTimeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1_000_000_000_000_000_000
    }
}
#endif
