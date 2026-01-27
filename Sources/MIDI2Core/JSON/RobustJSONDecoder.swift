//
//  RobustJSONDecoder.swift
//  MIDI2Kit
//
//  Fault-tolerant JSON decoder for embedded MIDI device responses.
//
//  Many MIDI devices return non-standard JSON that fails strict parsing.
//  This decoder preprocesses the JSON to fix common issues before decoding.
//

import Foundation

// MARK: - RobustJSONDecoder

/// A fault-tolerant JSON decoder that handles common non-standard JSON patterns
///
/// ## Problem
///
/// Embedded MIDI devices often return JSON with issues like:
/// - Trailing commas: `{"a": 1, "b": 2,}`
/// - Single quotes: `{'name': 'value'}`
/// - Unescaped control characters
/// - Comments: `// comment` or `/* comment */`
///
/// Standard `JSONDecoder` rejects these, causing parse failures.
///
/// ## Solution
///
/// `RobustJSONDecoder` preprocesses JSON data to fix known issues,
/// while preserving the original data for diagnostics.
///
/// ## Usage
///
/// ```swift
/// let decoder = RobustJSONDecoder()
///
/// // Decode with automatic fixing
/// let result: MyType = try decoder.decode(MyType.self, from: data)
///
/// // Or get detailed result with diagnostics
/// let detailedResult = decoder.decodeWithDiagnostics(MyType.self, from: data)
/// switch detailedResult {
/// case .success(let value, let wasFixed):
///     if wasFixed {
///         print("JSON was automatically fixed")
///     }
/// case .failure(let error, let rawData, let attemptedFix):
///     print("Decode failed: \(error)")
///     print("Raw data hex: \(rawData.hexDump)")
/// }
/// ```
public struct RobustJSONDecoder {
    
    /// The underlying JSON decoder
    private let decoder: JSONDecoder
    
    /// Whether to enable preprocessing (default: true)
    public var enablePreprocessing: Bool
    
    /// Logger for debugging (optional)
    public var logger: ((String) -> Void)?
    
    // MARK: - Initialization
    
    /// Create a new RobustJSONDecoder
    /// - Parameters:
    ///   - decoder: The underlying JSONDecoder to use (default: new instance)
    ///   - enablePreprocessing: Whether to preprocess JSON (default: true)
    public init(
        decoder: JSONDecoder = JSONDecoder(),
        enablePreprocessing: Bool = true
    ) {
        self.decoder = decoder
        self.enablePreprocessing = enablePreprocessing
    }
    
    // MARK: - Decoding
    
    /// Decode JSON data into a Decodable type
    ///
    /// Automatically applies preprocessing if standard decoding fails.
    ///
    /// - Parameters:
    ///   - type: The type to decode into
    ///   - data: The JSON data
    /// - Returns: The decoded value
    /// - Throws: `DecodingError` if decoding fails even after preprocessing
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Try standard decoding first
        do {
            return try decoder.decode(type, from: data)
        } catch let standardError {
            // If preprocessing is disabled, throw the original error
            guard enablePreprocessing else {
                throw standardError
            }
            
            // Try with preprocessing
            let (fixedData, wasFixed) = preprocess(data)
            
            if wasFixed {
                logger?("JSON preprocessing applied")
                do {
                    return try decoder.decode(type, from: fixedData)
                } catch {
                    // Preprocessing didn't help, throw original error with context
                    throw RobustJSONError.decodingFailed(
                        originalError: standardError,
                        preprocessedError: error,
                        rawData: data,
                        fixedData: fixedData
                    )
                }
            } else {
                // No fixes applied, throw original error
                throw standardError
            }
        }
    }
    
    /// Decode with detailed diagnostics
    ///
    /// Returns additional information about the decoding process,
    /// useful for debugging embedded device responses.
    ///
    /// - Parameters:
    ///   - type: The type to decode into
    ///   - data: The JSON data
    /// - Returns: A `DecodeResult` with the value and diagnostics
    public func decodeWithDiagnostics<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) -> DecodeResult<T> {
        // Try standard decoding first
        do {
            let value = try decoder.decode(type, from: data)
            return .success(value: value, wasFixed: false)
        } catch let standardError {
            // If preprocessing is disabled, return failure
            guard enablePreprocessing else {
                return .failure(
                    error: standardError,
                    rawData: data,
                    attemptedFix: nil
                )
            }
            
            // Try with preprocessing
            let (fixedData, wasFixed) = preprocess(data)
            
            if wasFixed {
                do {
                    let value = try decoder.decode(type, from: fixedData)
                    return .success(value: value, wasFixed: true)
                } catch let fixedError {
                    return .failure(
                        error: fixedError,
                        rawData: data,
                        attemptedFix: fixedData
                    )
                }
            } else {
                return .failure(
                    error: standardError,
                    rawData: data,
                    attemptedFix: nil
                )
            }
        }
    }
    
    // MARK: - Preprocessing
    
    /// Preprocess JSON data to fix common issues
    ///
    /// - Parameter data: Original JSON data
    /// - Returns: Tuple of (potentially fixed data, whether any fixes were applied)
    public func preprocess(_ data: Data) -> (Data, Bool) {
        guard var string = String(data: data, encoding: .utf8) else {
            return (data, false)
        }
        
        let original = string
        
        // Apply fixes in order
        string = removeComments(string)
        string = fixTrailingCommas(string)
        string = fixSingleQuotes(string)
        string = escapeControlCharacters(string)
        string = fixUnquotedKeys(string)
        
        let wasFixed = string != original
        
        if wasFixed, let fixedData = string.data(using: .utf8) {
            return (fixedData, true)
        }
        
        return (data, false)
    }
    
    // MARK: - Fix Functions
    
    /// Remove JavaScript-style comments
    private func removeComments(_ string: String) -> String {
        var result = string
        
        // Remove single-line comments: // ...
        // Be careful not to remove // inside strings
        let singleLinePattern = #"(?<!["'])//[^\n]*"#
        if let regex = try? NSRegularExpression(pattern: singleLinePattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        
        // Remove multi-line comments: /* ... */
        let multiLinePattern = #"/\*[\s\S]*?\*/"#
        if let regex = try? NSRegularExpression(pattern: multiLinePattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        
        return result
    }
    
    /// Fix trailing commas before ] or }
    private func fixTrailingCommas(_ string: String) -> String {
        var result = string
        
        // Pattern: comma followed by optional whitespace and ] or }
        let pattern = #",(\s*[\]\}])"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1"
            )
        }
        
        return result
    }
    
    /// Convert single quotes to double quotes (outside of existing double-quoted strings)
    private func fixSingleQuotes(_ string: String) -> String {
        var result = [Character]()
        var inDoubleQuote = false
        var inSingleQuote = false
        var prevChar: Character?
        
        for char in string {
            let isEscaped = prevChar == "\\"
            
            if char == "\"" && !isEscaped && !inSingleQuote {
                inDoubleQuote.toggle()
                result.append(char)
            } else if char == "'" && !isEscaped && !inDoubleQuote {
                // Convert single quote to double quote
                inSingleQuote.toggle()
                result.append("\"")
            } else {
                result.append(char)
            }
            
            prevChar = char
        }
        
        return String(result)
    }
    
    /// Escape unescaped control characters
    private func escapeControlCharacters(_ string: String) -> String {
        var result = string
        
        // Escape common problematic control characters
        // Tab, newline, carriage return inside strings should be escaped
        
        // This is a simplified approach - full implementation would need
        // to track whether we're inside a string literal
        
        // For now, just ensure any literal control chars are escaped
        let replacements: [(String, String)] = [
            ("\t", "\\t"),
            ("\r\n", "\\r\\n"),
            ("\r", "\\r"),
            ("\n", "\\n"),
        ]
        
        for (original, escaped) in replacements {
            // Only replace if not already escaped
            result = result.replacingOccurrences(of: original, with: escaped)
        }
        
        return result
    }
    
    /// Fix unquoted keys (common in JavaScript-style JSON)
    private func fixUnquotedKeys(_ string: String) -> String {
        var result = string
        
        // Pattern: unquoted key followed by colon
        // Matches: { key: or , key:
        // But not already quoted keys
        let pattern = #"([\{\,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)(\s*:)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: #"$1"$2"$3"#
            )
        }
        
        return result
    }
}

