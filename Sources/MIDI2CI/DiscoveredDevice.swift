//
//  DiscoveredDevice.swift
//  MIDI2Kit
//
//  Represents a discovered MIDI-CI device
//

import Foundation
import MIDI2Core

/// A MIDI-CI device discovered via Discovery Inquiry
public struct DiscoveredDevice: Sendable, Identifiable, Hashable {
    
    /// Unique identifier (MUID)
    public var id: MUID { muid }
    
    /// Device's MUID
    public let muid: MUID
    
    /// Device identity information
    public let identity: DeviceIdentity
    
    /// Supported MIDI-CI categories
    public let categorySupport: CategorySupport
    
    /// Maximum SysEx message size (0 = unlimited)
    public let maxSysExSize: UInt32
    
    /// Initiator output path ID (CI 1.2+)
    public let initiatorOutputPath: UInt8
    
    /// Function block (CI 1.2+)
    public let functionBlock: UInt8
    
    // MARK: - Initialization
    
    public init(
        muid: MUID,
        identity: DeviceIdentity,
        categorySupport: CategorySupport,
        maxSysExSize: UInt32 = 0,
        initiatorOutputPath: UInt8 = 0,
        functionBlock: UInt8 = 0
    ) {
        self.muid = muid
        self.identity = identity
        self.categorySupport = categorySupport
        self.maxSysExSize = maxSysExSize
        self.initiatorOutputPath = initiatorOutputPath
        self.functionBlock = functionBlock
    }
    
    // MARK: - Convenience
    
    /// Check if device supports Property Exchange
    public var supportsPropertyExchange: Bool {
        categorySupport.contains(.propertyExchange)
    }
    
    /// Check if device supports Profile Configuration
    public var supportsProfileConfiguration: Bool {
        categorySupport.contains(.profileConfiguration)
    }
    
    /// Check if device supports Protocol Negotiation
    public var supportsProtocolNegotiation: Bool {
        categorySupport.contains(.protocolNegotiation)
    }
    
    /// Display name based on identity
    public var displayName: String {
        if let name = identity.manufacturerID.name {
            return "\(name) (\(identity.familyID):\(identity.modelID))"
        }
        return "Device \(muid)"
    }
}
