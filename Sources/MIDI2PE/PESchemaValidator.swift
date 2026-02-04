//
//  PESchemaValidator.swift
//  MIDI2Kit
//
//  Lightweight JSON Schema validation for Property Exchange responses
//
//  This validator provides basic structural validation for PE JSON payloads
//  without external dependencies. It validates required fields, types, and
//  basic constraints based on MIDI-CI Property Exchange specifications.
//

import Foundation

// MARK: - Schema Validation Errors

/// Errors that can occur during schema validation
public enum PESchemaValidationError: Error, Sendable, CustomStringConvertible {
    /// JSON parsing failed
    case invalidJSON(Error)

    /// Expected object, got different type
    case expectedObject

    /// Expected array, got different type
    case expectedArray

    /// Required field is missing
    case missingRequiredField(String)

    /// Field has wrong type
    case wrongFieldType(field: String, expected: String, actual: String)

    /// Field value is out of valid range
    case valueOutOfRange(field: String, valueDescription: String, range: String)

    /// Unknown resource type
    case unknownResource(String)

    /// Multiple validation errors
    case multipleErrors([PESchemaValidationError])

    public var description: String {
        switch self {
        case .invalidJSON(let error):
            return "Invalid JSON: \(error.localizedDescription)"
        case .expectedObject:
            return "Expected JSON object"
        case .expectedArray:
            return "Expected JSON array"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .wrongFieldType(let field, let expected, let actual):
            return "Field '\(field)' has wrong type: expected \(expected), got \(actual)"
        case .valueOutOfRange(let field, let valueDesc, let range):
            return "Field '\(field)' value \(valueDesc) is out of range: \(range)"
        case .unknownResource(let name):
            return "Unknown resource type: \(name)"
        case .multipleErrors(let errors):
            return "Multiple validation errors:\n" + errors.map { "  - \($0)" }.joined(separator: "\n")
        }
    }
}

// MARK: - Validation Result

/// Result of schema validation
public struct PESchemaValidationResult: Sendable {
    /// Whether validation passed
    public let isValid: Bool

    /// Validation errors (empty if valid)
    public let errors: [PESchemaValidationError]

    /// Warnings (non-fatal issues)
    public let warnings: [String]

    public static let valid = PESchemaValidationResult(isValid: true, errors: [], warnings: [])

    public static func invalid(_ error: PESchemaValidationError) -> PESchemaValidationResult {
        PESchemaValidationResult(isValid: false, errors: [error], warnings: [])
    }

    public static func invalid(_ errors: [PESchemaValidationError]) -> PESchemaValidationResult {
        PESchemaValidationResult(isValid: false, errors: errors, warnings: [])
    }
}

// MARK: - Schema Validator

/// Lightweight JSON Schema validator for PE payloads
///
/// ## Supported Resources
/// - `DeviceInfo`: Device identification and capabilities
/// - `ResourceList`: Available PE resources
/// - `ChannelList`: MIDI channel configuration
/// - `CMList`: Control Map list (KORG extension)
///
/// ## Usage
/// ```swift
/// let validator = PESchemaValidator()
///
/// // Validate DeviceInfo response
/// let result = validator.validate(jsonData, forResource: "DeviceInfo")
/// if !result.isValid {
///     print("Validation errors: \(result.errors)")
/// }
///
/// // Auto-detect resource type from data
/// let autoResult = validator.validateAuto(jsonData)
/// ```
public struct PESchemaValidator: Sendable {

    public init() {}

    // MARK: - Public API

