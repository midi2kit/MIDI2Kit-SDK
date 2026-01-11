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
    }
    
    public init(
        resource: String,
        name: String? = nil,
        schema: String? = nil,
        canGet: Bool = true,
        canSet: Bool = false,
        canSubscribe: Bool = false,
        requireResId: Bool = false,
        mediaType: String? = nil
    ) {
        self.resource = resource
        self.name = name
        self.schema = schema
        self.canGet = canGet
        self.canSet = canSet
        self.canSubscribe = canSubscribe
        self.requireResId = requireResId
        self.mediaType = mediaType
    }
}
