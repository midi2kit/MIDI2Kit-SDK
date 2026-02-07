//
//  PEResponderResource.swift
//  MIDI2Kit
//
//  Protocol and implementations for PE Responder resources
//

import Foundation
import MIDI2Core
import MIDI2CI

// MARK: - Request Header

/// Parsed PE request header (Sendable-safe version)
public struct PERequestHeader: Sendable {
    public let resource: String?
    public let resId: String?
    public let offset: Int?
    public let limit: Int?
    public let rawData: Data

    public init(data: Data) {
        self.rawData = data

        // Parse JSON
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.resource = json["resource"] as? String
            self.resId = json["resId"] as? String
            self.offset = json["offset"] as? Int
            self.limit = json["limit"] as? Int
        } else {
            self.resource = nil
            self.resId = nil
            self.offset = nil
            self.limit = nil
        }
    }

    public init(resource: String? = nil, resId: String? = nil, offset: Int? = nil, limit: Int? = nil) {
        self.resource = resource
        self.resId = resId
        self.offset = offset
        self.limit = limit
        self.rawData = Data()
    }
}

// MARK: - Resource Protocol

/// Protocol for Property Exchange resources
///
/// Implement this protocol to create custom resources that respond to PE GET/SET requests.
public protocol PEResponderResource: Sendable {

    /// Handle GET request for this resource
    ///
    /// - Parameters:
    ///   - header: Parsed request header (contains resId, offset, limit, etc.)
    /// - Returns: Response data (JSON encoded)
    func get(header: PERequestHeader) async throws -> Data

    /// Handle SET request for this resource
    ///
    /// - Parameters:
    ///   - header: Parsed request header
    ///   - body: Property data from SET request
    /// - Returns: Response data (may be empty for simple acknowledgement)
    func set(header: PERequestHeader, body: Data) async throws -> Data

    /// Whether this resource supports subscriptions
    var supportsSubscription: Bool { get }

    /// Build custom response header for GET reply
    ///
    /// Override to include additional fields like `totalCount` for paginated resources.
    /// Default implementation returns `{"status":200}`.
    func responseHeader(for header: PERequestHeader, bodyData: Data) -> Data
}

// MARK: - Default Implementation

extension PEResponderResource {
    public var supportsSubscription: Bool { false }

    public func set(header: PERequestHeader, body: Data) async throws -> Data {
        throw PEResponderError.readOnly
    }

    public func responseHeader(for header: PERequestHeader, bodyData: Data) -> Data {
        return CIMessageBuilder.successResponseHeader()
    }
}

// MARK: - Errors

/// Errors for PE Responder resources
public enum PEResponderError: Error, Sendable {
    case resourceNotFound(String)
    case readOnly
    case invalidData
    case invalidHeader
    case subscriptionNotSupported
}

// MARK: - In-Memory Resource

/// Simple in-memory resource implementation
///
/// Stores JSON data that can be read and written via PE GET/SET.
/// Useful for testing and simple simulations.
public actor InMemoryResource: PEResponderResource {

    private var data: Data
    private let readOnly: Bool

    /// Create an in-memory resource with initial data
    ///
    /// - Parameters:
    ///   - data: Initial JSON data
    ///   - readOnly: If true, SET requests will fail
    public init(data: Data, readOnly: Bool = false) {
        self.data = data
        self.readOnly = readOnly
    }

    /// Create an in-memory resource from a Codable value
    ///
    /// - Parameters:
    ///   - value: Value to encode as JSON
    ///   - readOnly: If true, SET requests will fail
    public init<T: Encodable>(value: T, readOnly: Bool = false) throws {
        let encoder = JSONEncoder()
        self.data = try encoder.encode(value)
        self.readOnly = readOnly
    }

    /// Create an in-memory resource from a JSON string
    ///
    /// - Parameters:
    ///   - json: JSON string
    ///   - readOnly: If true, SET requests will fail
    public init(json: String, readOnly: Bool = false) {
        self.data = Data(json.utf8)
        self.readOnly = readOnly
    }

    public func get(header: PERequestHeader) async throws -> Data {
        return data
    }

    public func set(header: PERequestHeader, body: Data) async throws -> Data {
        guard !readOnly else {
            throw PEResponderError.readOnly
        }
        self.data = body
        return Data()
    }

    public nonisolated var supportsSubscription: Bool { false }

    /// Update the stored data
    public func update(_ newData: Data) {
        self.data = newData
    }

    /// Update the stored data from a Codable value
    public func update<T: Encodable>(value: T) throws {
        let encoder = JSONEncoder()
        self.data = try encoder.encode(value)
    }
}

