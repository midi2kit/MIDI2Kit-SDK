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
/// Key features:
/// - Enforces 7-bit constraint (0-127)
/// - Tracks in-use IDs to avoid collisions
/// - Automatic recycling with wrap-around
public struct PERequestIDManager: Sendable {
    
    /// Maximum Request ID value (7-bit)
    public static let maxRequestID: UInt8 = 127
    
    /// Next ID to try
    private var nextID: UInt8 = 0
    
    /// Currently in-use Request IDs
    private var inUseIDs: Set<UInt8> = []
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - ID Management
    
    /// Acquire next available Request ID
    /// - Returns: Available ID, or nil if all 128 IDs are in use
    public mutating func acquire() -> UInt8? {
        // Try up to 128 times to find an unused ID
        for _ in 0...Self.maxRequestID {
            let id = nextID
            nextID = (nextID + 1) & 0x7F  // Wrap at 128
            
            if !inUseIDs.contains(id) {
                inUseIDs.insert(id)
                return id
            }
        }
        
        // All IDs in use
        return nil
    }
    
    /// Release a Request ID for reuse
    /// - Parameter id: ID to release
    public mutating func release(_ id: UInt8) {
        inUseIDs.remove(id & 0x7F)
    }
    
    /// Release multiple Request IDs
    /// - Parameter ids: IDs to release
    public mutating func release(_ ids: [UInt8]) {
        for id in ids {
            release(id)
        }
    }
    
    /// Check if a Request ID is currently in use
    /// - Parameter id: ID to check
    /// - Returns: true if in use
    public func isInUse(_ id: UInt8) -> Bool {
        inUseIDs.contains(id & 0x7F)
    }
    
    /// Number of IDs currently in use
    public var usedCount: Int {
        inUseIDs.count
    }
    
    /// Number of available IDs
    public var availableCount: Int {
        Int(Self.maxRequestID) + 1 - inUseIDs.count
    }
    
    /// Release all IDs
    public mutating func releaseAll() {
        inUseIDs.removeAll()
    }
}
