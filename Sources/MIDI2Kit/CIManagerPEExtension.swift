//
//  CIManagerPEExtension.swift
//  MIDI2Kit
//
//  Bridge between CIManager (Discovery) and PEDeviceHandle (Property Exchange)
//

import MIDI2CI
import MIDI2PE
import MIDI2Core
import MIDI2Transport

// MARK: - CIManager PE Bridge

extension CIManager {
    
    /// Create a PEDeviceHandle for a discovered device
    ///
    /// This bridges MIDI-CI Discovery with Property Exchange, providing
    /// a convenient way to start PE communication with a discovered device.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Discovery → PE workflow
    /// for await event in ciManager.events {
    ///     if case .deviceDiscovered(let device) = event,
    ///        device.supportsPropertyExchange {
    ///         
    ///         if let handle = ciManager.peDeviceHandle(for: device.muid) {
    ///             let response = try await peManager.get("DeviceInfo", from: handle)
    ///             print(response.bodyString ?? "")
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter muid: The MUID of the discovered device
    /// - Returns: A `PEDeviceHandle` if the device exists and has a destination, nil otherwise
    public func peDeviceHandle(for muid: MUID) -> PEDeviceHandle? {
        guard let device = device(for: muid),
              let destination = destination(for: muid) else {
            return nil
        }
        
        return PEDeviceHandle(
            muid: muid,
            destination: destination,
            name: device.displayName
        )
    }
    
    /// Create a PEDeviceHandle directly from a DiscoveredDevice
    ///
    /// This is a convenience method when you already have the device object.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let devices = ciManager.peCapableDevices
    /// for device in devices {
    ///     if let handle = ciManager.peDeviceHandle(for: device) {
    ///         let info = try await peManager.get("DeviceInfo", from: handle)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter device: The discovered device
    /// - Returns: A `PEDeviceHandle` if the device has a destination, nil otherwise
    public func peDeviceHandle(for device: DiscoveredDevice) -> PEDeviceHandle? {
        guard let destination = destination(for: device.muid) else {
            return nil
        }
        
        return PEDeviceHandle(
            muid: device.muid,
            destination: destination,
            name: device.displayName
        )
    }
    
    /// Get all PE-capable devices as PEDeviceHandles
    ///
    /// Convenience method to get handles for all devices that support
    /// Property Exchange in one call.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let handles = ciManager.peDeviceHandles
    /// for handle in handles {
    ///     print("Ready for PE: \(handle.debugDescription)")
    /// }
    /// ```
    public var peDeviceHandles: [PEDeviceHandle] {
        var handles: [PEDeviceHandle] = []
        for device in peCapableDevices {
            if let handle = peDeviceHandle(for: device) {
                handles.append(handle)
            }
        }
        return handles
    }
}

// MARK: - DiscoveredDevice PE Extension

extension DiscoveredDevice {
    
    /// Create a PEDeviceHandle from this device (requires destination)
    ///
    /// Use this when you have both the device and its destination.
    ///
    /// - Parameter destination: The MIDI destination for this device
    /// - Returns: A `PEDeviceHandle` ready for PE operations
    public func peDeviceHandle(destination: MIDIDestinationID) -> PEDeviceHandle {
        PEDeviceHandle(
            muid: muid,
            destination: destination,
            name: displayName
        )
    }
}
