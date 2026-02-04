//
//  PEPayloadValidator.swift
//  MIDI2Kit
//
//  Payload validation protocol and registry for Property Exchange SET operations
//
//  This module provides a pre-SET validation layer to catch errors before
//  sending data to MIDI devices. It integrates with the existing PESchemaValidator
//  for schema-based validation while supporting custom validators for specific resources.
//

import Foundation

// MARK: - Validation Errors

/// Errors that can occur during payload validation before SET
public enum PEPayloadValidationError: Error, Sendable, Equatable {
    /// JSON parsing failed
    case invalidJSON(String)

    /// Schema validation failed
    case schemaViolation([PESchemaValidationError])

    /// Custom validation rule failed
    case customValidation(String)

    /// Payload is too large
    case payloadTooLarge(size: Int, maxSize: Int)

    /// Required field is missing
    case missingField(String)

    /// Field value is invalid
    case invalidFieldValue(field: String, reason: String)
}

extension PEPayloadValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidJSON(let error):
            return "Invalid JSON: \(error)"
        case .schemaViolation(let errors):
            return "Schema validation failed: \(errors.map { $0.description }.joined(separator: ", "))"
        case .customValidation(let message):
            return "Validation failed: \(message)"
        case .payloadTooLarge(let size, let maxSize):
            return "Payload too large: \(size) bytes (max: \(maxSize))"
        case .missingField(let field):
            return "Missing required field: \(field)"
        case .invalidFieldValue(let field, let reason):
            return "Invalid field '\(field)': \(reason)"
        }
    }
}

// MARK: - Equatable for PESchemaValidationError

