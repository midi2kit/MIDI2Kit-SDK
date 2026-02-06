//
//  PEResponse.swift
//  MIDI2Kit
//
//  Property Exchange response type
//

import Foundation
import MIDI2Core

// MARK: - PE Status Codes

/// Property Exchange status codes (HTTP-style)
///
/// These codes are used in PE Reply headers to indicate the result of an inquiry.
/// They follow HTTP semantics with MIDI-specific extensions.
///
/// Reference: MIDI-CI Specification, Property Exchange Section
public enum PEStatusCode: Int, Sendable, CaseIterable {

    // MARK: - 2xx Success

    /// Request succeeded
    case ok = 200

    /// Request accepted for processing (async operations)
    case accepted = 202

    // MARK: - 3xx Notification

    /// Property change notification
    case notify = 341

    /// Subscription was accepted
    case subscriptionAccepted = 342

    /// Subscription was cancelled/ended
    case subscriptionCancelled = 343

    // MARK: - 4xx Client Error

    /// Malformed request or invalid parameters
    case badRequest = 400

    /// Authentication required
    case unauthorized = 401

    /// Access denied (even with authentication)
    case forbidden = 403

    /// Resource or property not found
    case notFound = 404

    /// Resource exists but cannot be modified
    case methodNotAllowed = 405

    /// Request acceptable but cannot be processed currently
    case notAcceptable = 406

    /// Request timeout
    case requestTimeout = 408

    /// Request cannot be processed in current state
    case conflict = 409

    /// Resource no longer available
    case gone = 410

    /// Request payload too large
    case payloadTooLarge = 413

    /// Unprocessable entity (semantic error)
    case unprocessableEntity = 422

    /// Too many requests (rate limiting)
    case tooManyRequests = 429

    /// Resource is busy/locked
    case resourceBusy = 463

    // MARK: - 5xx Device Error

    /// Internal device error
    case internalError = 500

    /// Feature not implemented
    case notImplemented = 501

    /// Invalid response from upstream
    case badGateway = 502

    /// Device temporarily unavailable
    case serviceUnavailable = 503

    /// Upstream timeout
    case gatewayTimeout = 504

    // MARK: - Properties

    /// Human-readable description
    public var description: String {
        switch self {
        case .ok: return "OK"
        case .accepted: return "Accepted"
        case .notify: return "Notify"
        case .subscriptionAccepted: return "Subscription Accepted"
        case .subscriptionCancelled: return "Subscription Cancelled"
        case .badRequest: return "Bad Request"
        case .unauthorized: return "Unauthorized"
        case .forbidden: return "Forbidden"
        case .notFound: return "Not Found"
        case .methodNotAllowed: return "Method Not Allowed"
        case .notAcceptable: return "Not Acceptable"
        case .requestTimeout: return "Request Timeout"
        case .conflict: return "Conflict"
        case .gone: return "Gone"
        case .payloadTooLarge: return "Payload Too Large"
        case .unprocessableEntity: return "Unprocessable Entity"
        case .tooManyRequests: return "Too Many Requests"
        case .resourceBusy: return "Resource Busy"
        case .internalError: return "Internal Error"
        case .notImplemented: return "Not Implemented"
        case .badGateway: return "Bad Gateway"
        case .serviceUnavailable: return "Service Unavailable"
        case .gatewayTimeout: return "Gateway Timeout"
        }
    }

    /// Whether this status indicates success
    public var isSuccess: Bool {
        (200..<300).contains(rawValue)
    }

    /// Whether this status indicates a notification
    public var isNotification: Bool {
        (300..<400).contains(rawValue)
    }

    /// Whether this status indicates a client error
    public var isClientError: Bool {
        (400..<500).contains(rawValue)
    }

    /// Whether this status indicates a device/server error
    public var isDeviceError: Bool {
        (500..<600).contains(rawValue)
    }

    /// Whether this status indicates an error (4xx or 5xx)
    public var isError: Bool {
        rawValue >= 400
    }

    /// Whether retrying the request might succeed
    public var isRetryable: Bool {
        switch self {
        case .requestTimeout, .tooManyRequests, .resourceBusy,
             .serviceUnavailable, .gatewayTimeout:
            return true
        default:
            return false
        }
    }

    /// Suggested retry delay for retryable errors
    public var suggestedRetryDelay: Duration? {
        switch self {
        case .tooManyRequests:
            return .seconds(5)
        case .resourceBusy:
            return .milliseconds(500)
        case .serviceUnavailable, .gatewayTimeout:
            return .seconds(2)
        case .requestTimeout:
            return .seconds(1)
        default:
            return nil
        }
    }
}

// MARK: - PE Response

/// Property Exchange response
public struct PEResponse: Sendable {
    /// HTTP-style status code
    public let status: Int

    /// Response header (parsed JSON)
    public let header: PEHeader?

    /// Response body (raw data, may be Mcoded7 encoded)
    public let body: Data

    /// Status code as typed enum (if recognized)
    public var statusCode: PEStatusCode? {
        PEStatusCode(rawValue: status)
    }

    /// Decoded body (Mcoded7 decoded if needed)
    ///
    /// Decoding logic:
    /// 1. If header indicates Mcoded7 encoding, decode it
    /// 2. If body starts with '{' or '[', assume it's already JSON
    /// 3. Otherwise, try Mcoded7 decode as fallback (for devices like KORG that don't set the header flag)
    public var decodedBody: Data {
        // If header explicitly indicates Mcoded7
        if header?.isMcoded7 == true {
            return Mcoded7.decode(body) ?? body
        }

        // If body looks like JSON already (starts with '{' or '['), return as-is
        if let firstByte = body.first, firstByte == 0x7B || firstByte == 0x5B {
            return body
        }

        // Fallback: try Mcoded7 decode for devices that don't set the header flag
        // (e.g., KORG devices send Mcoded7-encoded data without mutualEncoding header)
        if let decoded = Mcoded7.decode(body) {
            return decoded
        }

        return body
    }

    /// Body as UTF-8 string
    public var bodyString: String? {
        String(data: decodedBody, encoding: .utf8)
    }

    /// Is success response
    public var isSuccess: Bool {
        status >= 200 && status < 300
    }

    /// Is error response
    public var isError: Bool {
        status >= 400
    }

    public init(status: Int, header: PEHeader?, body: Data) {
        self.status = status
        self.header = header
        self.body = body
    }
}

// MARK: - Empty Response Representable

/// Protocol for types that have a meaningful "empty" representation.
///
/// Types conforming to this protocol can be returned when a PE response
/// body is empty (0 bytes), avoiding unnecessary errors for array-type resources.
///
/// ## Built-in Conformances
///
/// - `Array` where Element: Decodable — returns `[]`
///
/// ## Usage
///
/// ```swift
/// extension MyResourceList: PEEmptyResponseRepresentable {
///     static var emptyResponse: MyResourceList { MyResourceList(items: []) }
/// }
/// ```
public protocol PEEmptyResponseRepresentable {
    /// The value to return when the response body is empty
    static var emptyResponse: Self { get }
}

extension Array: PEEmptyResponseRepresentable where Element: Decodable {
    public static var emptyResponse: [Element] { [] }
}
