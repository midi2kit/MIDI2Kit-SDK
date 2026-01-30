//
//  PEManager+JSON.swift
//  MIDI2Kit
//
//  PEManager extension for typed JSON API
//

import Foundation
import MIDI2Core

// MARK: - Typed API (JSON Codable)

extension PEManager {

    /// Get a resource and decode as JSON
    ///
    /// Automatically handles:
    /// - Mcoded7 decoding
    /// - JSON deserialization
    /// - Error status checking
    ///
    /// ## Example
    /// ```swift
    /// struct ProgramInfo: Decodable {
    ///     let name: String
    ///     let bankMSB: Int
    /// }
    /// let program: ProgramInfo = try await peManager.getJSON("ProgramInfo", from: device)
    /// ```
    public func getJSON<T: Decodable>(
        _ resource: String,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let response = try await get(resource, from: device, timeout: timeout)
        return try decodeResponse(response, resource: resource)
    }

    /// Get a channel-specific resource and decode as JSON
    public func getJSON<T: Decodable>(
        _ resource: String,
        channel: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let response = try await get(resource, channel: channel, from: device, timeout: timeout)
        return try decodeResponse(response, resource: resource)
    }

    /// Get a paginated resource and decode as JSON
    public func getJSON<T: Decodable>(
        _ resource: String,
        offset: Int,
        limit: Int,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let response = try await get(resource, offset: offset, limit: limit, from: device, timeout: timeout)
        return try decodeResponse(response, resource: resource)
    }

    /// Get a resource and decode as JSON (MUID-only)
    public func getJSON<T: Decodable>(
        _ resource: String,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let device = try await resolveDevice(muid)
        return try await getJSON(resource, from: device, timeout: timeout)
    }

    /// Get a channel-specific resource and decode as JSON (MUID-only)
    public func getJSON<T: Decodable>(
        _ resource: String,
        channel: Int,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> T {
        let device = try await resolveDevice(muid)
        return try await getJSON(resource, channel: channel, from: device, timeout: timeout)
    }

    /// Set a resource with JSON-encoded value
    ///
    /// Automatically handles:
    /// - JSON serialization
    /// - Error status checking
    ///
    /// ## Example
    /// ```swift
    /// struct ProgramSettings: Encodable {
    ///     let name: String
    ///     let volume: Int
    /// }
    /// let settings = ProgramSettings(name: "My Sound", volume: 100)
    /// try await peManager.setJSON("ProgramSettings", value: settings, to: device)
    /// ```
    public func setJSON<T: Encodable>(
        _ resource: String,
        value: T,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let data = try encodeValue(value, resource: resource)
        return try await set(resource, data: data, to: device, timeout: timeout)
    }

    /// Set a channel-specific resource with JSON-encoded value
    public func setJSON<T: Encodable>(
        _ resource: String,
        value: T,
        channel: Int,
        to device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let data = try encodeValue(value, resource: resource)
        return try await set(resource, data: data, channel: channel, to: device, timeout: timeout)
    }

    /// Set a resource with JSON-encoded value (MUID-only)
    public func setJSON<T: Encodable>(
        _ resource: String,
        value: T,
        to muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let device = try await resolveDevice(muid)
        return try await setJSON(resource, value: value, to: device, timeout: timeout)
    }

    /// Set a channel-specific resource with JSON-encoded value (MUID-only)
    public func setJSON<T: Encodable>(
        _ resource: String,
        value: T,
        channel: Int,
        to muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        let device = try await resolveDevice(muid)
        return try await setJSON(resource, value: value, channel: channel, to: device, timeout: timeout)
    }
}
