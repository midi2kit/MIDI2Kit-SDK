//
//  MIDI2Client+KORG.swift
//  MIDI2Kit
//
//  KORG-specific Property Exchange methods
//
//  These methods provide optimized access to KORG's proprietary PE resources,
//  offering significant performance improvements over standard PE workflows.
//

import Foundation
import MIDI2Core
import MIDI2PE

// MARK: - KORG-Specific Methods

extension MIDI2Client {

    // MARK: - X-ParameterList

    /// Get KORG X-ParameterList (CC parameter definitions)
    ///
    /// This method fetches the `X-ParameterList` resource which provides:
    /// - CC numbers to parameter name mapping (e.g., CC11 = "Inst Level")
    /// - Value ranges and defaults
    /// - Parameter categories
    ///
    /// ## Performance
    ///
    /// For KORG devices with vendor optimizations enabled, this method acts as
    /// an implicit warmup, making it faster than using `getResourceList()` first.
    ///
    /// - Parameters:
    ///   - muid: The device MUID
    ///   - timeout: Optional custom timeout (default: 3 seconds)
    /// - Returns: Array of parameter definitions
    /// - Throws: `MIDI2Error` on failure
    ///
    /// ## Example
    ///
    /// ```swift
    /// let params = try await client.getXParameterList(from: device.muid)
    /// for param in params {
    ///     print("CC\(param.controlCC): \(param.displayName)")
    /// }
    /// ```
    public func getXParameterList(
        from muid: MUID,
        timeout: Duration = .seconds(3)
    ) async throws -> [PEXParameter] {
        let response = try await get("X-ParameterList", from: muid, timeout: timeout)
        return try decodeXParameterList(from: response)
    }

    /// Get KORG X-ParameterList with raw response
    ///
    /// Use this method when you need both parsed data and raw response metadata.
    ///
    /// - Parameters:
    ///   - muid: The device MUID
    ///   - timeout: Optional custom timeout
    /// - Returns: Tuple of (parameters, raw response)
    /// - Throws: `MIDI2Error` on failure
    public func getXParameterListWithResponse(
        from muid: MUID,
        timeout: Duration = .seconds(3)
    ) async throws -> (parameters: [PEXParameter], response: PEResponse) {
        let response = try await get("X-ParameterList", from: muid, timeout: timeout)
        let params = try decodeXParameterList(from: response)
        return (params, response)
    }

    // MARK: - X-ProgramEdit

    /// Get KORG X-ProgramEdit (current program data)
    ///
    /// This method fetches the `X-ProgramEdit` resource which provides:
    /// - Current program name and category
    /// - Current values for all CC parameters
    /// - Bank and program number
    ///
    /// - Parameters:
    ///   - muid: The device MUID
    ///   - timeout: Optional custom timeout
    /// - Returns: Current program data
    /// - Throws: `MIDI2Error` on failure
    ///
    /// ## Example
    ///
    /// ```swift
    /// let program = try await client.getXProgramEdit(from: device.muid)
    /// print("Program: \(program.displayName)")
    /// if let level = program.value(for: 11) {
    ///     print("Inst Level: \(level)")
    /// }
    /// ```
    public func getXProgramEdit(
        from muid: MUID,
        timeout: Duration = .seconds(3)
    ) async throws -> PEXProgramEdit {
        let response = try await get("X-ProgramEdit", from: muid, timeout: timeout)
        return try decodeXProgramEdit(from: response)
    }

    /// Get KORG X-ProgramEdit for a specific channel
    ///
    /// - Parameters:
    ///   - channel: MIDI channel (0-15)
    ///   - muid: The device MUID
    ///   - timeout: Optional custom timeout
    /// - Returns: Current program data for the channel
    /// - Throws: `MIDI2Error` on failure
    public func getXProgramEdit(
        channel: Int,
        from muid: MUID,
        timeout: Duration = .seconds(3)
    ) async throws -> PEXProgramEdit {
        let response = try await get("X-ProgramEdit", channel: channel, from: muid, timeout: timeout)
        return try decodeXProgramEdit(from: response)
    }

    // MARK: - Optimized Resource Fetch