// MARK: - DecodeResult

/// Result of decoding with diagnostics
public enum DecodeResult<T> {
    /// Decoding succeeded
    /// - Parameters:
    ///   - value: The decoded value
    ///   - wasFixed: Whether preprocessing was applied
    case success(value: T, wasFixed: Bool)
    
    /// Decoding failed
    /// - Parameters:
    ///   - error: The decoding error
    ///   - rawData: The original raw data (for diagnostics)
    ///   - attemptedFix: The preprocessed data that was attempted (if any)
    case failure(error: Error, rawData: Data, attemptedFix: Data?)
    
    /// Get the decoded value if successful
    public var value: T? {
        switch self {
        case .success(let value, _):
            return value
        case .failure:
            return nil
        }
    }
    
    /// Whether decoding was successful
    public var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

// MARK: - RobustJSONError

/// Errors from RobustJSONDecoder
public enum RobustJSONError: Error {
    /// Decoding failed even after preprocessing
    case decodingFailed(
        originalError: Error,
        preprocessedError: Error,
        rawData: Data,
        fixedData: Data
    )
}

extension RobustJSONError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .decodingFailed(let original, let preprocessed, let rawData, let fixedData):
            var lines: [String] = []
            lines.append("JSON decoding failed:")
            lines.append("  Original error: \(original)")
            lines.append("  After preprocessing: \(preprocessed)")
            lines.append("  Raw data (\(rawData.count) bytes): \(rawData.hexDumpPreview)")
            lines.append("  Fixed data (\(fixedData.count) bytes): \(fixedData.hexDumpPreview)")
            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - Data Extension

extension Data {
    /// Hex dump preview (first 64 bytes)
    public var hexDumpPreview: String {
        let preview = self.prefix(64)
        let hex = preview.map { String(format: "%02X", $0) }.joined(separator: " ")
        if self.count > 64 {
            return "\(hex)... (\(self.count) bytes total)"
        }
        return hex
    }
    
    /// Full hex dump
    public var hexDump: String {
        self.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// Hex dump with ASCII representation (like xxd)
    public func hexDumpFormatted(bytesPerLine: Int = 16) -> String {
        var lines: [String] = []
        var offset = 0
        
        while offset < self.count {
            let lineEnd = min(offset + bytesPerLine, self.count)
            let lineBytes = self[offset..<lineEnd]
            
            // Offset
            var line = String(format: "%08X: ", offset)
            
            // Hex bytes
            let hexPart = lineBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            line += hexPart.padding(toLength: bytesPerLine * 3 - 1, withPad: " ", startingAt: 0)
            line += "  "
            
            // ASCII
            let asciiPart = lineBytes.map { byte -> Character in
                if byte >= 0x20 && byte < 0x7F {
                    return Character(UnicodeScalar(byte))
                }
                return "."
            }
            line += String(asciiPart)
            
            lines.append(line)
            offset = lineEnd
        }
        
        return lines.joined(separator: "\n")
    }
}
