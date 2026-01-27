//
//  MIDI2Device.swift
//  MIDI2Kit
//
//  High-level device wrapper for discovered MIDI-CI devices
//

import Foundation
import MIDI2Core
import MIDI2CI
import MIDI2PE

// MARK: - MIDI2Device

/// A discovered MIDI 2.0 device
///
/// `MIDI2Device` wraps a `DiscoveredDevice` with additional convenience methods
/// and caching for Property Exchange operations.
///
/// ## Example
///
/// ```swift
/// for await event in client.makeEventStream() {
///     if case .deviceDiscovered(let device) = event {
///         print("Found: \(device.displayName)")
///         print("Supports PE: \(device.supportsPropertyExchange)")
///         
///         if device.supportsPropertyExchange {
///             // DeviceInfo is automatically cached
///             if let info = await device.deviceInfo {
///                 print("Product: \(info.productName ?? "Unknown")")
///             }
///         }
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// MIDI2Device is designed to be `Sendable` and can be safely passed between
/// contexts. However, property access that requires network communication
/// (like `deviceInfo`) should be called from an async context.
public struct MIDI2Device: Sendable, Identifiable {
    
    // MARK: - Properties
    
    /// Unique identifier for this device instance
    public var id: MUID { muid }
    
    /// The device's MUID (may change on reconnection)
    public let muid: MUID
    
    /// Device identity (manufacturer, model, version)
    public let identity: DeviceIdentity
    
    /// Category support (profiles, PE, etc.)
    public let categorySupport: CategorySupport
    
    /// Maximum SysEx size supported
    public let maxSysExSize: UInt32
    
    /// Initiator output path ID
    public let initiatorOutputPath: UInt8
    
    /// Function block number
    public let functionBlock: UInt8
    
    /// Internal reference to the underlying DiscoveredDevice
    internal let discoveredDevice: DiscoveredDevice
    
    // MARK: - Initialization
    
    /// Create from a DiscoveredDevice
    public init(from device: DiscoveredDevice) {
        self.muid = device.muid
        self.identity = device.identity
        self.categorySupport = device.categorySupport
        self.maxSysExSize = device.maxSysExSize
        self.initiatorOutputPath = device.initiatorOutputPath
        self.functionBlock = device.functionBlock
        self.discoveredDevice = device
    }
    
    // MARK: - Computed Properties
    
    /// Display name for UI presentation
    public var displayName: String {
        discoveredDevice.displayName
    }
    
    /// Whether this device supports Property Exchange
    public var supportsPropertyExchange: Bool {
        categorySupport.contains(.propertyExchange)
    }
    
    /// Whether this device supports Profile Configuration
    public var supportsProfileConfiguration: Bool {
        categorySupport.contains(.profileConfiguration)
    }
    
    /// Whether this device supports Process Inquiry
    public var supportsProcessInquiry: Bool {
        categorySupport.contains(.processInquiry)
    }
    
    /// Manufacturer name (if known)
    public var manufacturerName: String? {
        identity.manufacturerID.name
    }
}

// MARK: - Equatable

extension MIDI2Device: Equatable {
    public static func == (lhs: MIDI2Device, rhs: MIDI2Device) -> Bool {
        lhs.muid == rhs.muid
    }
}

// MARK: - Hashable

extension MIDI2Device: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(muid)
    }
}

// MARK: - CustomStringConvertible

extension MIDI2Device: CustomStringConvertible {
    public var description: String {
        "\(displayName) [\(muid)]"
    }
}

// MARK: - CustomDebugStringConvertible

extension MIDI2Device: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        MIDI2Device(
            muid: \(muid),
            displayName: "\(displayName)",
            manufacturer: \(manufacturerName ?? "Unknown"),
            identity: \(identity),
            categorySupport: \(categorySupport),
            maxSysExSize: \(maxSysExSize)
        )
        """
    }
}
