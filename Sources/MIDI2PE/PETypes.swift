//
//  PETypes.swift
//  MIDI2Kit
//
//  Property Exchange Data Types
//

import Foundation
import MIDI2Core
import MIDI2CI
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

// MARK: - DeviceInfo

/// Device information from PE DeviceInfo resource
///
/// Supports both MIDI-CI 1.2 standard format and KORG proprietary format:
/// - Standard: `manufacturerName`, `productName`, `familyName`, `softwareVersion`
/// - KORG: `manufacturer`, `model`, `family`, `version`
public struct PEDeviceInfo: Sendable, Codable {
    
    /// Manufacturer name
    public let manufacturerName: String?
    
    /// Product/model name
    public let productName: String?
    
    /// Product instance ID (serial number, etc.)
    public let productInstanceID: String?
    
    /// Software/firmware version
    public let softwareVersion: String?
    
    /// Product family name
    public let familyName: String?
    
    /// Model name within family
    public let modelName: String?
    
    // CodingKeys for standard MIDI-CI format
    enum CodingKeys: String, CodingKey {
        case manufacturerName
        case productName
        case productInstanceID = "productInstanceId"
        case softwareVersion
        case familyName
        case modelName
        // KORG alternative keys
        case manufacturer
        case model
        case family
        case version
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try standard format first, fall back to KORG format
        manufacturerName = try container.decodeIfPresent(String.self, forKey: .manufacturerName)
            ?? container.decodeIfPresent(String.self, forKey: .manufacturer)
        
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
            ?? container.decodeIfPresent(String.self, forKey: .model)
        
        productInstanceID = try container.decodeIfPresent(String.self, forKey: .productInstanceID)
        
        softwareVersion = try container.decodeIfPresent(String.self, forKey: .softwareVersion)
            ?? container.decodeIfPresent(String.self, forKey: .version)
        
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName)
            ?? container.decodeIfPresent(String.self, forKey: .family)
        
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
    }
    
    public init(
        manufacturerName: String? = nil,
        productName: String? = nil,
        productInstanceID: String? = nil,
        softwareVersion: String? = nil,
        familyName: String? = nil,
        modelName: String? = nil
    ) {
        self.manufacturerName = manufacturerName
        self.productName = productName
        self.productInstanceID = productInstanceID
        self.softwareVersion = softwareVersion
        self.familyName = familyName
        self.modelName = modelName
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode using standard MIDI-CI format only
        try container.encodeIfPresent(manufacturerName, forKey: .manufacturerName)
        try container.encodeIfPresent(productName, forKey: .productName)
        try container.encodeIfPresent(productInstanceID, forKey: .productInstanceID)
        try container.encodeIfPresent(softwareVersion, forKey: .softwareVersion)
        try container.encodeIfPresent(familyName, forKey: .familyName)
        try container.encodeIfPresent(modelName, forKey: .modelName)
    }
    
    /// Display name (product name or manufacturer name)
    public var displayName: String {
        productName ?? manufacturerName ?? "Unknown Device"
    }
}

// MARK: - Controller Definition

/// Controller definition from ChCtrlList resource
public struct PEControllerDef: Sendable, Codable, Identifiable {
    public var id: Int { ctrlIndex }
    
    /// Controller index (CC number for standard CCs)
    public let ctrlIndex: Int
    
    /// Human-readable name
    public let name: String?
    
    /// Controller type
    public let ctrlType: String?
    
    /// Minimum value
    public let minValue: Int?
    
    /// Maximum value
    public let maxValue: Int?
    
    /// Default value
    public let defaultValue: Int?
    
    /// Step size
    public let stepCount: Int?
    
    /// Value labels
    public let valueList: [String]?
    
    /// Unit string (e.g., "dB", "Hz")
    public let units: String?
    
    enum CodingKeys: String, CodingKey {
        case ctrlIndex
        case name
        case ctrlType
        case minValue
        case maxValue
        case defaultValue = "default"
        case stepCount
        case valueList
        case units
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // ctrlIndex can be Int or String
        if let intValue = try? container.decode(Int.self, forKey: .ctrlIndex) {
            ctrlIndex = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .ctrlIndex),
                  let parsed = Int(stringValue) {
            ctrlIndex = parsed
        } else {
            ctrlIndex = 0
        }
        
        name = try container.decodeIfPresent(String.self, forKey: .name)
        ctrlType = try container.decodeIfPresent(String.self, forKey: .ctrlType)
        minValue = try container.decodeIfPresent(Int.self, forKey: .minValue)
        maxValue = try container.decodeIfPresent(Int.self, forKey: .maxValue)
        defaultValue = try container.decodeIfPresent(Int.self, forKey: .defaultValue)
        stepCount = try container.decodeIfPresent(Int.self, forKey: .stepCount)
        valueList = try container.decodeIfPresent([String].self, forKey: .valueList)
        units = try container.decodeIfPresent(String.self, forKey: .units)
    }
    
    public init(
        ctrlIndex: Int,
        name: String? = nil,
        ctrlType: String? = nil,
        minValue: Int? = nil,
        maxValue: Int? = nil,
        defaultValue: Int? = nil,
        stepCount: Int? = nil,
        valueList: [String]? = nil,
        units: String? = nil
    ) {
        self.ctrlIndex = ctrlIndex
        self.name = name
        self.ctrlType = ctrlType
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.stepCount = stepCount
        self.valueList = valueList
        self.units = units
    }
    
