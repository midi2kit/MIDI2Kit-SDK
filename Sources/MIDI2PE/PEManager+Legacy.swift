//
//  PEManager+Legacy.swift
//  MIDI2Kit
//
//  PEManager extension for deprecated legacy API
//
//  These methods accept separate MUID and destination parameters.
//  Use the modern API with PEDeviceHandle instead.
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - Legacy API (MUID + Destination separate)

extension PEManager {

    /// Get a resource from a device (legacy API)
    @available(*, deprecated, message: "Use get(_:from:) with PEDeviceHandle instead")
    public func get(
        resource: String,
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await get(resource, from: handle, timeout: timeout)
    }

    /// Get a channel-specific resource (legacy API)
    @available(*, deprecated, message: "Use get(_:channel:from:) with PEDeviceHandle instead")
    public func get(
        resource: String,
        channel: Int,
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await get(resource, channel: channel, from: handle, timeout: timeout)
    }

    /// Get a paginated resource (legacy API)
    @available(*, deprecated, message: "Use get(_:offset:limit:from:) with PEDeviceHandle instead")
    public func get(
        resource: String,
        offset: Int,
        limit: Int,
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await get(resource, offset: offset, limit: limit, from: handle, timeout: timeout)
    }

    /// Set a resource value (legacy API)
    @available(*, deprecated, message: "Use set(_:data:to:) with PEDeviceHandle instead")
    public func set(
        resource: String,
        data: Data,
        to device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await set(resource, data: data, to: handle, timeout: timeout)
    }

    /// Subscribe to notifications (legacy API)
    @available(*, deprecated, message: "Use subscribe(to:on:) with PEDeviceHandle instead")
    public func subscribe(
        to resource: String,
        on device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout
    ) async throws -> PESubscribeResponse {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await subscribe(to: resource, on: handle, timeout: timeout)
    }

    /// Get DeviceInfo (legacy API)
    @available(*, deprecated, message: "Use getDeviceInfo(from:) with PEDeviceHandle instead")
    public func getDeviceInfo(
        from device: MUID,
        via destination: MIDIDestinationID
    ) async throws -> PEDeviceInfo {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await getDeviceInfo(from: handle)
    }

    /// Get ResourceList (legacy API)
    @available(*, deprecated, message: "Use getResourceList(from:) with PEDeviceHandle instead")
    public func getResourceList(
        from device: MUID,
        via destination: MIDIDestinationID,
        timeout: Duration = defaultTimeout,
        maxRetries: Int = 5
    ) async throws -> [PEResourceEntry] {
        let handle = PEDeviceHandle(muid: device, destination: destination)
        return try await getResourceList(from: handle, timeout: timeout, maxRetries: maxRetries)
    }
}
