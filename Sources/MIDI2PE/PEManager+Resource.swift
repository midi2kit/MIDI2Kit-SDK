//
//  PEManager+Resource.swift
//  MIDI2Kit
//
//  PEResource-based API overloads for PEManager
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - Extended Resource Diagnostics

/// Which resource path was used when resolving extended (`X-*`) resources.
public enum PEResourceFallbackPath: String, Sendable {
    /// Extended resource was used (`X-*`)
    case extended
    /// Standard resource was used directly (extended disabled)
    case standardOnly
    /// Standard resource was used after extended path failed or returned empty
    case fallbackToStandard
}

/// Diagnostic information for extended resource fallback decisions.
public struct PEResourceFallbackDiagnostics: Sendable {
    /// Base resource name (without `X-` prefix), e.g. `ChannelList`
    public let baseResource: String
    /// Selected resource name that produced the returned result
    public let selectedResource: String
    /// Ordered list of resources attempted
    public let attemptedResources: [String]
    /// Resolution path used
    public let path: PEResourceFallbackPath
    /// Error from extended resource attempt, if any
    public let extendedError: String?
    /// Whether extended resource decoded successfully but was empty
    public let extendedWasEmpty: Bool

    /// Whether fallback to standard resource was used
    public var usedFallback: Bool {
        path == .fallbackToStandard
    }

    public init(
        baseResource: String,
        selectedResource: String,
        attemptedResources: [String],
        path: PEResourceFallbackPath,
        extendedError: String?,
        extendedWasEmpty: Bool
    ) {
        self.baseResource = baseResource
        self.selectedResource = selectedResource
        self.attemptedResources = attemptedResources
        self.path = path
        self.extendedError = extendedError
        self.extendedWasEmpty = extendedWasEmpty
    }

