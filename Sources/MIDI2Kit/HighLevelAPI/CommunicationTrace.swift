//
//  CommunicationTrace.swift
//  MIDI2Kit
//
//  Communication trace for debugging
//

import Foundation

// MARK: - CommunicationTrace

/// Trace information for the last communication
///
/// Provides detailed information about the most recent Property Exchange
/// operation for debugging purposes.
public struct CommunicationTrace: Sendable {

    // MARK: - Properties

    /// Timestamp of the communication
    public let timestamp: Date

    /// Type of operation
    public let operation: Operation

    /// Target MUID
    public let muid: MUID

    /// Resource identifier (if applicable)
    public let resource: String?

    /// Result of the operation
    public let result: Result

    /// Destination used
    public let destination: MIDIDestinationID?

    /// Duration of the operation
    public let duration: TimeInterval

    /// Error message (if failed)
    public let errorMessage: String?

    // MARK: - Nested Types

    /// Communication operation type
    public enum Operation: String, Sendable {
        case getDeviceInfo = "Get Device Info"
        case getResourceList = "Get Resource List"
        case getProperty = "Get Property"
        case setProperty = "Set Property"
    }

    /// Communication result
    public enum Result: String, Sendable {
        case success = "Success"
        case timeout = "Timeout"
        case error = "Error"
        case cancelled = "Cancelled"
    }

    // MARK: - Initialization

    public init(
        timestamp: Date = Date(),
        operation: Operation,
        muid: MUID,
        resource: String? = nil,
        result: Result,
        destination: MIDIDestinationID? = nil,
        duration: TimeInterval,
        errorMessage: String? = nil
    ) {
        self.timestamp = timestamp
        self.operation = operation
        self.muid = muid
        self.resource = resource
        self.result = result
        self.destination = destination
        self.duration = duration
        self.errorMessage = errorMessage
    }

    // MARK: - Description

    /// Human-readable description
    public var description: String {
        var lines: [String] = []

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        lines.append("=== Communication Trace ===")
        lines.append("Time: \(formatter.string(from: timestamp))")
        lines.append("Operation: \(operation.rawValue)")
        lines.append("MUID: 0x\(String(format: "%07X", muid.value))")

        if let resource = resource {
            lines.append("Resource: \(resource)")
        }

        if let destination = destination {
            lines.append("Destination: \(destination)")
        }

        lines.append("Duration: \(String(format: "%.3f", duration))s")
        lines.append("Result: \(result.rawValue)")

        if let error = errorMessage {
            lines.append("Error: \(error)")
        }

        return lines.joined(separator: "\n")
    }
}
