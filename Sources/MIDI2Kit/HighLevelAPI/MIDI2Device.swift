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
/// MIDI2Device is an actor that provides thread-safe access to device properties
/// and Property Exchange operations. All property access must be awaited.
public actor MIDI2Device: Identifiable {

    // MARK: - Properties

    /// Unique identifier for this device instance
    public nonisolated var id: MUID { muid }

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

    /// Reference to the MIDI2Client for Property Exchange operations
    private let client: MIDI2Client

    // MARK: - Cache

    /// Cached DeviceInfo
    private var cachedDeviceInfo: PEDeviceInfo?

    /// Cached ResourceList
    private var cachedResourceList: [PEResourceEntry]?

    // MARK: - Initialization

    /// Create from a DiscoveredDevice and MIDI2Client
    public init(from device: DiscoveredDevice, client: MIDI2Client) {
        self.muid = device.muid
        self.identity = device.identity
        self.categorySupport = device.categorySupport
        self.maxSysExSize = device.maxSysExSize
        self.initiatorOutputPath = device.initiatorOutputPath
        self.functionBlock = device.functionBlock
        self.discoveredDevice = device
        self.client = client
        self.cachedDeviceInfo = nil
        self.cachedResourceList = nil
    }
    
    // MARK: - Computed Properties

    /// Display name for UI presentation
    public nonisolated var displayName: String {
        discoveredDevice.displayName
    }

    /// Whether this device supports Property Exchange
    public nonisolated var supportsPropertyExchange: Bool {
        categorySupport.contains(.propertyExchange)
    }

    /// Whether this device supports Profile Configuration
    public nonisolated var supportsProfileConfiguration: Bool {
        categorySupport.contains(.profileConfiguration)
    }

    /// Whether this device supports Process Inquiry
    public nonisolated var supportsProcessInquiry: Bool {
        categorySupport.contains(.processInquiry)
    }

    /// Manufacturer name (if known)
    public nonisolated var manufacturerName: String? {
        identity.manufacturerID.name
    }

    // MARK: - Property Exchange

    /// Get DeviceInfo from the device (cached)
    ///
    /// This property automatically caches the DeviceInfo after the first successful fetch.
    /// Use `invalidateCache()` to force a fresh fetch on the next access.
    ///
    /// - Returns: The device's DeviceInfo, or nil if the device doesn't support PE
    /// - Throws: `MIDI2Error` if the fetch fails
    public var deviceInfo: PEDeviceInfo? {
        get async throws {
            guard supportsPropertyExchange else { return nil }

            if let cached = cachedDeviceInfo {
                return cached
            }

            let info = try await client.getDeviceInfo(from: muid)
            cachedDeviceInfo = info
            return info
        }
    }

    /// Get ResourceList from the device (cached)
    ///
    /// This property automatically caches the ResourceList after the first successful fetch.
    /// Use `invalidateCache()` to force a fresh fetch on the next access.
    ///
    /// - Returns: The device's ResourceList, or nil if the device doesn't support PE
    /// - Throws: `MIDI2Error` if the fetch fails
    public var resourceList: [PEResourceEntry]? {
        get async throws {
            guard supportsPropertyExchange else { return nil }

            if let cached = cachedResourceList {
                return cached
            }

            let list = try await client.getResourceList(from: muid)
            cachedResourceList = list
            return list
        }
    }

    /// Invalidate all cached properties
    ///
    /// Call this method to force fresh fetches on the next property access.
    /// This is useful when you know the device state has changed.
    public func invalidateCache() {
        cachedDeviceInfo = nil
        cachedResourceList = nil
    }

    /// Get a property value with type-safe decoding
    ///
    /// This method fetches a property value from the device and decodes it as the specified type.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct CustomProperty: Codable {
    ///     let value: String
    ///     let enabled: Bool
    /// }
    ///
    /// if let prop = try await device.getProperty("X-CustomProp", as: CustomProperty.self) {
    ///     print("Custom property: \(prop.value), enabled: \(prop.enabled)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - resource: The resource identifier (e.g., "DeviceInfo", "X-CustomProp")
    ///   - type: The expected Decodable type
    /// - Returns: The decoded property value, or nil if the device doesn't support PE
    /// - Throws: `MIDI2Error` if the fetch or decoding fails
    public func getProperty<T: Decodable>(_ resource: String, as type: T.Type) async throws -> T? {
        guard supportsPropertyExchange else { return nil }

        let response = try await client.get(resource, from: muid)

        guard !response.body.isEmpty else {
            throw MIDI2Error.propertyNotSupported(resource: resource)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: response.body)
    }
}

// MARK: - Equatable

extension MIDI2Device: Equatable {
    public nonisolated static func == (lhs: MIDI2Device, rhs: MIDI2Device) -> Bool {
        lhs.id == rhs.id
    }
}