    /// Display name (name or "CC{index}")
    public var displayName: String {
        name ?? "CC\(ctrlIndex)"
    }
}

// MARK: - Program Definition

/// Program/preset definition from ProgramList resource
public struct PEProgramDef: Sendable, Codable, Identifiable {
    public var id: String { "\(bankMSB)-\(bankLSB)-\(programNumber)" }
    
    /// Program number (0-127)
    public let programNumber: Int
    
    /// Bank MSB (0-127)
    public let bankMSB: Int
    
    /// Bank LSB (0-127)
    public let bankLSB: Int
    
    /// Program name
    public let name: String?
    
    enum CodingKeys: String, CodingKey {
        case programNumber = "program"
        case bankMSB = "bankPC"
        case bankLSB = "bankCC"
        case name
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        programNumber = try container.decodeIfPresent(Int.self, forKey: .programNumber) ?? 0
        bankMSB = try container.decodeIfPresent(Int.self, forKey: .bankMSB) ?? 0
        bankLSB = try container.decodeIfPresent(Int.self, forKey: .bankLSB) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
    
    public init(
        programNumber: Int,
        bankMSB: Int = 0,
        bankLSB: Int = 0,
        name: String? = nil
    ) {
        self.programNumber = programNumber
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.name = name
    }
    
    /// Display name (name or program number)
    public var displayName: String {
        name ?? "Program \(programNumber)"
    }
}

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

// MARK: - NAK Details

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

// MARK: - Channel Info

/// Channel information from X-ChannelList resource
///
/// Represents a single MIDI channel's configuration and state.
public struct PEChannelInfo: Sendable, Codable, Identifiable {
    public var id: Int { channel }
    
    /// Channel number (0-15 for standard MIDI, 0-255 for MIDI 2.0)
    public let channel: Int
    
    /// Channel title/name
    public let title: String?
    
    /// Current program number (0-127)
    public let programNumber: Int?
    
    /// Current bank MSB (CC#0)
    public let bankMSB: Int?
    
    /// Current bank LSB (CC#32)
    public let bankLSB: Int?
    
    /// Current program name
    public let programTitle: String?
    
    /// Cluster type ("channel", "group", etc.)
    public let clusterType: String?
    
    /// Cluster index within group
    public let clusterIndex: Int?
    
    /// Number of channels in cluster
    public let clusterLength: Int?
    
    /// Whether channel is muted
    public let mute: Bool?
    
    /// Whether channel is solo'd
    public let solo: Bool?
    
    enum CodingKeys: String, CodingKey {
        case channel
        case title
        case programNumber = "program"
        case bankMSB = "bankPC"
        case bankLSB = "bankCC"
        case programTitle
        case clusterType
        case clusterIndex
        case clusterLength
        case mute
        case solo
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Channel can be Int or String
        if let intValue = try? container.decode(Int.self, forKey: .channel) {
            channel = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .channel),
                  let parsed = Int(stringValue) {
            channel = parsed
        } else {
            channel = 0
        }
        
        title = try container.decodeIfPresent(String.self, forKey: .title)
        programNumber = try container.decodeIfPresent(Int.self, forKey: .programNumber)
        bankMSB = try container.decodeIfPresent(Int.self, forKey: .bankMSB)
        bankLSB = try container.decodeIfPresent(Int.self, forKey: .bankLSB)
        programTitle = try container.decodeIfPresent(String.self, forKey: .programTitle)
        clusterType = try container.decodeIfPresent(String.self, forKey: .clusterType)
        clusterIndex = try container.decodeIfPresent(Int.self, forKey: .clusterIndex)
        clusterLength = try container.decodeIfPresent(Int.self, forKey: .clusterLength)
        mute = try container.decodeIfPresent(Bool.self, forKey: .mute)
        solo = try container.decodeIfPresent(Bool.self, forKey: .solo)
    }
    
    public init(
        channel: Int,
        title: String? = nil,
        programNumber: Int? = nil,
        bankMSB: Int? = nil,
        bankLSB: Int? = nil,
        programTitle: String? = nil,
        clusterType: String? = nil,
        clusterIndex: Int? = nil,
        clusterLength: Int? = nil,
        mute: Bool? = nil,
        solo: Bool? = nil
    ) {
        self.channel = channel
        self.title = title
        self.programNumber = programNumber
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.programTitle = programTitle
        self.clusterType = clusterType
        self.clusterIndex = clusterIndex
        self.clusterLength = clusterLength
        self.mute = mute
        self.solo = solo
    }
    
    /// Display name (title or "Ch {channel}")
    public var displayName: String {
        title ?? "Ch \(channel)"
    }
    
    /// Full program description ("Bank MSB-LSB Program: Name")
    public var programDescription: String? {
        guard let prog = programNumber else { return nil }
        
        var parts: [String] = []
        
        if let msb = bankMSB, let lsb = bankLSB {
            parts.append("\(msb)-\(lsb)")
        }
        
        parts.append("#\(prog)")
        
        if let name = programTitle {
            parts.append(name)
        }
        
        return parts.joined(separator: " ")
    }
}
