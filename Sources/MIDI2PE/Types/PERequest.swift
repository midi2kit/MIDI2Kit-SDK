//
//  PERequest.swift
//  MIDI2Kit
//
//  Property Exchange Request Types
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - Device Handle

/// A handle to a PE-capable device, bundling MUID with its transport destination.
///
/// This type prevents the common mistake of passing a MUID and destination
/// that don't correspond to the same device.
///
/// ## Usage
///
/// ```swift
/// // Create from discovered device and its source/destination
/// let handle = PEDeviceHandle(
///     muid: discoveredDevice.muid,
///     destination: destinationID
/// )
///
/// // Use with PEManager
/// let response = try await peManager.get("DeviceInfo", from: handle)
/// ```
public struct PEDeviceHandle: Sendable, Hashable, Identifiable {
    /// Unique identifier (uses MUID)
    public var id: MUID { muid }

    /// Device's MUID (from MIDI-CI Discovery)
    public let muid: MUID

    /// MIDI destination for sending messages to this device
    public let destination: MIDIDestinationID

    /// Optional device name for debugging
    public let name: String?

    public init(muid: MUID, destination: MIDIDestinationID, name: String? = nil) {
        self.muid = muid
        self.destination = destination
        self.name = name
    }

    /// Debug description
    public var debugDescription: String {
        if let name = name {
            return "\(name) (\(muid))"
        }
        return "Device \(muid)"
    }
}

// MARK: - PE Operation

/// Property Exchange operation type
public enum PEOperation: String, Sendable, CaseIterable {
    /// GET inquiry (read resource)
    case get = "GET"

    /// SET inquiry (write resource)
    case set = "SET"

    /// Subscribe to notifications
    case subscribe = "SUBSCRIBE"

    /// Unsubscribe from notifications
    case unsubscribe = "UNSUBSCRIBE"
}

// MARK: - PE Request

/// A Property Exchange request, encapsulating all parameters for GET/SET operations.
///
/// ## Design Rationale
///
/// This type centralizes request parameters to:
/// - Enable a single `send(request:)` method instead of multiple `get/set` variants
/// - Make request building testable and composable
/// - Provide a single place for validation logic
///
/// ## Usage
///
/// ```swift
/// // Simple GET
/// let request = PERequest.get("DeviceInfo", from: deviceHandle)
///
/// // GET with channel
/// let request = PERequest.get("ProgramName", channel: 0, from: deviceHandle)
///
/// // GET with pagination
/// let request = PERequest.get("ProgramList", offset: 0, limit: 10, from: deviceHandle)
///
/// // SET
/// let request = PERequest.set("ProgramName", data: nameData, to: deviceHandle)
/// ```
public struct PERequest: Sendable {
    /// Operation type
    public let operation: PEOperation

    /// Resource name (e.g., "DeviceInfo", "ProgramList")
    public let resource: String

    /// Target device
    public let device: PEDeviceHandle

    /// Request body data (for SET operations)
    public let body: Data?

    /// Channel number (for channel-specific resources)
    public let channel: Int?

    /// Pagination offset
    public let offset: Int?

    /// Pagination limit
    public let limit: Int?

    /// Request timeout
    public let timeout: Duration

    /// Default timeout for PE requests
    public static let defaultTimeout: Duration = .seconds(5)

    // MARK: - Initializers

    /// Full initializer
    public init(
        operation: PEOperation,
        resource: String,
        device: PEDeviceHandle,
        body: Data? = nil,
        channel: Int? = nil,
        offset: Int? = nil,
        limit: Int? = nil,
        timeout: Duration = defaultTimeout
    ) {
        self.operation = operation
        self.resource = resource
        self.device = device
        self.body = body
        self.channel = channel
        self.offset = offset
        self.limit = limit
        self.timeout = timeout
    }

    // MARK: - Factory Methods

    /// Create a GET request
    public static func get(
        _ resource: String,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        PERequest(operation: .get, resource: resource, device: device, timeout: timeout)
    }

    /// Create a GET request with channel
    public static func get(
        _ resource: String,
        channel: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        PERequest(operation: .get, resource: resource, device: device, channel: channel, timeout: timeout)
    }

    /// Create a paginated GET request
    public static func get(
        _ resource: String,
        offset: Int,
        limit: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        PERequest(operation: .get, resource: resource, device: device, offset: offset, limit: limit, timeout: timeout)
    }

    /// Create a SET request
    public static func set(
        _ resource: String,
        data: Data,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        PERequest(operation: .set, resource: resource, device: device, body: data, timeout: timeout)
    }

    /// Create a SET request with channel
    public static func set(
        _ resource: String,
        data: Data,
        channel: Int,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        PERequest(operation: .set, resource: resource, device: device, body: data, channel: channel, timeout: timeout)
    }

    // MARK: - Validation

    /// Validate request parameters
    public func validate() throws {
        if resource.isEmpty {
            throw PERequestError.emptyResource
        }

        if operation == .set && body == nil {
            throw PERequestError.missingBody
        }

        if let channel = channel, (channel < 0 || channel > 255) {
            throw PERequestError.invalidChannel(channel)
        }

        if let offset = offset, offset < 0 {
            throw PERequestError.invalidOffset(offset)
        }

        if let limit = limit, limit < 1 {
            throw PERequestError.invalidLimit(limit)
        }
    }
}

/// Request validation errors
public enum PERequestError: Error, Sendable, Equatable {
    case emptyResource
    case missingBody
    case invalidChannel(Int)
    case invalidOffset(Int)
    case invalidLimit(Int)
}
