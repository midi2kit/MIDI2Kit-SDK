//
//  PETypes.swift
//  MIDI2Kit
//
//  Property Exchange Data Types
//

import Foundation

// MARK: - DeviceInfo

/// Device information from PE DeviceInfo resource
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
    
    enum CodingKeys: String, CodingKey {
        case manufacturerName
        case productName
        case productInstanceID = "productInstanceId"
        case softwareVersion
        case familyName
        case modelName
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        manufacturerName = try container.decodeIfPresent(String.self, forKey: .manufacturerName)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        productInstanceID = try container.decodeIfPresent(String.self, forKey: .productInstanceID)
        softwareVersion = try container.decodeIfPresent(String.self, forKey: .softwareVersion)
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName)
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
