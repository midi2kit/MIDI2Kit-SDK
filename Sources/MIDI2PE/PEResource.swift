//
//  PEResource.swift
//  MIDI2Kit
//
//  Property Exchange Resource Definitions
//

import Foundation

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
    
    /// KORG X-ParameterList (CC name mappings)
    case xParameterList = "X-ParameterList"
    
    /// KORG X-CustomUI
    case xCustomUI = "X-CustomUI"
    
    // MARK: - Properties
    
    /// Resource name string
    public var name: String { rawValue }
}

/// Resource list entry from device
public struct PEResourceEntry: Sendable, Codable, Identifiable {
    public var id: String { resource }
    
    /// Resource name
    public let resource: String
    
    /// Human-readable name
    public let name: String?
    
    /// Schema reference
    public let schema: String?
    
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
        schema = try container.decodeIfPresent(String.self, forKey: .schema)
        canGet = try container.decodeIfPresent(Bool.self, forKey: .canGet) ?? true
        canSet = try container.decodeIfPresent(Bool.self, forKey: .canSet) ?? false
        canSubscribe = try container.decodeIfPresent(Bool.self, forKey: .canSubscribe) ?? false
        requireResId = try container.decodeIfPresent(Bool.self, forKey: .requireResId) ?? false
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        mediaTypes = try container.decodeIfPresent([String].self, forKey: .mediaTypes)
        columns = try container.decodeIfPresent([[String: String]].self, forKey: .columns)
    }
    
    public init(
        resource: String,
        name: String? = nil,
        schema: String? = nil,
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
