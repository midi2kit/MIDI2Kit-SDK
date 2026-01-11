//
//  PEManager+Resource.swift
//  MIDI2Kit
//
//  PEResource-based API overloads for PEManager
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - PEResource Overloads

extension PEManager {
    
    // MARK: - GET with PEResource
    
    /// Get a resource from a device using PEResource constant
    ///
    /// ```swift
    /// let response = try await peManager.get(.deviceInfo, from: device)
    /// ```
    public func get(
        _ resource: PEResource,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await get(resource.rawValue, from: device, timeout: timeout)
    }
    
    /// Get a channel-specific resource using PEResource constant
    public func get(
        _ resource: PEResource,
        channel: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await get(resource.rawValue, channel: channel, from: device, timeout: timeout)
    }
    
    /// Get a paginated resource using PEResource constant
    public func get(
        _ resource: PEResource,
        offset: Int,
        limit: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await get(resource.rawValue, offset: offset, limit: limit, from: device, timeout: timeout)
    }
    
    // MARK: - GET with PEResource (MUID-only)
    
    /// Get a resource using PEResource constant (MUID-only)
    public func get(
        _ resource: PEResource,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await get(resource.rawValue, from: muid, timeout: timeout)
    }
    
    /// Get a channel-specific resource using PEResource constant (MUID-only)
    public func get(
        _ resource: PEResource,
        channel: Int,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await get(resource.rawValue, channel: channel, from: muid, timeout: timeout)
    }
    
    /// Get a paginated resource using PEResource constant (MUID-only)
    public func get(
        _ resource: PEResource,
        offset: Int,
        limit: Int,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await get(resource.rawValue, offset: offset, limit: limit, from: muid, timeout: timeout)
    }
    
    // MARK: - SET with PEResource
    
    /// Set a resource value using PEResource constant
    public func set(
        _ resource: PEResource,
        data: Data,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await set(resource.rawValue, data: data, to: device, timeout: timeout)
    }
    
    /// Set a channel-specific resource using PEResource constant
    public func set(
        _ resource: PEResource,
        data: Data,
        channel: Int,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await set(resource.rawValue, data: data, channel: channel, to: device, timeout: timeout)
    }
    
    /// Set a resource value using PEResource constant (MUID-only)
    public func set(
        _ resource: PEResource,
        data: Data,
        to muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await set(resource.rawValue, data: data, to: muid, timeout: timeout)
    }
    
    /// Set a channel-specific resource using PEResource constant (MUID-only)
    public func set(
        _ resource: PEResource,
        data: Data,
        channel: Int,
        to muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await set(resource.rawValue, data: data, channel: channel, to: muid, timeout: timeout)
    }
    
    // MARK: - Subscribe with PEResource
    
