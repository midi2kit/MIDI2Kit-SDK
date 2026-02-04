//
//  PEConditionalSet.swift
//  MIDI2Kit
//
//  Conditional SET operations for Property Exchange
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - Conditional SET

/// A builder for conditional SET operations
///
/// `PEConditionalSet` first fetches a resource, checks a condition,
/// and only performs the SET if the condition is met. This prevents
/// unnecessary updates and provides read-modify-write semantics.
///
/// ## Usage
///
/// ```swift
/// struct VolumeInfo: Codable {
///     var level: Int
/// }
///
/// // Only increase volume if it's below 50
/// let result = try await PEConditionalSet(
///     manager: peManager,
///     device: device,
///     resource: "Volume",
///     type: VolumeInfo.self
/// )
/// .setIf({ $0.level < 50 }) { _ in
///     VolumeInfo(level: 100)
/// }
///
/// switch result {
/// case .updated(let response):
///     print("Volume increased")
/// case .skipped(let currentValue):
///     print("Volume was already \(currentValue.level)")
/// case .failed(let error):
///     print("Operation failed: \(error)")
/// }
/// ```
public struct PEConditionalSet<T: Codable & Sendable>: Sendable {
    let manager: PEManager
    let device: PEDeviceHandle
    let resource: String
    let channel: Int?
    let timeout: Duration
    let type: T.Type

    /// Create a conditional SET operation
    ///
    /// - Parameters:
    ///   - manager: PEManager for PE operations
    ///   - device: Target device
    ///   - resource: Resource name
    ///   - type: Type to decode/encode
    ///   - channel: Optional channel number
    ///   - timeout: Operation timeout
    public init(
        manager: PEManager,
        device: PEDeviceHandle,
        resource: String,
        type: T.Type,
        channel: Int? = nil,
        timeout: Duration = .seconds(5)
    ) {
        self.manager = manager
        self.device = device
        self.resource = resource
        self.type = type
        self.channel = channel
        self.timeout = timeout
    }

    /// Set if condition is met
    ///
    /// - Parameters:
    ///   - condition: Condition to check against current value
    ///   - transform: Function to create new value from current value
    /// - Returns: Result of the conditional operation
    public func setIf(
        _ condition: @Sendable (T) -> Bool,
        transform: @Sendable (T) throws -> T
    ) async throws -> PEConditionalResult<T> {
        // Fetch current value
        let currentValue: T
        do {
            if let ch = channel {
                currentValue = try await manager.getJSON(resource, channel: ch, from: device, timeout: timeout)
            } else {
                currentValue = try await manager.getJSON(resource, from: device, timeout: timeout)
            }
        } catch {
            return .failed(error)
        }

        // Check condition
        guard condition(currentValue) else {
            return .skipped(currentValue)
        }

        // Transform and SET
        do {
            let newValue = try transform(currentValue)
            let data = try JSONEncoder().encode(newValue)

            let response: PEResponse
            if let ch = channel {
                response = try await manager.set(resource, data: data, channel: ch, to: device, timeout: timeout)
            } else {
                response = try await manager.set(resource, data: data, to: device, timeout: timeout)
            }

            return .updated(response, oldValue: currentValue, newValue: newValue)
        } catch {
            return .failed(error)
        }
    }

    /// Set to a fixed value if condition is met
    ///
    /// - Parameters:
    ///   - condition: Condition to check against current value
    ///   - newValue: Value to set if condition is met
    /// - Returns: Result of the conditional operation
    public func setIf(
        _ condition: @Sendable (T) -> Bool,
        to newValue: T
    ) async throws -> PEConditionalResult<T> {
        try await setIf(condition) { _ in newValue }
    }
}

// MARK: - Conditional Result

/// Result of a conditional SET operation
public enum PEConditionalResult<T: Sendable>: Sendable {
    /// SET was performed successfully
    case updated(PEResponse, oldValue: T, newValue: T)

    /// SET was skipped because condition was not met
    case skipped(T)

    /// Operation failed with an error
    case failed(Error)

    /// Whether the SET was performed
    public var wasUpdated: Bool {
        if case .updated = self { return true }
        return false
    }

    /// Whether the SET was skipped
    public var wasSkipped: Bool {
        if case .skipped = self { return true }
        return false
    }

    /// Whether the operation failed
    public var didFail: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Get the response if SET was performed
    public var response: PEResponse? {
        if case .updated(let response, _, _) = self { return response }
        return nil
    }

    /// Get the current/old value
    public var currentValue: T? {
        switch self {
        case .updated(_, let old, _): return old
        case .skipped(let value): return value
        case .failed: return nil
        }
    }

    /// Get the error if operation failed
    public var error: Error? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

// MARK: - PEManager Extension

extension PEManager {

    /// Create a conditional SET operation
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Only update if volume is below threshold
    /// let result = try await peManager.conditionalSet(
    ///     "Volume",
    ///     as: VolumeInfo.self,
    ///     on: device
    /// ).setIf({ $0.level < 50 }) { _ in
    ///     VolumeInfo(level: 100)
    /// }
    /// ```
    public func conditionalSet<T: Codable & Sendable>(
        _ resource: String,
        as type: T.Type,
        on device: PEDeviceHandle,
        channel: Int? = nil,
        timeout: Duration = .seconds(5)
    ) -> PEConditionalSet<T> {
        PEConditionalSet(
            manager: self,
            device: device,
            resource: resource,
            type: type,
            channel: channel,
            timeout: timeout
        )
    }

    /// Create a pipeline for the device
    ///
    /// ## Example
    ///
    /// ```swift
    /// let result = try await peManager.pipeline(for: device)
    ///     .get("ProgramName")
    ///     .transform { ... }
    ///     .set("ProgramName")
    ///     .execute()
    /// ```
    public func pipeline(
        for device: PEDeviceHandle,
        timeout: Duration = .seconds(5)
    ) -> PEPipeline<Void> {
        PEPipeline(manager: self, device: device, timeout: timeout)
    }
}
