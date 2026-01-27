//
//  DestinationStrategy.swift
//  MIDI2Kit
//
//  Strategy for resolving MUID to MIDI destination
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - DestinationStrategy

/// Strategy for resolving a device MUID to a MIDI destination
///
/// Many MIDI devices have multiple ports, and the correct destination
/// for Property Exchange may differ from where Discovery replies arrive.
///
/// ## KORG Example
///
/// KORG devices typically have this structure:
/// - Sources: "Bluetooth", "Session 1"
/// - Destinations: "Bluetooth", "Session 1", "Module"
///
/// Discovery replies come from "Bluetooth", but PE must go to "Module".
///
/// ## Strategy Selection
///
/// - `.preferModule`: Best for KORG and similar devices (default)
/// - `.preferNameMatch`: Best for simple devices with matching source/dest names
/// - `.automatic`: Tries to detect the best strategy automatically
/// - `.custom`: Provide your own resolution logic
public enum DestinationStrategy: Sendable {
    
    /// Automatically detect the best strategy
    ///
    /// Examines the available destinations and chooses based on patterns:
    /// - If "Module" destination exists → use preferModule behavior
    /// - Otherwise → use preferNameMatch behavior
    case automatic
    
    /// Prefer "Module" destination (for KORG and similar devices)
    ///
    /// Resolution order:
    /// 1. Destination containing "Module" in name
    /// 2. Entity-based matching (source → destination)
    /// 3. Name-based matching
    ///
    /// **Fallback**: On timeout, tries next candidate (max 1 retry)
    /// **Caching**: Successful destination is cached for MUID lifetime
    case preferModule
    
    /// Prefer name-based matching
    ///
    /// Resolution order:
    /// 1. Destination with exact same name as source
    /// 2. Entity-based matching
    /// 3. First available destination
    case preferNameMatch
    
    /// Custom resolution logic
    ///
    /// Provide your own function to resolve MUID to destination.
    ///
    /// - Parameter resolver: Function that takes MUID and available destinations,
    ///   returns the destination to use (or nil if none suitable)
    case custom(@Sendable (MUID, [MIDIDestinationInfo]) async -> MIDIDestinationID?)
}

// MARK: - Equatable (partial)

extension DestinationStrategy {
    /// Check if two strategies are the same type (ignores custom closure content)
    public func isSameType(as other: DestinationStrategy) -> Bool {
        switch (self, other) {
        case (.automatic, .automatic):
            return true
        case (.preferModule, .preferModule):
            return true
        case (.preferNameMatch, .preferNameMatch):
            return true
        case (.custom, .custom):
            return true
        default:
            return false
        }
    }
}

// MARK: - DestinationDiagnostics

/// Diagnostic information about destination resolution
///
/// Use this to debug destination resolution issues.
/// Available via `MIDI2Client.lastDestinationDiagnostics`.
public struct DestinationDiagnostics: Sendable {
    /// The MUID that was being resolved
    public let muid: MUID
    
    /// All destination candidates that were considered
    public let candidates: [MIDIDestinationInfo]
    
    /// Order in which destinations were tried
    public let triedOrder: [MIDIDestinationID]
    
    /// The last destination that was attempted
    public let lastAttempted: MIDIDestinationID?
    
    /// The successfully resolved destination (if any)
    public let resolvedDestination: MIDIDestinationID?
    
    /// Reason for failure (if resolution failed)
    public let failureReason: String?
    
    /// When this resolution occurred
    public let timestamp: Date
    
    /// Whether resolution was successful
    public var isSuccess: Bool {
        resolvedDestination != nil
    }
    
    public init(
        muid: MUID,
        candidates: [MIDIDestinationInfo],
        triedOrder: [MIDIDestinationID] = [],
        lastAttempted: MIDIDestinationID? = nil,
        resolvedDestination: MIDIDestinationID? = nil,
        failureReason: String? = nil,
        timestamp: Date = Date()
    ) {
        self.muid = muid
        self.candidates = candidates
        self.triedOrder = triedOrder
        self.lastAttempted = lastAttempted
        self.resolvedDestination = resolvedDestination
        self.failureReason = failureReason
        self.timestamp = timestamp
    }
}

// MARK: - CustomStringConvertible

extension DestinationDiagnostics: CustomStringConvertible {
    public var description: String {
        var lines: [String] = []
        lines.append("DestinationDiagnostics for \(muid):")
        lines.append("  Candidates: \(candidates.map { $0.name })")
        lines.append("  Tried: \(triedOrder)")
        if let last = lastAttempted {
            lines.append("  Last attempted: \(last)")
        }
        if let resolved = resolvedDestination {
            lines.append("  Resolved: \(resolved) ✓")
        } else if let reason = failureReason {
            lines.append("  Failed: \(reason)")
        }
        return lines.joined(separator: "\n")
    }
}
