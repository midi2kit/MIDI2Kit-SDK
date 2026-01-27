//
//  DestinationResolver.swift
//  MIDI2Kit
//
//  Resolves MUID to MIDI destination with strategy support and caching
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - DestinationResolver

/// Internal actor that resolves MUIDs to MIDI destinations
///
/// Features:
/// - Multiple resolution strategies
/// - Caching of successful resolutions
/// - Fallback with single retry on timeout
/// - Diagnostic information collection
internal actor DestinationResolver {
    
    // MARK: - Properties
    
    /// The resolution strategy to use
    private let strategy: DestinationStrategy
    
    /// Transport for accessing destinations
    private let transport: any MIDITransport
    
    /// Cache of resolved destinations (MUID → DestinationID)
    private var cache: [MUID: MIDIDestinationID] = [:]
    
    /// Last resolution diagnostics
    private var _lastDiagnostics: DestinationDiagnostics?
    
    // MARK: - Initialization
    
    init(strategy: DestinationStrategy, transport: any MIDITransport) {
        self.strategy = strategy
        self.transport = transport
    }
    
    // MARK: - Public Methods
    
    /// Resolve a MUID to a destination
    ///
    /// - Parameter muid: The device MUID
    /// - Parameter sourceID: Optional source ID from Discovery reply
    /// - Returns: The resolved destination, or nil if not found
    func resolve(muid: MUID, sourceID: MIDISourceID? = nil) async -> MIDIDestinationID? {
        // Check cache first
        if let cached = cache[muid] {
            return cached
        }
        
        let destinations = await transport.destinations
        var diagnostics = DestinationDiagnostics(
            muid: muid,
            candidates: destinations
        )
        
        var triedOrder: [MIDIDestinationID] = []
        var resolved: MIDIDestinationID?
        
        switch strategy {
        case .automatic:
            resolved = await resolveAutomatic(
                muid: muid,
                sourceID: sourceID,
                destinations: destinations,
                triedOrder: &triedOrder
            )
            
        case .preferModule:
            resolved = await resolvePreferModule(
                muid: muid,
                sourceID: sourceID,
                destinations: destinations,
                triedOrder: &triedOrder
            )
            
        case .preferNameMatch:
            resolved = await resolvePreferNameMatch(
                muid: muid,
                sourceID: sourceID,
                destinations: destinations,
                triedOrder: &triedOrder
            )
            
        case .custom(let resolver):
            resolved = await resolver(muid, destinations)
            if let r = resolved {
                triedOrder.append(r)
            }
        }
        
        // Update diagnostics
        diagnostics = DestinationDiagnostics(
            muid: muid,
            candidates: destinations,
            triedOrder: triedOrder,
            lastAttempted: triedOrder.last,
            resolvedDestination: resolved,
            failureReason: resolved == nil ? "No suitable destination found" : nil
        )
        _lastDiagnostics = diagnostics
        
        // Cache successful resolution
        if let resolved {
            cache[muid] = resolved
        }
        
        return resolved
    }
    
    /// Get candidates in priority order for a given MUID
    ///
    /// Used for fallback retry - returns next candidate after the failed one.
    func getNextCandidate(after destination: MIDIDestinationID, for muid: MUID) async -> MIDIDestinationID? {
        let destinations = await transport.destinations
        var candidates = buildCandidateOrder(destinations: destinations)
        
        // Find and remove the failed destination
        if let index = candidates.firstIndex(of: destination) {
            candidates.remove(at: index)
        }
        
        return candidates.first
    }
    
    /// Invalidate cached destination for a MUID
    func invalidate(muid: MUID) {
        cache.removeValue(forKey: muid)
    }
    
    /// Clear all cached destinations
    func clearCache() {
        cache.removeAll()
    }
    
    /// Get last resolution diagnostics
    var lastDiagnostics: DestinationDiagnostics? {
        _lastDiagnostics
    }
    
    /// Update cache with a known-good destination
    func cacheDestination(_ destination: MIDIDestinationID, for muid: MUID) {
        cache[muid] = destination
    }
    
    // MARK: - Strategy Implementations
    
    private func resolveAutomatic(
        muid: MUID,
        sourceID: MIDISourceID?,
        destinations: [MIDIDestinationInfo],
        triedOrder: inout [MIDIDestinationID]
    ) async -> MIDIDestinationID? {
        // Debug: log strategy selection
        print("[DestResolver] resolveAutomatic for \(muid)")
        print("[DestResolver]   Destinations count: \(destinations.count)")
        for dest in destinations {
            print("[DestResolver]   - '\(dest.name)'")
        }
        
        // Check if "Module" destination exists
        let hasModule = destinations.contains { $0.name.lowercased().contains("module") }
        print("[DestResolver]   hasModule: \(hasModule)")
        
        if hasModule {
            print("[DestResolver]   Using preferModule strategy")
            return await resolvePreferModule(
                muid: muid,
                sourceID: sourceID,
                destinations: destinations,
                triedOrder: &triedOrder
            )
        } else {
            return await resolvePreferNameMatch(
                muid: muid,
                sourceID: sourceID,
                destinations: destinations,
                triedOrder: &triedOrder
            )
        }
    }
    
    private func resolvePreferModule(
        muid: MUID,
        sourceID: MIDISourceID?,
        destinations: [MIDIDestinationInfo],
        triedOrder: inout [MIDIDestinationID]
    ) async -> MIDIDestinationID? {
        // Debug: log all destinations
        print("[DestResolver] resolvePreferModule for \(muid)")
        print("[DestResolver]   Available destinations:")
        for dest in destinations {
            print("[DestResolver]     - '\(dest.name)' -> \(dest.destinationID)")
        }
        
        // Priority 1: "Module" destination
        if let moduleDest = destinations.first(where: { $0.name.lowercased().contains("module") }) {
            print("[DestResolver]   Selected Module: '\(moduleDest.name)' -> \(moduleDest.destinationID)")
            triedOrder.append(moduleDest.destinationID)
            return moduleDest.destinationID
        }
        print("[DestResolver]   No Module port found!")
        
        // Priority 2: Entity-based matching
        if let sourceID,
           let matched = await transport.findMatchingDestination(for: sourceID) {
            triedOrder.append(matched)
            return matched
        }
        
        // Priority 3: Name-based matching
        if let sourceID {
            let sources = await transport.sources
            if let sourceInfo = sources.first(where: { $0.sourceID == sourceID }),
               let matchingDest = destinations.first(where: { $0.name == sourceInfo.name }) {
                triedOrder.append(matchingDest.destinationID)
                return matchingDest.destinationID
            }
        }
        
        return nil
    }
    
    private func resolvePreferNameMatch(
        muid: MUID,
        sourceID: MIDISourceID?,
        destinations: [MIDIDestinationInfo],
        triedOrder: inout [MIDIDestinationID]
    ) async -> MIDIDestinationID? {
        // Priority 1: Name-based matching
        if let sourceID {
            let sources = await transport.sources
            if let sourceInfo = sources.first(where: { $0.sourceID == sourceID }),
               let matchingDest = destinations.first(where: { $0.name == sourceInfo.name }) {
                triedOrder.append(matchingDest.destinationID)
                return matchingDest.destinationID
            }
        }
        
        // Priority 2: Entity-based matching
        if let sourceID,
           let matched = await transport.findMatchingDestination(for: sourceID) {
            triedOrder.append(matched)
            return matched
        }
        
        // Priority 3: First available (not recommended but provides fallback)
        if let first = destinations.first {
            triedOrder.append(first.destinationID)
            return first.destinationID
        }
        
        return nil
    }
    
    /// Build ordered list of candidate destinations based on strategy
    private func buildCandidateOrder(destinations: [MIDIDestinationInfo]) -> [MIDIDestinationID] {
        var candidates: [MIDIDestinationID] = []
        
        // Module destinations first (for preferModule strategy)
        for dest in destinations where dest.name.lowercased().contains("module") {
            candidates.append(dest.destinationID)
        }
        
        // Then others
        for dest in destinations where !dest.name.lowercased().contains("module") {
            candidates.append(dest.destinationID)
        }
        
        return candidates
    }
}