    public var description: String {
        var parts: [String] = []
        parts.append("resource=\(baseResource)")
        parts.append("path=\(path.rawValue)")
        parts.append("selected=\(selectedResource)")
        if extendedWasEmpty { parts.append("extended=empty") }
        if let extendedError { parts.append("extendedError=\(extendedError)") }
        parts.append("attempted=\(attemptedResources.joined(separator: " -> "))")
        return parts.joined(separator: ", ")
    }
}

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
    /// When `preferExtended` is `true`, tries `X-ChannelList` first.
    /// Falls back to `ChannelList` if extended resource fails or returns empty.
    ///
    /// ```swift
    /// let channels = try await peManager.getChannelList(from: device)
    /// for channel in channels {
    ///     print("Ch\(channel.channel): \(channel.programTitle ?? "---")")
    /// }
    /// ```
    public func getChannelList(
        from device: PEDeviceHandle,
        preferExtended: Bool = true,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEChannelInfo] {
        try await getChannelListWithDiagnostics(
            from: device,
            preferExtended: preferExtended,
            timeout: timeout
        ).channels
    }

    /// Get channel list with extended-resource diagnostics.
    public func getChannelListWithDiagnostics(
        from device: PEDeviceHandle,
        preferExtended: Bool = true,
        timeout: Duration = defaultTimeout
    ) async throws -> (channels: [PEChannelInfo], diagnostics: PEResourceFallbackDiagnostics) {
        let result = try await fetchArrayWithExtendedFallback(
            extendedResource: PEResource.xChannelList.rawValue,
            standardResource: PEResource.channelList.rawValue,
            channel: nil,
            preferExtended: preferExtended,
            timeout: timeout,
            fetchResponse: { resource, channel, timeout in
                if let channel {
                    return try await self.get(resource, channel: channel, from: device, timeout: timeout)
                }
                return try await self.get(resource, from: device, timeout: timeout)
            },
            decodeType: PEChannelInfo.self
        )
        return (channels: result.values, diagnostics: result.diagnostics)
    }
    
    /// Get channel list from a device (MUID-only)
    ///
    /// Requires `destinationResolver` to be configured.
    public func getChannelList(
        from muid: MUID,
        preferExtended: Bool = true,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEChannelInfo] {
        try await getChannelListWithDiagnostics(
            from: muid,
            preferExtended: preferExtended,
            timeout: timeout
        ).channels
    }

    /// Get channel list from a device (MUID-only) with diagnostics.
    public func getChannelListWithDiagnostics(
        from muid: MUID,
        preferExtended: Bool = true,
        timeout: Duration = defaultTimeout
    ) async throws -> (channels: [PEChannelInfo], diagnostics: PEResourceFallbackDiagnostics) {
        let result = try await fetchArrayWithExtendedFallback(
            extendedResource: PEResource.xChannelList.rawValue,
            standardResource: PEResource.channelList.rawValue,
            channel: nil,
            preferExtended: preferExtended,
            timeout: timeout,
            fetchResponse: { resource, channel, timeout in
                if let channel {
                    return try await self.get(resource, channel: channel, from: muid, timeout: timeout)
                }
                return try await self.get(resource, from: muid, timeout: timeout)
            },
            decodeType: PEChannelInfo.self
        )
        return (channels: result.values, diagnostics: result.diagnostics)
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
    /// When `preferExtended` is `true`, tries `X-ProgramList` first.
    /// Falls back to `ProgramList` if extended resource fails or returns empty.
    public func getProgramList(
        channel: Int,
        from device: PEDeviceHandle,
        preferExtended: Bool = true,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEProgramDef] {
        try await getProgramListWithDiagnostics(
            channel: channel,
            from: device,
            preferExtended: preferExtended,
            timeout: timeout
        ).programs
    }

    /// Get program list for a channel with extended-resource diagnostics.
    public func getProgramListWithDiagnostics(
        channel: Int,
        from device: PEDeviceHandle,
        preferExtended: Bool = true,
        timeout: Duration = defaultTimeout
    ) async throws -> (programs: [PEProgramDef], diagnostics: PEResourceFallbackDiagnostics) {
        let result = try await fetchArrayWithExtendedFallback(
            extendedResource: PEResource.xProgramList.rawValue,
            standardResource: PEResource.programList.rawValue,
            channel: channel,
            preferExtended: preferExtended,
            timeout: timeout,
            fetchResponse: { resource, channel, timeout in
                if let channel {
                    return try await self.get(resource, channel: channel, from: device, timeout: timeout)
                }
                return try await self.get(resource, from: device, timeout: timeout)
            },
            decodeType: PEProgramDef.self
        )
        return (programs: result.values, diagnostics: result.diagnostics)
    }
    
    /// Get program list for a channel (MUID-only)
    public func getProgramList(
        channel: Int,
        from muid: MUID,
        preferExtended: Bool = true,
        timeout: Duration = defaultTimeout
    ) async throws -> [PEProgramDef] {
        try await getProgramListWithDiagnostics(
            channel: channel,
            from: muid,
            preferExtended: preferExtended,
            timeout: timeout
        ).programs
    }

    /// Get program list for a channel (MUID-only) with diagnostics.
    public func getProgramListWithDiagnostics(
        channel: Int,
        from muid: MUID,
        preferExtended: Bool = true,
        timeout: Duration = defaultTimeout
    ) async throws -> (programs: [PEProgramDef], diagnostics: PEResourceFallbackDiagnostics) {
        let result = try await fetchArrayWithExtendedFallback(
            extendedResource: PEResource.xProgramList.rawValue,
            standardResource: PEResource.programList.rawValue,
            channel: channel,
            preferExtended: preferExtended,
            timeout: timeout,
            fetchResponse: { resource, channel, timeout in
                if let channel {
                    return try await self.get(resource, channel: channel, from: muid, timeout: timeout)
                }
                return try await self.get(resource, from: muid, timeout: timeout)
            },
            decodeType: PEProgramDef.self
        )
        return (programs: result.values, diagnostics: result.diagnostics)
    }

    // MARK: - Private Helpers

    private func fetchArrayWithExtendedFallback<T: Decodable>(
        extendedResource: String,
        standardResource: String,
        channel: Int?,
        preferExtended: Bool,
        timeout: Duration,
        fetchResponse: @Sendable @escaping (_ resource: String, _ channel: Int?, _ timeout: Duration) async throws -> PEResponse,
        decodeType: T.Type
    ) async throws -> (values: [T], diagnostics: PEResourceFallbackDiagnostics) {
        var attempted: [String] = []
        var extendedError: String?
        var extendedWasEmpty = false

        if preferExtended {
            attempted.append(extendedResource)
            do {
                let response = try await fetchResponse(extendedResource, channel, timeout)
                guard response.isSuccess else {
                    throw PEError.deviceError(status: response.status, message: response.header?.message)
                }
                let values = try decodeArray(from: response, as: decodeType, resourceName: extendedResource)
                if !values.isEmpty {
                    return (
                        values: values,
                        diagnostics: PEResourceFallbackDiagnostics(
                            baseResource: standardResource,
                            selectedResource: extendedResource,
                            attemptedResources: attempted,
                            path: .extended,
                            extendedError: nil,
                            extendedWasEmpty: false
                        )
                    )
                }

                // Empty array is treated as "try standard fallback"
                extendedWasEmpty = true
            } catch let error as PEError {
                if case .cancelled = error { throw error }
                extendedError = error.localizedDescription
            } catch is CancellationError {
                throw PEError.cancelled
            } catch {
                extendedError = error.localizedDescription
            }
        }

        attempted.append(standardResource)
        let response = try await fetchResponse(standardResource, channel, timeout)
        guard response.isSuccess else {
            throw PEError.deviceError(status: response.status, message: response.header?.message)
        }
        let values = try decodeArray(from: response, as: decodeType, resourceName: standardResource)
        return (
            values: values,
            diagnostics: PEResourceFallbackDiagnostics(
                baseResource: standardResource,
                selectedResource: standardResource,
                attemptedResources: attempted,
                path: preferExtended ? .fallbackToStandard : .standardOnly,
                extendedError: extendedError,
                extendedWasEmpty: extendedWasEmpty
            )
        )
    }

    private func decodeArray<T: Decodable>(
        from response: PEResponse,
        as type: T.Type,
        resourceName: String
    ) throws -> [T] {
        let decoder = JSONDecoder()

        // Try decodedBody first
        if let values = try? decoder.decode([T].self, from: response.decodedBody) {
            return values
        }

        // Try UTF-8 body string when decodedBody path failed
        if let bodyString = response.bodyString,
           let bodyData = bodyString.data(using: .utf8),
           let values = try? decoder.decode([T].self, from: bodyData) {
            return values
        }

        // Treat empty body as empty array to support fallback decision
        if response.decodedBody.isEmpty || response.bodyString?.isEmpty == true {
            return []
        }

        throw PEError.invalidResponse("Failed to decode \(resourceName)")
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
