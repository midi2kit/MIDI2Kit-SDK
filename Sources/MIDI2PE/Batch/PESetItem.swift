//
//  PESetItem.swift
//  MIDI2Kit
//
//  SET item for batch operations
//

import Foundation
import MIDI2Core

// MARK: - SET Item

/// An item in a batch SET operation
///
/// ## Usage
///
/// ```swift
/// // Create from raw data
/// let item = PESetItem(resource: "Volume", data: volumeData)
///
/// // Create from Encodable
/// let item = try PESetItem.json(resource: "Volume", value: VolumeInfo(level: 100))
///
/// // Create with channel
/// let item = try PESetItem.json(
///     resource: "ProgramName",
///     value: ["name": "Piano"],
///     channel: 0
/// )
/// ```
public struct PESetItem: Sendable, Hashable {
    /// Target resource name
    public let resource: String

    /// Payload data to SET
    public let data: Data

    /// Optional channel for channel-specific resources
    public let channel: Int?

    /// Create a SET item from raw data
    public init(resource: String, data: Data, channel: Int? = nil) {
        self.resource = resource
        self.data = data
        self.channel = channel
    }

    /// Create a SET item from an Encodable value
    ///
    /// - Parameters:
    ///   - resource: Resource name
    ///   - value: Encodable value to SET
    ///   - channel: Optional channel number
    /// - Throws: Encoding error if value cannot be serialized
    public static func json<T: Encodable & Sendable>(
        resource: String,
        value: T,
        channel: Int? = nil
    ) throws -> PESetItem {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        return PESetItem(resource: resource, data: data, channel: channel)
    }

    /// Create a SET item from a dictionary
    ///
    /// - Parameters:
    ///   - resource: Resource name
    ///   - dictionary: Dictionary to SET
    ///   - channel: Optional channel number
    /// - Throws: Serialization error
    public static func dictionary(
        resource: String,
        _ dictionary: [String: Any],
        channel: Int? = nil
    ) throws -> PESetItem {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return PESetItem(resource: resource, data: data, channel: channel)
    }
}

// MARK: - Batch SET Options

/// Options for batch SET operations
///
/// ## Presets
///
/// ```swift
/// // Default options
/// await peManager.batchSet(items, to: device, options: .default)
///
/// // Strict mode - stops on first failure
/// await peManager.batchSet(items, to: device, options: .strict)
///
/// // Fast parallel execution
/// await peManager.batchSet(items, to: device, options: .fast)
/// ```
public struct PEBatchSetOptions: Sendable {
    /// Maximum concurrent SET requests (default: 4)
    public var maxConcurrency: Int

    /// Stop immediately on first failure (default: false)
    public var stopOnFirstFailure: Bool

    /// Timeout per SET request (default: 5 seconds)
    public var timeout: Duration

    /// Validate payloads before sending (default: false)
    ///
    /// When true, payloads are validated using the PEManager's
    /// payloadValidatorRegistry before being sent.
    public var validatePayloads: Bool

    public init(
        maxConcurrency: Int = 4,
        stopOnFirstFailure: Bool = false,
        timeout: Duration = .seconds(5),
        validatePayloads: Bool = false
    ) {
        self.maxConcurrency = max(1, maxConcurrency)
        self.stopOnFirstFailure = stopOnFirstFailure
        self.timeout = timeout
        self.validatePayloads = validatePayloads
    }

    /// Default options
    public static let `default` = PEBatchSetOptions()

    /// Strict mode - stops on first failure, validates payloads
    public static let strict = PEBatchSetOptions(
        stopOnFirstFailure: true,
        validatePayloads: true
    )

    /// Fast parallel execution (more concurrent requests, shorter timeout)
    public static let fast = PEBatchSetOptions(
        maxConcurrency: 8,
        timeout: .seconds(3)
    )

    /// Serial execution (one at a time)
    public static let serial = PEBatchSetOptions(
        maxConcurrency: 1
    )
}

// MARK: - Batch SET Response

/// Response from a batch SET operation
public struct PEBatchSetResponse: Sendable {
    /// Results keyed by resource name
    public let results: [String: PEBatchResult]

    /// All successful responses
    public var successes: [String: PEResponse] {
        results.compactMapValues { $0.response }
    }

    /// All failures
    public var failures: [String: Error] {
        results.compactMapValues { $0.error }
    }

    /// Whether all requests succeeded
    public var allSucceeded: Bool {
        failures.isEmpty && !results.isEmpty
    }

    /// Number of successful requests
    public var successCount: Int {
        successes.count
    }

    /// Number of failed requests
    public var failureCount: Int {
        failures.count
    }

    /// Get result for a specific resource
    public subscript(resource: String) -> PEBatchResult? {
        results[resource]
    }

    /// Initialize with results
    public init(results: [String: PEBatchResult]) {
        self.results = results
    }
}
