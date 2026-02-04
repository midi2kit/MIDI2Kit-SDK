//
//  PENAKTypes.swift
//  MIDI2Kit
//
//  Property Exchange NAK (Negative Acknowledge) Types
//

import Foundation
import MIDI2CI

// MARK: - NAK Status Code

/// MIDI-CI NAK (Negative Acknowledge) reason codes
///
/// These codes indicate why a MIDI-CI request was rejected.
public enum NAKStatusCode: UInt8, Sendable, CaseIterable, CustomStringConvertible {
    /// General CI rejection
    case ciNAK = 0x00

    /// Message type not supported
    case messageNotSupported = 0x01

    /// CI version mismatch
    case ciVersionMismatch = 0x02

    /// Reserved for future use
    case reserved = 0x03

    /// Unknown status code
    case unknown = 0xFF

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .ciNAK
        case 0x01: self = .messageNotSupported
        case 0x02: self = .ciVersionMismatch
        case 0x03: self = .reserved
        default: self = .unknown
        }
    }

    public var description: String {
        switch self {
        case .ciNAK: return "CI NAK"
        case .messageNotSupported: return "Message Not Supported"
        case .ciVersionMismatch: return "CI Version Mismatch"
        case .reserved: return "Reserved"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - NAK Detail Code

/// MIDI-CI NAK detail codes (status data interpretation)
public enum NAKDetailCode: UInt8, Sendable, CaseIterable, CustomStringConvertible {
    /// No additional information
    case none = 0x00

    /// Device is busy
    case busy = 0x01

    /// Resource not found
    case notFound = 0x02

    /// Permission denied
    case permissionDenied = 0x03

    /// Too many requests
    case tooManyRequests = 0x04

    /// Unknown detail code
    case unknown = 0xFF

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .none
        case 0x01: self = .busy
        case 0x02: self = .notFound
        case 0x03: self = .permissionDenied
        case 0x04: self = .tooManyRequests
        default: self = .unknown
        }
    }

    public var description: String {
        switch self {
        case .none: return "No additional info"
        case .busy: return "Device busy"
        case .notFound: return "Not found"
        case .permissionDenied: return "Permission denied"
        case .tooManyRequests: return "Too many requests"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - NAK Details

/// Detailed NAK (Negative Acknowledge) information
///
/// Contains parsed NAK response details from a MIDI-CI device.
public struct PENAKDetails: Sendable, CustomStringConvertible {
    /// Original message type that was rejected
    public let originalTransaction: UInt8

    /// NAK status code (reason category)
    public let statusCode: NAKStatusCode

    /// NAK detail code (specific reason)
    public let detailCode: NAKDetailCode

    /// Raw status code value
    public let rawStatusCode: UInt8

    /// Raw status data value
    public let rawStatusData: UInt8

    /// Additional NAK details (up to 5 bytes)
    public let additionalDetails: [UInt8]

    /// Human-readable error message from device
    public let message: String?

    public init(
        originalTransaction: UInt8,
        statusCode: UInt8,
        statusData: UInt8,
        additionalDetails: [UInt8] = [],
        message: String? = nil
    ) {
        self.originalTransaction = originalTransaction
        self.rawStatusCode = statusCode
        self.rawStatusData = statusData
        self.statusCode = NAKStatusCode(rawValue: statusCode)
        self.detailCode = NAKDetailCode(rawValue: statusData)
        self.additionalDetails = additionalDetails
        self.message = message
    }

    public var description: String {
        var parts: [String] = []
        parts.append("NAK: \(statusCode)")

        if detailCode != .none {
            parts.append("(\(detailCode))")
        }

        if let msg = message {
            parts.append("\"\(msg)\"")
        }

        return parts.joined(separator: " ")
    }

    /// Whether this NAK indicates a transient error (retry might succeed)
    public var isTransient: Bool {
        detailCode == .busy || detailCode == .tooManyRequests
    }

    /// Whether this NAK indicates a permanent error (retry won't help)
    public var isPermanent: Bool {
        statusCode == .messageNotSupported || detailCode == .notFound || detailCode == .permissionDenied
    }
}

// MARK: - PENAKDetails CIMessageParser Integration

extension PENAKDetails {
    /// Create from CIMessageParser.NAKPayload
    public init(from payload: CIMessageParser.NAKPayload) {
        self.init(
            originalTransaction: payload.originalTransaction,
            statusCode: payload.statusCode,
            statusData: payload.statusData,
            additionalDetails: payload.nakDetails,
            message: payload.messageText
        )
    }

    /// Create from CIMessageParser.FullNAK
    public init(from nak: CIMessageParser.FullNAK) {
        self.init(
            originalTransaction: nak.originalTransaction,
            statusCode: nak.statusCode,
            statusData: nak.statusData,
            additionalDetails: nak.nakDetails,
            message: nak.messageText
        )
    }
}