extension PESchemaValidationError: Equatable {
    public static func == (lhs: PESchemaValidationError, rhs: PESchemaValidationError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidJSON, .invalidJSON):
            return true
        case (.expectedObject, .expectedObject):
            return true
        case (.expectedArray, .expectedArray):
            return true
        case (.missingRequiredField(let a), .missingRequiredField(let b)):
            return a == b
        case (.wrongFieldType(let f1, let e1, let a1), .wrongFieldType(let f2, let e2, let a2)):
            return f1 == f2 && e1 == e2 && a1 == a2
        case (.valueOutOfRange(let f1, let v1, let r1), .valueOutOfRange(let f2, let v2, let r2)):
            return f1 == f2 && v1 == v2 && r1 == r2
        case (.unknownResource(let a), .unknownResource(let b)):
            return a == b
        case (.multipleErrors(let a), .multipleErrors(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Payload Validator Protocol

/// Protocol for validating Property Exchange payloads before SET operations
///
/// Implement this protocol to create custom validators for specific resources.
/// Register validators with `PEPayloadValidatorRegistry` for automatic validation.
///
/// ## Example
///
/// ```swift
/// struct VolumeValidator: PEPayloadValidator {
///     let resource = "Volume"
///
///     func validate(_ data: Data) throws {
///         let json = try JSONSerialization.jsonObject(with: data)
///         guard let dict = json as? [String: Any],
///               let level = dict["level"] as? Int else {
///             throw PEPayloadValidationError.missingField("level")
///         }
///         guard (0...127).contains(level) else {
///             throw PEPayloadValidationError.invalidFieldValue(
///                 field: "level",
///                 reason: "must be 0-127"
///             )
///         }
///     }
/// }
/// ```
public protocol PEPayloadValidator: Sendable {
    /// Resource name this validator applies to
    var resource: String { get }

    /// Validate payload data before SET
    /// - Parameter data: JSON data to validate
    /// - Throws: `PEPayloadValidationError` if validation fails
    func validate(_ data: Data) throws
}

// MARK: - Validator Registry

/// Registry for payload validators
///
/// Thread-safe registry that maps resource names to validators.
/// Use with `PEManager.payloadValidatorRegistry` for automatic validation.
///
/// ## Example
///
/// ```swift
/// let registry = PEPayloadValidatorRegistry()
/// await registry.register(VolumeValidator())
/// await registry.register(ProgramNameValidator())
///
/// // Assign to PEManager for automatic validation
/// peManager.payloadValidatorRegistry = registry
/// ```
public actor PEPayloadValidatorRegistry {

    /// Registered validators by resource name
    private var validators: [String: any PEPayloadValidator] = [:]

    /// Whether to use schema-based validation as fallback
    private var useSchemaFallback: Bool

    /// Schema validator for fallback validation
    private let schemaValidator = PESchemaValidator()

    /// Maximum payload size (default: 64KB)
    public var maxPayloadSize: Int = 65536

    public init(useSchemaFallback: Bool = true) {
        self.useSchemaFallback = useSchemaFallback
    }

    /// Register a validator for a resource
    ///
    /// Overwrites any existing validator for the same resource.
    /// - Parameter validator: Validator to register
    public func register(_ validator: any PEPayloadValidator) {
        validators[validator.resource] = validator
    }

    /// Unregister validator for a resource
    /// - Parameter resource: Resource name
    public func unregister(_ resource: String) {
        validators.removeValue(forKey: resource)
    }

    /// Get validator for a resource
    /// - Parameter resource: Resource name
    /// - Returns: Registered validator, or nil if none
    public func validator(for resource: String) -> (any PEPayloadValidator)? {
        validators[resource]
    }

    /// Check if a validator is registered for a resource
    public func hasValidator(for resource: String) -> Bool {
        validators[resource] != nil
    }

    /// All registered resource names
    public var registeredResources: [String] {
        Array(validators.keys)
    }

    /// Validate payload for a resource
    ///
    /// Validation order:
    /// 1. Check payload size
    /// 2. Use registered validator if available
    /// 3. Fall back to schema validation if enabled
    ///
    /// - Parameters:
    ///   - data: Payload data to validate
    ///   - resource: Target resource name
    /// - Throws: `PEPayloadValidationError` if validation fails
    public func validate(_ data: Data, for resource: String) throws {
        // Check size limit
        if data.count > maxPayloadSize {
            throw PEPayloadValidationError.payloadTooLarge(
                size: data.count,
                maxSize: maxPayloadSize
            )
        }

        // Use registered validator if available
        if let validator = validators[resource] {
            try validator.validate(data)
            return
        }

        // Fall back to schema validation
        if useSchemaFallback {
            let result = schemaValidator.validate(data, forResource: resource)
            if !result.isValid {
                throw PEPayloadValidationError.schemaViolation(result.errors)
            }
        }
    }

    /// Enable or disable schema fallback
    public func setSchemaFallback(_ enabled: Bool) {
        useSchemaFallback = enabled
    }
}

// MARK: - Schema-Based Validator

/// Validator that uses PESchemaValidator for validation
///
/// This is a convenience wrapper around PESchemaValidator for use
/// as a PEPayloadValidator in the registry.
public struct PESchemaBasedValidator: PEPayloadValidator {
    public let resource: String
    private let schemaValidator = PESchemaValidator()

    public init(resource: String) {
        self.resource = resource
    }

    public func validate(_ data: Data) throws {
        let result = schemaValidator.validate(data, forResource: resource)
        if !result.isValid {
            throw PEPayloadValidationError.schemaViolation(result.errors)
        }
    }
}

// MARK: - Common Validators

/// Built-in validators for common PE resources
public enum PEBuiltinValidators {

    /// DeviceInfo validator
    public static let deviceInfo = PESchemaBasedValidator(resource: "DeviceInfo")

    /// ResourceList validator
    public static let resourceList = PESchemaBasedValidator(resource: "ResourceList")

    /// ChannelList validator
    public static let channelList = PESchemaBasedValidator(resource: "ChannelList")

    /// CMList validator (KORG)
    public static let cmList = PESchemaBasedValidator(resource: "CMList")

    /// All built-in validators
    public static var all: [any PEPayloadValidator] {
        [deviceInfo, resourceList, channelList, cmList]
    }
}
