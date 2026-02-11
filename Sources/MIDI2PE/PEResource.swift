//
//  PEResource.swift
//  MIDI2Kit
//
//  Property Exchange Resource Definitions
//

import Foundation
import MIDI2Core

/// Standard Property Exchange resource names
///
/// Use these constants with PEManager to avoid typos:
/// ```swift
/// let response = try await peManager.get(.deviceInfo, from: device)
/// ```
///
/// For custom/vendor-specific resources, use String directly:
/// ```swift
/// let response = try await peManager.get("X-MyVendorResource", from: device)
/// ```
public enum PEResource: String, Sendable, CaseIterable {
    
    // MARK: - Standard Resources (MIDI-CI 1.2)
    
    /// List of available resources on device
    case resourceList = "ResourceList"
    
    /// Device information (manufacturer, model, etc.)
    case deviceInfo = "DeviceInfo"
    
    /// List of available channels
    case channelList = "ChannelList"
    
    /// Controller definitions for a channel
    case channelControllerList = "ChCtrlList"
    
    /// Program/preset list for a channel
    case programList = "ProgramList"
    
    /// Current program selection
    case currentProgram = "CurrentProgram"
    
    /// Device state snapshot
    case state = "State"
    
    /// Local control on/off
    case localOn = "LocalOn"
    
    /// JSON schema for a resource
    case jsonSchema = "JSONSchema"
    
    // MARK: - Extended Resources (X- prefix)
    
    /// Extended channel list with additional info
    case xChannelList = "X-ChannelList"
    
    /// Extended program info
    case xProgramInfo = "X-ProgramInfo"

    /// Extended program list (vendor-specific)
    case xProgramList = "X-ProgramList"
    
    /// KORG X-ParameterList (CC name mappings)
    case xParameterList = "X-ParameterList"
    
    /// KORG X-CustomUI
    case xCustomUI = "X-CustomUI"
    
    // MARK: - Properties
    
    /// Resource name string
    public var name: String { rawValue }
}

// MARK: - Flexible Bool Decoding

/// Helper to decode booleans that may be encoded as strings
///
/// Some devices (e.g., KORG) return boolean values as strings ("true"/"false")
/// instead of JSON booleans.
private struct FlexibleBool: Decodable {
    let value: Bool
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try Bool first
        if let boolValue = try? container.decode(Bool.self) {
            self.value = boolValue
            return
        }
        
        // Try String ("true"/"false")
        if let stringValue = try? container.decode(String.self) {
            switch stringValue.lowercased() {
            case "true", "1", "yes":
                self.value = true
                return
            case "false", "0", "no":
                self.value = false
                return
            default:
                break
            }
        }
        
        // Try Int (1/0)
        if let intValue = try? container.decode(Int.self) {
            self.value = intValue != 0
            return
        }
        
        throw DecodingError.typeMismatch(
            Bool.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected Bool, String (\"true\"/\"false\"), or Int (1/0)"
            )
        )
    }
}

extension KeyedDecodingContainer {
    /// Decode a flexible boolean that may be Bool or String
    func decodeFlexibleBool(forKey key: Key, default defaultValue: Bool) throws -> Bool {
        if let flexBool = try? decode(FlexibleBool.self, forKey: key) {
            return flexBool.value
        }
        return defaultValue
    }
}

// MARK: - PE Schema

/// Schema definition for a PE resource
///
/// MIDI-CI standard defines schema as a string reference (URN),
/// but some devices (e.g., KORG) embed the full JSON Schema as an object.
///
/// ## Standard Format (String)
/// ```json
/// {"schema": "urn:midi2:pe:schema:DeviceInfo"}
/// ```
///
/// ## KORG Format (Embedded Object)
/// ```json
/// {"schema": {"type": "object", "properties": {...}}}
/// ```
public enum PESchema: Sendable, Equatable {
    /// Schema reference URI (MIDI-CI standard)
    case reference(String)
    
    /// Embedded JSON Schema object (vendor extension)
    case embedded(PESchemaObject)
    
    /// Get the reference string if this is a reference type
    public var referenceString: String? {
        if case .reference(let str) = self {
            return str
        }
        return nil
    }
    
