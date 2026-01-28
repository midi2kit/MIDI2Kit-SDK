//
//  PESendStrategy.swift
//  MIDI2Kit
//
//  PE Send Strategy for controlling message routing
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - PESendStrategy

/// Strategy for sending Property Exchange requests
///
/// Controls how PE requests are routed to destinations. Different strategies
/// trade off between reliability (broadcast) and efficiency/safety (single).
///
/// ## Recommended Strategy
///
/// Use `.fallback` for best balance:
/// - Tries cached destination first (fastest)
/// - Falls back to resolved destination
/// - Only broadcasts as last resort
///
/// ## KORG Compatibility
///
/// KORG devices have asymmetric routing where Discovery responses come from
/// different ports than PE responses. The `.fallback` strategy handles this
/// by learning the correct destination after the first successful exchange.
public enum PESendStrategy: Sendable, Equatable {
    
    /// Send to single resolved destination only
    ///
    /// Most efficient but may fail with devices that have asymmetric routing.
    /// Use for well-behaved MIDI 2.0 devices.
    case single
    
    /// Broadcast to all destinations
    ///
    /// Most reliable but inefficient and may cause side effects when other
    /// MIDI applications (Logic Pro, etc.) are running.
    ///
    /// - Warning: Use only for debugging or when other strategies fail.
    case broadcast
    
    /// Fallback strategy (recommended)
    ///
    /// Tries destinations in order:
    /// 1. Cached destination (if previously successful)
    /// 2. Resolved destination from strategy
    /// 3. Broadcast (last resort)
    ///
    /// This strategy learns from successful responses and caches the working
    /// destination for future requests, minimizing broadcasts over time.
    case fallback
    
    /// Use only learned (cached) destinations
    ///
    /// Fails immediately if no cached destination exists.
    /// Useful for testing cache behavior.
    case learned
    
    /// Custom strategy with closure
    ///
    /// Allows full control over destination selection.
    /// The closure receives available destinations and returns which to use.
    case custom(@Sendable ([MIDIDestinationID]) async -> [MIDIDestinationID])
    
    // MARK: - Equatable (for non-custom cases)
    
    public static func == (lhs: PESendStrategy, rhs: PESendStrategy) -> Bool {
        switch (lhs, rhs) {
        case (.single, .single): return true
        case (.broadcast, .broadcast): return true
        case (.fallback, .fallback): return true
        case (.learned, .learned): return true
        case (.custom, .custom): return false // Custom closures can't be compared
        default: return false
        }
    }
}

// MARK: - PESendStrategy Description

extension PESendStrategy: CustomStringConvertible {
    public var description: String {
        switch self {
        case .single: return "single"
        case .broadcast: return "broadcast"
        case .fallback: return "fallback"
        case .learned: return "learned"
        case .custom: return "custom"
        }
    }
}

// MARK: - DestinationCache

/// Cache for successful PE destinations
///
/// Tracks which destination successfully responded to PE requests for each MUID.
/// Used by `.fallback` and `.learned` strategies to avoid unnecessary broadcasts.
///
/// ## Thread Safety
///
/// All operations are actor-isolated for thread safety.
///
/// ## TTL (Time To Live)
///
/// Entries expire after a configurable TTL to handle device reconnections
/// where the destination may have changed.
public actor DestinationCache {
    
    // MARK: - Entry
    
    /// Cache entry with metadata
    public struct Entry: Sendable {
        /// The cached destination ID
        public let destinationID: MIDIDestinationID
        
        /// When this entry was last successfully used
        public let lastSuccess: Date
        
        /// Number of successful responses from this destination
        public var successCount: Int
        
        public init(destinationID: MIDIDestinationID, lastSuccess: Date = Date(), successCount: Int = 1) {
            self.destinationID = destinationID
            self.lastSuccess = lastSuccess
            self.successCount = successCount
        }
    }
    
    // MARK: - Properties
    
    /// Cache storage: MUID → Entry
    private var cache: [MUID: Entry] = [:]
    
    /// Time-to-live for entries (default: 30 minutes)
    public let ttl: TimeInterval
    
    // MARK: - Initialization
    
    /// Initialize with TTL
    /// - Parameter ttl: Time-to-live for entries in seconds (default: 1800 = 30 minutes)
    public init(ttl: TimeInterval = 1800) {
        self.ttl = ttl
    }
    
    // MARK: - Public Methods
    
    /// Record a successful PE response
    ///
    /// - Parameters:
    ///   - muid: The device MUID
    ///   - destination: The destination that responded successfully
    public func recordSuccess(muid: MUID, destination: MIDIDestinationID) {
        if var existing = cache[muid], existing.destinationID == destination {
            // Update existing entry
            existing.successCount += 1
            cache[muid] = Entry(
                destinationID: destination,
                lastSuccess: Date(),
                successCount: existing.successCount
            )
        } else {
            // New entry (or different destination)
            cache[muid] = Entry(destinationID: destination)
        }
    }
    
    /// Get cached destination for a MUID
    ///
    /// Returns nil if:
    /// - No entry exists
    /// - Entry has expired (older than TTL)
    ///
    /// - Parameter muid: The device MUID
    /// - Returns: Cached destination if valid, nil otherwise
    public func getCachedDestination(for muid: MUID) -> MIDIDestinationID? {
        guard let entry = cache[muid] else { return nil }
        
        // Check TTL
        let age = Date().timeIntervalSince(entry.lastSuccess)
        if age > ttl {
            cache.removeValue(forKey: muid)
            return nil
        }
        
        return entry.destinationID
    }
    
    /// Invalidate cached destination for a MUID
    ///
    /// Call this when a request to the cached destination fails.
    ///
    /// - Parameter muid: The device MUID
    public func invalidate(muid: MUID) {
        cache.removeValue(forKey: muid)
    }
    
    /// Clear all cached destinations
    public func clearAll() {
        cache.removeAll()
    }
    
    /// Remove stale entries older than TTL
    ///
    /// Call periodically to clean up expired entries.
    public func pruneStale() {
        let now = Date()
        cache = cache.filter { _, entry in
            now.timeIntervalSince(entry.lastSuccess) <= ttl
        }
    }
    
    /// Get all cached entries (for diagnostics)
    public var allEntries: [MUID: Entry] {
        cache
    }
    
    /// Number of cached entries
    public var count: Int {
        cache.count
    }
    
    /// Get entry for a MUID (for diagnostics)
    public func getEntry(for muid: MUID) -> Entry? {
        cache[muid]
    }
}

// MARK: - DestinationCache Diagnostics

extension DestinationCache {
    /// Diagnostic string representation
    public var diagnostics: String {
        get async {
            var lines: [String] = []
            lines.append("=== DestinationCache ===")
            lines.append("TTL: \(Int(ttl))s")
            lines.append("Entries: \(cache.count)")
            
            for (muid, entry) in cache.sorted(by: { $0.key.value < $1.key.value }) {
                let age = Int(Date().timeIntervalSince(entry.lastSuccess))
                lines.append("  \(muid) → \(entry.destinationID) (success: \(entry.successCount), age: \(age)s)")
            }
            
            return lines.joined(separator: "\n")
        }
    }
}