    /// Validate JSON data for a specific resource type
    /// - Parameters:
    ///   - data: JSON data to validate
    ///   - resource: Resource name (e.g., "DeviceInfo", "ResourceList")
    /// - Returns: Validation result
    public func validate(_ data: Data, forResource resource: String) -> PESchemaValidationResult {
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            return validate(json, forResource: resource)
        } catch {
            return .invalid(.invalidJSON(error))
        }
    }

    /// Validate parsed JSON for a specific resource type
    /// - Parameters:
    ///   - json: Parsed JSON object
    ///   - resource: Resource name
    /// - Returns: Validation result
    public func validate(_ json: Any, forResource resource: String) -> PESchemaValidationResult {
        switch resource.lowercased() {
        case "deviceinfo":
            return validateDeviceInfo(json)
        case "resourcelist":
            return validateResourceList(json)
        case "channellist":
            return validateChannelList(json)
        case "cmlist":
            return validateCMList(json)
        default:
            // Unknown resources pass validation (forward compatibility)
            return .valid
        }
    }

    /// Auto-detect resource type and validate
    /// - Parameter data: JSON data to validate
    /// - Returns: Validation result (may indicate unknown resource)
    public func validateAuto(_ data: Data) -> PESchemaValidationResult {
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            return validateAuto(json)
        } catch {
            return .invalid(.invalidJSON(error))
        }
    }

    /// Auto-detect resource type from parsed JSON and validate
    public func validateAuto(_ json: Any) -> PESchemaValidationResult {
        // Try to detect resource type from structure
        if let dict = json as? [String: Any] {
            // DeviceInfo has specific fields
            if dict["manufacturerId"] != nil || dict["familyId"] != nil {
                return validateDeviceInfo(dict)
            }
        } else if let array = json as? [[String: Any]] {
            // Check first element for hints
            if let first = array.first {
                if first["resource"] != nil {
                    return validateResourceList(array)
                }
                if first["title"] != nil && first["channel"] != nil {
                    return validateChannelList(array)
                }
            }
        }

        // Unknown structure - pass validation
        return .valid
    }

    // MARK: - DeviceInfo Validation

    /// DeviceInfo schema:
    /// {
    ///   "manufacturerId": [int, int, int],  // Required
    ///   "familyId": [int, int],             // Required
    ///   "modelId": [int, int],              // Required
    ///   "versionId": [int, int, int, int],  // Required
    ///   "manufacturer": string,             // Optional
    ///   "family": string,                   // Optional
    ///   "model": string,                    // Optional
    ///   "version": string                   // Optional
    /// }
    private func validateDeviceInfo(_ json: Any) -> PESchemaValidationResult {
        guard let dict = json as? [String: Any] else {
            return .invalid(.expectedObject)
        }

        var errors: [PESchemaValidationError] = []

        // Required fields
        if let mfr = dict["manufacturerId"] {
            if let arr = mfr as? [Int] {
                if arr.count != 3 {
                    errors.append(.valueOutOfRange(field: "manufacturerId", valueDescription: "\(arr.count) elements", range: "must have 3 elements"))
                }
                for (i, v) in arr.enumerated() {
                    if v < 0 || v > 127 {
                        errors.append(.valueOutOfRange(field: "manufacturerId[\(i)]", valueDescription: "\(v)", range: "0-127"))
                    }
                }
            } else {
                errors.append(.wrongFieldType(field: "manufacturerId", expected: "array of int", actual: typeName(mfr)))
            }
        } else {
            errors.append(.missingRequiredField("manufacturerId"))
        }

        if let family = dict["familyId"] {
            if let arr = family as? [Int] {
                if arr.count != 2 {
                    errors.append(.valueOutOfRange(field: "familyId", valueDescription: "\(arr.count) elements", range: "must have 2 elements"))
                }
            } else {
                errors.append(.wrongFieldType(field: "familyId", expected: "array of int", actual: typeName(family)))
            }
        } else {
            errors.append(.missingRequiredField("familyId"))
        }

        if let model = dict["modelId"] {
            if let arr = model as? [Int] {
                if arr.count != 2 {
                    errors.append(.valueOutOfRange(field: "modelId", valueDescription: "\(arr.count) elements", range: "must have 2 elements"))
                }
            } else {
                errors.append(.wrongFieldType(field: "modelId", expected: "array of int", actual: typeName(model)))
            }
        } else {
            errors.append(.missingRequiredField("modelId"))
        }

        if let version = dict["versionId"] {
            if let arr = version as? [Int] {
                if arr.count != 4 {
                    errors.append(.valueOutOfRange(field: "versionId", valueDescription: "\(arr.count) elements", range: "must have 4 elements"))
                }
            } else {
                errors.append(.wrongFieldType(field: "versionId", expected: "array of int", actual: typeName(version)))
            }
        } else {
            errors.append(.missingRequiredField("versionId"))
        }

        // Optional string fields
        for field in ["manufacturer", "family", "model", "version"] {
            if let value = dict[field], !(value is String) {
                errors.append(.wrongFieldType(field: field, expected: "string", actual: typeName(value)))
            }
        }

        if errors.isEmpty {
            return .valid
        } else if errors.count == 1 {
            return .invalid(errors[0])
        } else {
            return .invalid(.multipleErrors(errors))
        }
    }

    // MARK: - ResourceList Validation

    /// ResourceList schema:
    /// [
    ///   {
    ///     "resource": string,      // Required
    ///     "canGet": bool,          // Optional
    ///     "canSet": bool,          // Optional
    ///     "canSubscribe": bool,    // Optional
    ///     "requireResId": bool,    // Optional
    ///     "mediaTypes": [string],  // Optional
    ///     "name": string,          // Optional
    ///     "schema": object         // Optional
    ///   },
    ///   ...
    /// ]
    private func validateResourceList(_ json: Any) -> PESchemaValidationResult {
        guard let array = json as? [[String: Any]] else {
            if json is [String: Any] {
                return .invalid(.expectedArray)
            }
            return .invalid(.expectedArray)
        }

        var errors: [PESchemaValidationError] = []

        for (index, item) in array.enumerated() {
            // Required: resource
            if let resource = item["resource"] {
                if !(resource is String) {
                    errors.append(.wrongFieldType(field: "[\(index)].resource", expected: "string", actual: typeName(resource)))
                }
            } else {
                errors.append(.missingRequiredField("[\(index)].resource"))
            }

            // Optional boolean fields
            for field in ["canGet", "canSet", "canSubscribe", "requireResId"] {
                if let value = item[field], !(value is Bool) && !(value is Int) {
                    errors.append(.wrongFieldType(field: "[\(index)].\(field)", expected: "bool", actual: typeName(value)))
                }
            }

            // Optional mediaTypes array
            if let mediaTypes = item["mediaTypes"] {
                if let arr = mediaTypes as? [Any] {
                    for (i, mt) in arr.enumerated() {
                        if !(mt is String) {
                            errors.append(.wrongFieldType(field: "[\(index)].mediaTypes[\(i)]", expected: "string", actual: typeName(mt)))
                        }
                    }
                } else {
                    errors.append(.wrongFieldType(field: "[\(index)].mediaTypes", expected: "array", actual: typeName(mediaTypes)))
                }
            }
        }

        if errors.isEmpty {
            return .valid
        } else if errors.count == 1 {
            return .invalid(errors[0])
        } else {
            return .invalid(.multipleErrors(errors))
        }
    }

    // MARK: - ChannelList Validation

    /// ChannelList schema:
    /// [
    ///   {
    ///     "title": string,         // Required
    ///     "channel": int,          // Required (0-15)
    ///     "programTitle": string,  // Optional
    ///     "bankPC": [int, int, int] // Optional: [bankMSB, bankLSB, program]
    ///   },
    ///   ...
    /// ]
    private func validateChannelList(_ json: Any) -> PESchemaValidationResult {
        guard let array = json as? [[String: Any]] else {
            return .invalid(.expectedArray)
        }

        var errors: [PESchemaValidationError] = []

        for (index, item) in array.enumerated() {
            // Required: title
            if let title = item["title"] {
                if !(title is String) {
                    errors.append(.wrongFieldType(field: "[\(index)].title", expected: "string", actual: typeName(title)))
                }
            } else {
                errors.append(.missingRequiredField("[\(index)].title"))
            }

            // Required: channel
            if let channel = item["channel"] {
                if let ch = channel as? Int {
                    if ch < 0 || ch > 15 {
                        errors.append(.valueOutOfRange(field: "[\(index)].channel", valueDescription: "\(ch)", range: "0-15"))
                    }
                } else {
                    errors.append(.wrongFieldType(field: "[\(index)].channel", expected: "int", actual: typeName(channel)))
                }
            } else {
                errors.append(.missingRequiredField("[\(index)].channel"))
            }

            // Optional: bankPC
            if let bankPC = item["bankPC"] {
                if let arr = bankPC as? [Int] {
                    if arr.count != 3 {
                        errors.append(.valueOutOfRange(field: "[\(index)].bankPC", valueDescription: "\(arr.count) elements", range: "must have 3 elements [bankMSB, bankLSB, program]"))
                    }
                } else {
                    errors.append(.wrongFieldType(field: "[\(index)].bankPC", expected: "array of int", actual: typeName(bankPC)))
                }
            }
        }

        if errors.isEmpty {
            return .valid
        } else if errors.count == 1 {
            return .invalid(errors[0])
        } else {
            return .invalid(.multipleErrors(errors))
        }
    }

    // MARK: - CMList Validation (KORG Extension)

    /// CMList schema (KORG Control Map):
    /// [
    ///   {
    ///     "title": string,     // Required
    ///     "index": int         // Required
    ///   },
    ///   ...
    /// ]
    private func validateCMList(_ json: Any) -> PESchemaValidationResult {
        guard let array = json as? [[String: Any]] else {
            return .invalid(.expectedArray)
        }

        var errors: [PESchemaValidationError] = []

        for (index, item) in array.enumerated() {
            // Required: title
            if let title = item["title"] {
                if !(title is String) {
                    errors.append(.wrongFieldType(field: "[\(index)].title", expected: "string", actual: typeName(title)))
                }
            } else {
                errors.append(.missingRequiredField("[\(index)].title"))
            }

            // Required: index
            if let idx = item["index"] {
                if !(idx is Int) {
                    errors.append(.wrongFieldType(field: "[\(index)].index", expected: "int", actual: typeName(idx)))
                }
            } else {
                errors.append(.missingRequiredField("[\(index)].index"))
            }
        }

        if errors.isEmpty {
            return .valid
        } else if errors.count == 1 {
            return .invalid(errors[0])
        } else {
            return .invalid(.multipleErrors(errors))
        }
    }

    // MARK: - Helpers

    private func typeName(_ value: Any) -> String {
        if value is String { return "string" }
        if value is Int { return "int" }
        if value is Double { return "double" }
        if value is Bool { return "bool" }
        if value is [Any] { return "array" }
        if value is [String: Any] { return "object" }
        return String(describing: type(of: value))
    }
}

// MARK: - PEResponse Extension

extension PEResponse {

    /// Validate response body against expected schema
    /// - Parameter resource: Resource name to validate against
    /// - Returns: Validation result
    public func validateSchema(forResource resource: String) -> PESchemaValidationResult {
        let validator = PESchemaValidator()
        return validator.validate(decodedBody, forResource: resource)
    }

    /// Validate response body with auto-detection
    /// - Returns: Validation result
    public func validateSchemaAuto() -> PESchemaValidationResult {
        let validator = PESchemaValidator()
        return validator.validateAuto(decodedBody)
    }
}
