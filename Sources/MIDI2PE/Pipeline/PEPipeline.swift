//
//  PEPipeline.swift
//  MIDI2Kit
//
//  GET → Transform → SET Pipeline for Property Exchange
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - Pipeline

/// A fluent builder for GET → Transform → SET operations
///
/// PEPipeline provides a declarative way to read a resource,
/// transform its value, and write it back to the device.
///
/// ## Usage
///
/// ```swift
/// // Simple transform and set
/// let result = try await PEPipeline(manager: peManager, device: device)
///     .get("ProgramName")
///     .transform { response in
///         // Modify the data
///         var json = try JSONSerialization.jsonObject(with: response.decodedBody) as! [String: Any]
///         json["name"] = "New Name"
///         return try JSONSerialization.data(withJSONObject: json)
///     }
///     .set("ProgramName")
///     .execute()
///
/// // Type-safe transform
/// struct ProgramName: Codable {
///     var name: String
/// }
///
/// let result = try await PEPipeline(manager: peManager, device: device)
///     .getJSON("ProgramName", as: ProgramName.self)
///     .map { $0.name.uppercased() }
///     .transform { ProgramName(name: $0) }
///     .setJSON("ProgramName")
///     .execute()
/// ```
public struct PEPipeline<T: Sendable>: Sendable {
    let manager: PEManager
    let device: PEDeviceHandle
    let timeout: Duration
    private let operation: @Sendable () async throws -> T

    /// Create a new pipeline
    ///
    /// - Parameters:
    ///   - manager: PEManager for PE operations
    ///   - device: Target device
    ///   - timeout: Default timeout for operations
    public init(
        manager: PEManager,
        device: PEDeviceHandle,
        timeout: Duration = .seconds(5)
    ) where T == Void {
        self.manager = manager
        self.device = device
        self.timeout = timeout
        self.operation = { }
    }

    /// Internal initializer with operation
    internal init(
        manager: PEManager,
        device: PEDeviceHandle,
        timeout: Duration,
        operation: @Sendable @escaping () async throws -> T
    ) {
        self.manager = manager
        self.device = device
        self.timeout = timeout
        self.operation = operation
    }
}

// MARK: - GET Operations

extension PEPipeline where T == Void {

    /// GET a resource
    ///
    /// - Parameters:
    ///   - resource: Resource name to fetch
    ///   - channel: Optional channel number
    /// - Returns: Pipeline with PEResponse
    public func get(
        _ resource: String,
        channel: Int? = nil
    ) -> PEPipeline<PEResponse> {
        PEPipeline<PEResponse>(
            manager: manager,
            device: device,
            timeout: timeout
        ) { [manager, device, timeout] in
            if let ch = channel {
                return try await manager.get(resource, channel: ch, from: device, timeout: timeout)
            } else {
                return try await manager.get(resource, from: device, timeout: timeout)
            }
        }
    }

    /// GET and decode a resource as JSON
    ///
    /// - Parameters:
    ///   - resource: Resource name to fetch
    ///   - type: Decodable type
    ///   - channel: Optional channel number
    /// - Returns: Pipeline with decoded value
    public func getJSON<U: Decodable & Sendable>(
        _ resource: String,
        as type: U.Type,
        channel: Int? = nil
    ) -> PEPipeline<U> {
        PEPipeline<U>(
            manager: manager,
            device: device,
            timeout: timeout
        ) { [manager, device, timeout] in
            if let ch = channel {
                return try await manager.getJSON(resource, channel: ch, from: device, timeout: timeout)
            } else {
                return try await manager.getJSON(resource, from: device, timeout: timeout)
            }
        }
    }
}

// MARK: - Transform Operations

extension PEPipeline {

    /// Transform the current value
    ///
    /// - Parameter transform: Transformation function
    /// - Returns: Pipeline with transformed value
    public func transform<U: Sendable>(
        _ transform: @Sendable @escaping (T) throws -> U
    ) -> PEPipeline<U> {
        PEPipeline<U>(
            manager: manager,
            device: device,
            timeout: timeout
        ) { [operation] in
            let value = try await operation()
            return try transform(value)
        }
    }

