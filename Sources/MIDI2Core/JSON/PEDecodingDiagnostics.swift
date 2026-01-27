//
//  PEDecodingDiagnostics.swift
//  MIDI2Kit
//
//  Extended PE response with raw data retention for debugging.
//

import Foundation

// MARK: - PEDecodingDiagnostics

/// Diagnostic information when PE response decoding fails
///
/// Contains all the raw data needed to debug parsing issues with
/// embedded MIDI devices.
///
/// ## Usage
///
/// ```swift
/// do {
///     let deviceInfo = try await peManager.getDeviceInfo(from: device)
/// } catch let error as PEError {
///     if case .invalidResponse(let reason) = error {
///         // Check if diagnostics are available
///         if let diag = peManager.lastDecodingDiagnostics {
///             print("Raw body hex: \(diag.rawBody.hexDump)")
///             print("Decoded body: \(diag.decodedBodyString ?? "N/A")")
///             print("Parse error: \(diag.parseError?.localizedDescription ?? "N/A")")
///         }
///     }
/// }
/// ```
public struct PEDecodingDiagnostics: Sendable {
    
    /// Resource that was requested
    public let resource: String
    
    /// Raw response body (before Mcoded7 decoding)
    public let rawBody: Data
    
    /// Decoded body (after Mcoded7 decoding)
    public let decodedBody: Data
    
    /// Attempt to interpret decoded body as UTF-8 string
    public var decodedBodyString: String? {
        String(data: decodedBody, encoding: .utf8)
    }
    
    /// The error that occurred during parsing (if any)
    public let parseError: Error?
    
    /// HTTP-style status code
    public let status: Int
    
    /// Timestamp when this diagnostic was captured
    public let timestamp: Date
    
    /// Whether RobustJSONDecoder preprocessing was applied
    public let wasPreprocessed: Bool
    
    /// Preprocessed JSON data (if preprocessing was applied)
    public let preprocessedData: Data?
    
    // MARK: - Initialization
    
    public init(
        resource: String,
        rawBody: Data,
        decodedBody: Data,
        parseError: Error? = nil,
        status: Int = 0,
        wasPreprocessed: Bool = false,
        preprocessedData: Data? = nil,
        timestamp: Date = Date()
    ) {
        self.resource = resource
        self.rawBody = rawBody
        self.decodedBody = decodedBody
        self.parseError = parseError
        self.status = status
        self.wasPreprocessed = wasPreprocessed
        self.preprocessedData = preprocessedData
        self.timestamp = timestamp
    }
}

// MARK: - CustomStringConvertible

extension PEDecodingDiagnostics: CustomStringConvertible {
    public var description: String {
        var lines: [String] = []
        lines.append("=== PEDecodingDiagnostics ===")
        lines.append("Resource: \(resource)")
        lines.append("Status: \(status)")
        lines.append("Timestamp: \(timestamp)")
        lines.append("")
        lines.append("Raw body (\(rawBody.count) bytes):")
        lines.append(rawBody.hexDumpFormatted())
        lines.append("")
        lines.append("Decoded body (\(decodedBody.count) bytes):")
        if let str = decodedBodyString {
            lines.append("  String: \(str.prefix(500))\(str.count > 500 ? "..." : "")")
        }
        lines.append(decodedBody.hexDumpFormatted())
        
        if wasPreprocessed, let preprocessed = preprocessedData {
            lines.append("")
            lines.append("Preprocessed data (\(preprocessed.count) bytes):")
            if let str = String(data: preprocessed, encoding: .utf8) {
                lines.append("  String: \(str.prefix(500))\(str.count > 500 ? "..." : "")")
            }
        }
        
        if let error = parseError {
            lines.append("")
            lines.append("Parse error: \(error)")
        }
        
        return lines.joined(separator: "\n")
    }
}
