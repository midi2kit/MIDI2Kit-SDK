//
//  PEHeaderTypes.swift
//  MIDI2Kit
//
//  Property Exchange Header and Status Types
//

import Foundation

// MARK: - PE Status

/// Property Exchange status codes
public enum PEStatus: Int, Sendable, CaseIterable {
    /// Success
    case ok = 200

    /// Accepted (async processing)
    case accepted = 202

    /// Bad request
    case badRequest = 400

    /// Unauthorized
    case unauthorized = 401

    /// Resource not found
    case notFound = 404

    /// Too many simultaneous transactions
    case tooManyRequests = 429

    /// Internal device error
    case internalError = 500

    /// Not implemented
    case notImplemented = 501

    /// Is success status (2xx)
    public var isSuccess: Bool {
        rawValue >= 200 && rawValue < 300
    }

    /// Is error status (4xx or 5xx)
    public var isError: Bool {
        rawValue >= 400
    }
}

// MARK: - PE Header

/// Property Exchange header (JSON parsed)
public struct PEHeader: Sendable, Codable {
    /// Resource name
    public let resource: String?

    /// Resource ID (for channel-specific resources)
    public let resId: String?

    /// Status code
    public let status: Int?

    /// Message (for errors)
    public let message: String?

    /// Pagination offset
    public let offset: Int?

    /// Pagination limit
    public let limit: Int?

    /// Total count (for paginated responses)
    public let totalCount: Int?

    /// Media type ("ASCII" or "Mcoded7")
    public let mediaType: String?

    /// Mutual encoding
    public let mutualEncoding: String?

    /// Whether data is Mcoded7 encoded
    public var isMcoded7: Bool {
        mutualEncoding?.lowercased() == "mcoded7" ||
        mediaType?.lowercased() == "mcoded7"
    }
}