    /// Subscribe to notifications using PEResource constant
    public func subscribe(
        to resource: PEResource,
        on device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PESubscribeResponse {
        try await subscribe(to: resource.rawValue, on: device, timeout: timeout)
    }
    
    /// Subscribe to notifications using PEResource constant (MUID-only)
    public func subscribe(
        to resource: PEResource,
        on muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PESubscribeResponse {
        try await subscribe(to: resource.rawValue, on: muid, timeout: timeout)
    }
    
    // MARK: - Typed JSON API with PEResource
    
    /// Get a resource and decode as JSON using PEResource constant
    public func getJSON<T: Decodable>(
        _ resource: PEResource,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        try await getJSON(resource.rawValue, from: device, timeout: timeout)
    }
    
    /// Get a channel-specific resource and decode as JSON using PEResource constant
    public func getJSON<T: Decodable>(
        _ resource: PEResource,
        channel: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        try await getJSON(resource.rawValue, channel: channel, from: device, timeout: timeout)
    }
    
    /// Get a resource and decode as JSON using PEResource constant (MUID-only)
    public func getJSON<T: Decodable>(
        _ resource: PEResource,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        try await getJSON(resource.rawValue, from: muid, timeout: timeout)
    }
    
    /// Set a resource with JSON-encoded value using PEResource constant
    public func setJSON<T: Encodable>(
        _ resource: PEResource,
        value: T,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await setJSON(resource.rawValue, value: value, to: device, timeout: timeout)
    }
    
    /// Set a resource with JSON-encoded value using PEResource constant (MUID-only)
    public func setJSON<T: Encodable>(
        _ resource: PEResource,
        value: T,
        to muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        try await setJSON(resource.rawValue, value: value, to: muid, timeout: timeout)
    }
    
    // MARK: - Channel List Convenience Methods
    
    /// Get channel list from a device
    ///
    /// Fetches the X-ChannelList resource and decodes it.
    ///
    /// ```swift
    /// let channels = try await peManager.getChannelList(from: device)
    /// for channel in channels {
    ///     print("Ch\(channel.channel): \(channel.programTitle ?? "---")")
    /// }
    /// ```
    public func getChannelList(
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEChannelInfo] {
        let response = try await get(.xChannelList, from: device, timeout: timeout)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        do {
            return try JSONDecoder().decode([PEChannelInfo].self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode X-ChannelList: \(error)")
        }
    }
    
    /// Get channel list from a device (MUID-only)
    ///
    /// Requires `destinationResolver` to be configured.
    public func getChannelList(
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEChannelInfo] {
        let response = try await get(.xChannelList, from: muid, timeout: timeout)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        do {
            return try JSONDecoder().decode([PEChannelInfo].self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode X-ChannelList: \(error)")
        }
    }
    
    /// Get controller list for a channel
    ///
    /// Fetches the ChCtrlList resource for a specific channel.
    ///
    /// ```swift
    /// let controllers = try await peManager.getControllerList(channel: 0, from: device)
    /// for ctrl in controllers {
    ///     print("CC\(ctrl.ctrlIndex): \(ctrl.name ?? "---")")
    /// }
    /// ```
    public func getControllerList(
        channel: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEControllerDef] {
        let response = try await get(.channelControllerList, channel: channel, from: device, timeout: timeout)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        do {
            return try JSONDecoder().decode([PEControllerDef].self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode ChCtrlList: \(error)")
        }
    }
    
    /// Get controller list for a channel (MUID-only)
    public func getControllerList(
        channel: Int,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEControllerDef] {
        let response = try await get(.channelControllerList, channel: channel, from: muid, timeout: timeout)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        do {
            return try JSONDecoder().decode([PEControllerDef].self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode ChCtrlList: \(error)")
        }
    }
    
    /// Get program list for a channel
    ///
    /// Fetches the ProgramList resource for a specific channel.
    public func getProgramList(
        channel: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEProgramDef] {
        let response = try await get(.programList, channel: channel, from: device, timeout: timeout)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        do {
            return try JSONDecoder().decode([PEProgramDef].self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode ProgramList: \(error)")
        }
    }
    
    /// Get program list for a channel (MUID-only)
    public func getProgramList(
        channel: Int,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEProgramDef] {
        let response = try await get(.programList, channel: channel, from: muid, timeout: timeout)
        
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        
        do {
            return try JSONDecoder().decode([PEProgramDef].self, from: response.decodedBody)
        } catch {
            throw PEError.invalidResponse("Failed to decode ProgramList: \(error)")
        }
    }
}

// MARK: - PERequest Factory with PEResource

extension PERequest {
    
    /// Create a GET request using PEResource constant
    public static func get(
        _ resource: PEResource,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        get(resource.rawValue, from: device, timeout: timeout)
    }
    
    /// Create a GET request with channel using PEResource constant
    public static func get(
        _ resource: PEResource,
        channel: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        get(resource.rawValue, channel: channel, from: device, timeout: timeout)
    }
    
    /// Create a paginated GET request using PEResource constant
    public static func get(
        _ resource: PEResource,
        offset: Int,
        limit: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        get(resource.rawValue, offset: offset, limit: limit, from: device, timeout: timeout)
    }
    
    /// Create a SET request using PEResource constant
    public static func set(
        _ resource: PEResource,
        data: Data,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        set(resource.rawValue, data: data, to: device, timeout: timeout)
    }
    
    /// Create a SET request with channel using PEResource constant
    public static func set(
        _ resource: PEResource,
        data: Data,
        channel: Int,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) -> PERequest {
        set(resource.rawValue, data: data, channel: channel, to: device, timeout: timeout)
    }
}
