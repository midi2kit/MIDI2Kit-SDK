//
//  PEManager+RobustDecoding.swift
//  MIDI2Kit
//
//  Extension for robust JSON decoding with diagnostics.
//

import Foundation
import MIDI2Core

// MARK: - PEManager Robust Decoding Extension

extension PEManager {
    
    /// The shared RobustJSONDecoder instance
    private static let robustDecoder = RobustJSONDecoder()
    
    /// Decode PE response body with robust JSON handling
    ///
    /// Uses RobustJSONDecoder to handle non-standard JSON from embedded devices.
    /// On failure, creates PEDecodingDiagnostics for debugging.
    ///
    /// - Parameters:
    ///   - type: The type to decode into
    ///   - response: The PE response containing the body
    ///   - resource: Resource name for diagnostics
    /// - Returns: Decoded value and optional diagnostics
    /// - Throws: `PEError.invalidResponse` if decoding fails
    public func decodeResponse<T: Decodable>(
        _ type: T.Type,
        from response: PEResponse,
        resource: String
    ) throws -> (value: T, diagnostics: PEDecodingDiagnostics?) {
        let decoder = Self.robustDecoder
        let data = response.decodedBody
        
        let result = decoder.decodeWithDiagnostics(type, from: data)
        
        switch result {
        case .success(let value, let wasFixed):
            if wasFixed {
                // Create diagnostics even on success if preprocessing was needed
                let diagnostics = PEDecodingDiagnostics(
                    resource: resource,
                    rawBody: response.body,
                    decodedBody: data,
                    status: response.status,
                    wasPreprocessed: true,
                    preprocessedData: decoder.preprocess(data).0
                )
                return (value, diagnostics)
            }
            return (value, nil)
            
        case .failure(let error, _, let attemptedFix):
            // Create diagnostics for debugging
            let diagnostics = PEDecodingDiagnostics(
                resource: resource,
                rawBody: response.body,
                decodedBody: data,
                parseError: error,
                status: response.status,
                wasPreprocessed: attemptedFix != nil,
                preprocessedData: attemptedFix
            )
            
            throw PEError.invalidResponse(
                "Failed to decode \(resource): \(error.localizedDescription). " +
                "Raw data: \(data.hexDumpPreview)"
            )
        }
    }
    
    /// Convenience method to decode DeviceInfo with robust handling
    public func decodeDeviceInfo(from response: PEResponse) throws -> PEDeviceInfo {
        try decodeResponse(PEDeviceInfo.self, from: response, resource: "DeviceInfo").value
    }
    
    /// Convenience method to decode ResourceList with robust handling
    public func decodeResourceList(from response: PEResponse) throws -> [PEResourceEntry] {
        try decodeResponse([PEResourceEntry].self, from: response, resource: "ResourceList").value
    }
}

// MARK: - Convenience Extensions

extension PEResponse {
    /// Decode body as JSON with robust handling
    ///
    /// Uses RobustJSONDecoder to handle non-standard JSON.
    ///
    /// - Parameter type: The type to decode into
    /// - Returns: The decoded value
    /// - Throws: `DecodingError` or `RobustJSONError` on failure
    public func decodeBody<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = RobustJSONDecoder()
        return try decoder.decode(type, from: decodedBody)
    }
    
    /// Decode body with diagnostics
    ///
    /// - Parameter type: The type to decode into
    /// - Returns: DecodeResult with value or error details
    public func decodeBodyWithDiagnostics<T: Decodable>(_ type: T.Type) -> DecodeResult<T> {
        let decoder = RobustJSONDecoder()
        return decoder.decodeWithDiagnostics(type, from: decodedBody)
    }
}