    /// Fetch PE resources using KORG-optimized path when applicable
    ///
    /// When vendor optimizations are enabled for KORG devices, this method:
    /// 1. Skips ResourceList fetch entirely
    /// 2. Directly fetches X-ParameterList (acts as warmup)
    /// 3. Returns results significantly faster (99%+ improvement)
    ///
    /// For non-KORG devices, falls back to standard `getResourceList()` workflow.
    ///
    /// - Parameters:
    ///   - muid: The device MUID
    ///   - preferVendorResources: Whether to prefer vendor-specific resources (default: true)
    /// - Returns: Optimized resource fetch result
    /// - Throws: `MIDI2Error` on failure
    ///
    /// ## Example
    ///
    /// ```swift
    /// let result = try await client.getOptimizedResources(from: device.muid)
    /// if let params = result.xParameterList {
    ///     // KORG fast path was used
    ///     for param in params {
    ///         print("CC\(param.controlCC): \(param.displayName)")
    ///     }
    /// }
    /// ```
    public func getOptimizedResources(
        from muid: MUID,
        preferVendorResources: Bool = true
    ) async throws -> OptimizedResourceResult {
        // Detect vendor from cached DeviceInfo or fetch it
        let vendor: MIDIVendor
        if let cachedInfo = getCachedDeviceInfo(for: muid) {
            vendor = MIDIVendor.detect(from: cachedInfo.manufacturerName)
        } else {
            // Fetch DeviceInfo (also acts as warmup)
            let info = try await getDeviceInfo(from: muid)
            vendor = MIDIVendor.detect(from: info.manufacturerName)
        }

        // Check if KORG optimization is enabled
        let useKORGPath = vendor == .korg &&
            preferVendorResources &&
            configuration.vendorOptimizations.isEnabled(.skipResourceListWhenPossible, for: .korg)

        if useKORGPath {
            // KORG optimized path: directly fetch X-ParameterList
            MIDI2Logger.pe.midi2Debug("KORG optimization: attempting X-ParameterList direct fetch for \(muid)")
            do {
                let startTime = Date()
                let params = try await getXParameterList(from: muid)
                let elapsed = Date().timeIntervalSince(startTime)
                MIDI2Logger.pe.midi2Info("KORG optimization successful: X-ParameterList fetched in \(String(format: "%.0f", elapsed * 1000))ms (\(params.count) parameters)")
                return OptimizedResourceResult(
                    vendor: vendor,
                    usedOptimizedPath: true,
                    xParameterList: params,
                    standardResourceList: nil
                )
            } catch {
                // Fall back to standard path on failure
                MIDI2Logger.pe.midi2Warning("KORG optimized path failed: \(error)")
                MIDI2Logger.pe.midi2Info("Falling back to standard ResourceList path (this may be slower)")
            }
        }

        // Standard path: fetch ResourceList
        MIDI2Logger.pe.midi2Debug("Using standard ResourceList path for \(muid)")
        let startTime = Date()
        let resourceList = try await getResourceList(from: muid)
        let elapsed = Date().timeIntervalSince(startTime)
        MIDI2Logger.pe.midi2Debug("Standard path completed in \(String(format: "%.0f", elapsed * 1000))ms (\(resourceList.count) resources)")
        return OptimizedResourceResult(
            vendor: vendor,
            usedOptimizedPath: false,
            xParameterList: nil,
            standardResourceList: resourceList
        )
    }

    // MARK: - Private Decoding

    private func decodeXParameterList(from response: PEResponse) throws -> [PEXParameter] {
        let decoder = JSONDecoder()

        // Try decoding from decodedBody first
        if let params = try? decoder.decode([PEXParameter].self, from: response.decodedBody) {
            return params
        }

        // Try from bodyString
        if let bodyStr = response.bodyString,
           let data = bodyStr.data(using: .utf8),
           let params = try? decoder.decode([PEXParameter].self, from: data) {
            return params
        }

        // Return empty array if body is empty
        if response.decodedBody.isEmpty || response.bodyString?.isEmpty == true {
            return []
        }

        throw MIDI2Error.invalidResponse(
            muid: nil,
            resource: "X-ParameterList",
            details: "Failed to decode X-ParameterList response"
        )
    }

    private func decodeXProgramEdit(from response: PEResponse) throws -> PEXProgramEdit {
        let decoder = JSONDecoder()

        // Try decoding from decodedBody first
        if let program = try? decoder.decode(PEXProgramEdit.self, from: response.decodedBody) {
            return program
        }

        // Try from bodyString
        if let bodyStr = response.bodyString,
           let data = bodyStr.data(using: .utf8),
           let program = try? decoder.decode(PEXProgramEdit.self, from: data) {
            return program
        }

        throw MIDI2Error.invalidResponse(
            muid: nil,
            resource: "X-ProgramEdit",
            details: "Failed to decode X-ProgramEdit response"
        )
    }
}

// MARK: - Optimized Resource Result

/// Result of optimized resource fetch
public struct OptimizedResourceResult: Sendable {
    /// Detected vendor
    public let vendor: MIDIVendor

    /// Whether the optimized path was used
    public let usedOptimizedPath: Bool

    /// KORG X-ParameterList (if KORG optimized path was used)
    public let xParameterList: [PEXParameter]?

    /// Standard ResourceList (if standard path was used)
    public let standardResourceList: [PEResourceEntry]?

    /// Whether X-ParameterList is available
    public var hasXParameterList: Bool {
        xParameterList != nil && !(xParameterList?.isEmpty ?? true)
    }

    /// Whether standard ResourceList is available
    public var hasStandardResourceList: Bool {
        standardResourceList != nil && !(standardResourceList?.isEmpty ?? true)
    }
}

// MARK: - Convenience Extensions

extension Array where Element == PEXParameter {
    /// Find parameter by CC number
    public func parameter(for cc: Int) -> PEXParameter? {
        first { $0.controlCC == cc }
    }

    /// Get display name for CC number
    public func displayName(for cc: Int) -> String {
        parameter(for: cc)?.displayName ?? "CC\(cc)"
    }

    /// Dictionary of CC -> parameter
    public var byControlCC: [Int: PEXParameter] {
        Dictionary(uniqueKeysWithValues: map { ($0.controlCC, $0) })
    }
}
