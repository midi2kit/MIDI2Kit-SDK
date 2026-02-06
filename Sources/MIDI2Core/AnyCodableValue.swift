//
//  AnyCodableValue.swift
//  MIDI2Kit
//
//  Type-safe container for heterogeneous JSON values.
//
//  MIDI devices may return mixed-type values in PE responses
//  (e.g., currentValues with Int and String mixed).
//  This type provides safe, Sendable handling of such values.
//

import Foundation

// MARK: - AnyCodableValue

/// A type-safe, Sendable container for heterogeneous JSON values.
///
/// Used when PE response data contains mixed types (e.g., Int, String, Bool)
/// in the same field across different entries.
///
/// ## Supported Types
///
/// - `.string(String)` - JSON strings
/// - `.int(Int)` - JSON integers
/// - `.double(Double)` - JSON floating-point numbers
/// - `.bool(Bool)` - JSON booleans
/// - `.array([AnyCodableValue])` - JSON arrays
/// - `.dictionary([String: AnyCodableValue])` - JSON objects
/// - `.null` - JSON null
///
/// ## Usage
///
/// ```swift
/// let value: AnyCodableValue = .int(42)
/// if let intVal = value.intValue {
///     print("Got integer: \(intVal)")
/// }
/// ```
public enum AnyCodableValue: Sendable, Equatable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    // MARK: - Equatable

    public static func == (lhs: AnyCodableValue, rhs: AnyCodableValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.dictionary(let a), .dictionary(let b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .string(let v):
            hasher.combine(0)
            hasher.combine(v)
        case .int(let v):
            hasher.combine(1)
            hasher.combine(v)
        case .double(let v):
            hasher.combine(2)
            hasher.combine(v)
        case .bool(let v):
            hasher.combine(3)
            hasher.combine(v)
        case .array(let v):
            hasher.combine(4)
            hasher.combine(v)
        case .dictionary(let v):
            hasher.combine(5)
            for (key, val) in v.sorted(by: { $0.key < $1.key }) {
                hasher.combine(key)
                hasher.combine(val)
            }
        case .null:
            hasher.combine(6)
        }
    }

    // MARK: - Convenience Accessors

    /// Extract as String (returns nil for non-string types)
    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    /// Extract as Int (returns nil for non-int types)
    public var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    /// Extract as Double (also converts Int to Double)
    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    /// Extract as Bool (returns nil for non-bool types)
    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    /// Extract as array (returns nil for non-array types)
    public var arrayValue: [AnyCodableValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    /// Extract as dictionary (returns nil for non-dictionary types)
    public var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let v) = self { return v }
        return nil
    }

    /// Whether this value is null
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Coerce to Int (converts String → Int, Double → Int, Bool → 0/1)
    public var coercedIntValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        case .string(let v): return Int(v)
        case .bool(let v): return v ? 1 : 0
        default: return nil
        }
    }

    /// Coerce to String (converts Int, Double, Bool to their string representation)
    public var coercedStringValue: String? {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return String(v)
        case .null: return nil
        default: return nil
        }
    }
}

// MARK: - Codable

extension AnyCodableValue: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Order matters: try bool before int (JSON true/false)
        if container.decodeNil() {
            self = .null
        } else if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else if let arrayVal = try? container.decode([AnyCodableValue].self) {
            self = .array(arrayVal)
        } else if let dictVal = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dictVal)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodableValue cannot decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - ExpressibleBy Literals

extension AnyCodableValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension AnyCodableValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension AnyCodableValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension AnyCodableValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension AnyCodableValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: AnyCodableValue...) {
        self = .array(elements)
    }
}

extension AnyCodableValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, AnyCodableValue)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension AnyCodableValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

// MARK: - CustomStringConvertible

extension AnyCodableValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let v): return "\"\(v)\""
        case .int(let v): return "\(v)"
        case .double(let v): return "\(v)"
        case .bool(let v): return "\(v)"
        case .array(let v): return "\(v)"
        case .dictionary(let v): return "\(v)"
        case .null: return "null"
        }
    }
}