    /// Get the embedded schema if this is an embedded type
    public var embeddedSchema: PESchemaObject? {
        if case .embedded(let obj) = self {
            return obj
        }
        return nil
    }
}

extension PESchema: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try String first (MIDI-CI standard)
        if let str = try? container.decode(String.self) {
            self = .reference(str)
            return
        }
        
        // Try embedded object (KORG style)
        if let obj = try? container.decode(PESchemaObject.self) {
            self = .embedded(obj)
            return
        }
        
        throw DecodingError.typeMismatch(
            PESchema.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected String or Object for schema"
            )
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .reference(let str):
            try container.encode(str)
        case .embedded(let obj):
            try container.encode(obj)
        }
    }
}

/// Embedded JSON Schema object
///
/// Represents a JSON Schema definition embedded directly in the ResourceList.
/// This is used by some devices (e.g., KORG) instead of a reference URI.
public struct PESchemaObject: Sendable, Codable, Equatable {
    /// JSON Schema type (e.g., "object", "array", "string")
    public let type: String?
    
    /// Properties for object type
    public let properties: [String: PESchemaProperty]?
    
    /// Items schema for array type
    public let items: PESchemaProperty?
    
    /// Required property names
    public let required: [String]?
    
    /// Title/description
    public let title: String?
    public let description: String?
    
    public init(
        type: String? = nil,
        properties: [String: PESchemaProperty]? = nil,
        items: PESchemaProperty? = nil,
        required: [String]? = nil,
        title: String? = nil,
        description: String? = nil
    ) {
        self.type = type
        self.properties = properties
        self.items = items
        self.required = required
        self.title = title
        self.description = description
    }
}

/// JSON Schema property definition
public struct PESchemaProperty: Sendable, Codable, Equatable {
    public let type: String?
    public let title: String?
    public let description: String?
    public let minimum: Double?
    public let maximum: Double?
    public let defaultValue: AnyCodableValue?
    
    enum CodingKeys: String, CodingKey {
        case type, title, description, minimum, maximum
        case defaultValue = "default"
    }
    
    public init(
        type: String? = nil,
        title: String? = nil,
        description: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        defaultValue: AnyCodableValue? = nil
    ) {
        self.type = type
        self.title = title
        self.description = description
        self.minimum = minimum
        self.maximum = maximum
        self.defaultValue = defaultValue
    }
}

// AnyCodableValue is provided by MIDI2Core

// MARK: - PE Resource Entry

/// Resource list entry from device
public struct PEResourceEntry: Sendable, Codable, Identifiable {
    public var id: String { resource }
    
    /// Resource name
    public let resource: String
    
    /// Human-readable name
    public let name: String?
    
    /// Schema reference or embedded schema
    ///
    /// MIDI-CI standard uses a string reference (URN), but some devices
    /// like KORG embed the full JSON Schema object directly.
    public let schema: PESchema?
    
    /// Whether resource can be read
    public let canGet: Bool
    
    /// Whether resource can be written
    public let canSet: Bool
    
    /// Whether resource supports subscription
    public let canSubscribe: Bool
    
    /// Whether resource requires resId parameter
    public let requireResId: Bool
    
    /// Encoding type ("ASCII" or "Mcoded7")
    public let mediaType: String?
    
    /// Supported media types (array format)
    public let mediaTypes: [String]?
    
    /// Column definitions for tabular resources
    public let columns: [[String: String]]?
    
    // MARK: - Convenience
    
    /// Get schema as string reference (for standard-compliant devices)
    public var schemaReference: String? {
        schema?.referenceString
    }
    