    /// Map the current value (alias for transform)
    public func map<U: Sendable>(
        _ transform: @Sendable @escaping (T) throws -> U
    ) -> PEPipeline<U> {
        self.transform(transform)
    }

    /// Async transform
    public func transformAsync<U: Sendable>(
        _ transform: @Sendable @escaping (T) async throws -> U
    ) -> PEPipeline<U> {
        PEPipeline<U>(
            manager: manager,
            device: device,
            timeout: timeout
        ) { [operation] in
            let value = try await operation()
            return try await transform(value)
        }
    }
}

// MARK: - SET Operations

extension PEPipeline where T == Data {

    /// SET the data to a resource
    ///
    /// - Parameters:
    ///   - resource: Resource name to set
    ///   - channel: Optional channel number
    /// - Returns: Pipeline with SET response
    public func set(
        _ resource: String,
        channel: Int? = nil
    ) -> PEPipeline<PEResponse> {
        PEPipeline<PEResponse>(
            manager: manager,
            device: device,
            timeout: timeout
        ) { [manager, device, timeout, operation] in
            let data = try await operation()
            if let ch = channel {
                return try await manager.set(resource, data: data, channel: ch, to: device, timeout: timeout)
            } else {
                return try await manager.set(resource, data: data, to: device, timeout: timeout)
            }
        }
    }
}

extension PEPipeline where T: Encodable & Sendable {

    /// SET the encodable value as JSON
    ///
    /// - Parameters:
    ///   - resource: Resource name to set
    ///   - channel: Optional channel number
    /// - Returns: Pipeline with SET response
    public func setJSON(
        _ resource: String,
        channel: Int? = nil
    ) -> PEPipeline<PEResponse> {
        PEPipeline<PEResponse>(
            manager: manager,
            device: device,
            timeout: timeout
        ) { [manager, device, timeout, operation] in
            let value = try await operation()
            let data = try JSONEncoder().encode(value)
            if let ch = channel {
                return try await manager.set(resource, data: data, channel: ch, to: device, timeout: timeout)
            } else {
                return try await manager.set(resource, data: data, to: device, timeout: timeout)
            }
        }
    }
}

// MARK: - PEResponse Extensions

extension PEPipeline where T == PEResponse {

    /// Transform response to Data
    public func toData() -> PEPipeline<Data> {
        transform { $0.decodedBody }
    }

    /// Decode response as JSON
    public func decode<U: Decodable & Sendable>(as type: U.Type) -> PEPipeline<U> {
        transform { response in
            try JSONDecoder().decode(type, from: response.decodedBody)
        }
    }
}

// MARK: - Execute

extension PEPipeline {

    /// Execute the pipeline and return the result
    public func execute() async throws -> T {
        try await operation()
    }

    /// Execute and discard the result
    @discardableResult
    public func run() async throws -> T {
        try await execute()
    }
}

// MARK: - Conditional Operations

extension PEPipeline {

    /// Continue only if the condition is met
    ///
    /// - Parameter condition: Condition to check
    /// - Returns: Pipeline that throws if condition is false
    public func `where`(
        _ condition: @Sendable @escaping (T) throws -> Bool
    ) -> PEPipeline<T> {
        transform { value in
            guard try condition(value) else {
                throw PEPipelineError.conditionNotMet
            }
            return value
        }
    }

    /// Execute only if condition is met, otherwise return default
    public func whereOr(
        _ condition: @Sendable @escaping (T) throws -> Bool,
        default defaultValue: T
    ) -> PEPipeline<T> {
        transform { value in
            if try condition(value) {
                return value
            }
            return defaultValue
        }
    }
}

// MARK: - Pipeline Errors

/// Errors that can occur during pipeline execution
public enum PEPipelineError: Error, Sendable {
    /// Condition in `where` clause was not met
    case conditionNotMet

    /// Transform operation failed
    case transformFailed(Error)
}

extension PEPipelineError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .conditionNotMet:
            return "Pipeline condition was not met"
        case .transformFailed(let error):
            return "Pipeline transform failed: \(error)"
        }
    }
}