// MARK: - Static Resource

/// Static resource that returns fixed data
///
/// Always returns the same data for GET, ignores SET.
public struct StaticResource: PEResponderResource {

    private let data: Data

    /// Create a static resource
    ///
    /// - Parameter data: Fixed data to return for GET requests
    public init(data: Data) {
        self.data = data
    }

    /// Create a static resource from a JSON string
    public init(json: String) {
        self.data = Data(json.utf8)
    }

    /// Create a static resource from a Codable value
    public init<T: Encodable>(value: T) throws {
        let encoder = JSONEncoder()
        self.data = try encoder.encode(value)
    }

    public func get(header: PERequestHeader) async throws -> Data {
        return data
    }

    public var supportsSubscription: Bool { false }
}

// MARK: - Computed Resource

/// Resource with computed GET/SET handlers
///
/// Use when you need custom logic for GET/SET operations.
public struct ComputedResource: PEResponderResource {

    private let getHandler: @Sendable (PERequestHeader) async throws -> Data
    private let setHandler: (@Sendable (PERequestHeader, Data) async throws -> Data)?
    private let responseHeaderHandler: (@Sendable (PERequestHeader, Data) -> Data)?
    public let supportsSubscription: Bool

    /// Create a computed resource
    ///
    /// - Parameters:
    ///   - supportsSubscription: Whether subscriptions are supported
    ///   - get: Handler for GET requests
    ///   - set: Handler for SET requests (nil for read-only)
    ///   - responseHeader: Custom response header builder (nil for default `{"status":200}`)
    public init(
        supportsSubscription: Bool = false,
        get: @Sendable @escaping (PERequestHeader) async throws -> Data,
        set: (@Sendable (PERequestHeader, Data) async throws -> Data)? = nil,
        responseHeader: (@Sendable (PERequestHeader, Data) -> Data)? = nil
    ) {
        self.supportsSubscription = supportsSubscription
        self.getHandler = get
        self.setHandler = set
        self.responseHeaderHandler = responseHeader
    }

    public func get(header: PERequestHeader) async throws -> Data {
        return try await getHandler(header)
    }

    public func responseHeader(for header: PERequestHeader, bodyData: Data) -> Data {
        if let handler = responseHeaderHandler {
            return handler(header, bodyData)
        }
        return CIMessageBuilder.successResponseHeader()
    }

    public func set(header: PERequestHeader, body: Data) async throws -> Data {
        guard let handler = setHandler else {
            throw PEResponderError.readOnly
        }
        return try await handler(header, body)
    }
}

// MARK: - List Resource

/// Resource that manages a list of items
///
/// Supports pagination via offset/limit parameters.
public actor ListResource<T: Codable & Sendable>: PEResponderResource {

    private var items: [T]
    private let readOnly: Bool

    /// Create a list resource
    ///
    /// - Parameters:
    ///   - items: Initial items
    ///   - readOnly: If true, SET requests will fail
    public init(items: [T], readOnly: Bool = true) {
        self.items = items
        self.readOnly = readOnly
    }

    public func get(header: PERequestHeader) async throws -> Data {
        let offset = header.offset ?? 0
        let limit = header.limit ?? items.count

        let startIndex = max(0, min(offset, items.count))
        let endIndex = min(startIndex + limit, items.count)

        let slice = Array(items[startIndex..<endIndex])
        let encoder = JSONEncoder()
        return try encoder.encode(slice)
    }

    public func set(header: PERequestHeader, body: Data) async throws -> Data {
        guard !readOnly else {
            throw PEResponderError.readOnly
        }

        let decoder = JSONDecoder()
        let newItems = try decoder.decode([T].self, from: body)
        self.items = newItems
        return Data()
    }

    public nonisolated var supportsSubscription: Bool { false }

    /// Add an item to the list
    public func append(_ item: T) {
        items.append(item)
    }

    /// Remove all items
    public func removeAll() {
        items.removeAll()
    }

    /// Get current item count
    public var count: Int { items.count }
}