    /// Get embedded schema object (for KORG-style devices)
    public var embeddedSchema: PESchemaObject? {
        schema?.embeddedSchema
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case resource
        case name
        case schema
        case canGet
        case canSet
        case canSubscribe
        case requireResId
        case mediaType
        case mediaTypes
        case columns
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        resource = try container.decode(String.self, forKey: .resource)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        schema = try container.decodeIfPresent(PESchema.self, forKey: .schema)
        
        // Use flexible bool decoding for capability flags
        // Some devices (e.g., KORG) return these as strings ("true"/"false")
        canGet = try container.decodeFlexibleBool(forKey: .canGet, default: true)
        canSet = try container.decodeFlexibleBool(forKey: .canSet, default: false)
        canSubscribe = try container.decodeFlexibleBool(forKey: .canSubscribe, default: false)
        requireResId = try container.decodeFlexibleBool(forKey: .requireResId, default: false)
        
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        mediaTypes = try container.decodeIfPresent([String].self, forKey: .mediaTypes)
        columns = try container.decodeIfPresent([[String: String]].self, forKey: .columns)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(resource, forKey: .resource)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(schema, forKey: .schema)
        try container.encode(canGet, forKey: .canGet)
        try container.encode(canSet, forKey: .canSet)
        try container.encode(canSubscribe, forKey: .canSubscribe)
        try container.encode(requireResId, forKey: .requireResId)
        try container.encodeIfPresent(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(mediaTypes, forKey: .mediaTypes)
        try container.encodeIfPresent(columns, forKey: .columns)
    }
    
    public init(
        resource: String,
        name: String? = nil,
        schema: PESchema? = nil,
        canGet: Bool = true,
        canSet: Bool = false,
        canSubscribe: Bool = false,
        requireResId: Bool = false,
        mediaType: String? = nil,
        mediaTypes: [String]? = nil,
        columns: [[String: String]]? = nil
    ) {
        self.resource = resource
        self.name = name
        self.schema = schema
        self.canGet = canGet
        self.canSet = canSet
        self.canSubscribe = canSubscribe
        self.requireResId = requireResId
        self.mediaType = mediaType
        self.mediaTypes = mediaTypes
        self.columns = columns
    }
    
    /// Convenience initializer with string schema (for backward compatibility)
    public init(
        resource: String,
        name: String? = nil,
        schemaReference: String?,
        canGet: Bool = true,
        canSet: Bool = false,
        canSubscribe: Bool = false,
        requireResId: Bool = false,
        mediaType: String? = nil,
        mediaTypes: [String]? = nil,
        columns: [[String: String]]? = nil
    ) {
        self.resource = resource
        self.name = name
        self.schema = schemaReference.map { .reference($0) }
        self.canGet = canGet
        self.canSet = canSet
        self.canSubscribe = canSubscribe
        self.requireResId = requireResId
        self.mediaType = mediaType
        self.mediaTypes = mediaTypes
        self.columns = columns
    }
}

// MARK: - KORG X-ParameterList

/// KORG proprietary X-ParameterList parameter definition
///
/// This represents a parameter from KORG's X-ParameterList resource,
/// which maps CC numbers to parameter names and default values.
///
/// ## JSON Format
/// ```json
/// {"name": "EQ High", "controlcc": 100, "default": 64}
/// ```
///
/// ## Usage
/// ```swift
/// let response = try await peManager.get(.xParameterList, from: device)
/// let parameters = try JSONDecoder().decode([XParameterDef].self, from: response.body)
///
/// // Build CC name lookup
/// let ccNames = parameters
///     .filter { $0.hasCCMapping }
///     .reduce(into: [Int: String]()) { $0[$1.controlCC] = $1.name }
/// ```
public struct XParameterDef: Sendable, Codable, Identifiable {
    public var id: String { name }
    
    /// Parameter display name
    public let name: String
    
    /// CC number (-1 if not assigned to CC)
    public let controlCC: Int
    
    /// Default value (0-127)
    public let defaultValue: Int
    
    /// Whether this parameter is mapped to a CC (0-127)
    public var hasCCMapping: Bool {
        controlCC >= 0 && controlCC <= 127
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case name
        case controlCC = "controlcc"
        case defaultValue = "default"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        controlCC = try container.decodeIfPresent(Int.self, forKey: .controlCC) ?? -1
        defaultValue = try container.decodeIfPresent(Int.self, forKey: .defaultValue) ?? 64
    }
    
    public init(name: String, controlCC: Int, defaultValue: Int = 64) {
        self.name = name
        self.controlCC = controlCC
        self.defaultValue = defaultValue
    }
}
