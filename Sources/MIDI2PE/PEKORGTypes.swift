//
//  PEKORGTypes.swift
//  MIDI2Kit
//
//  KORG-specific Property Exchange types
//
//  These types support KORG's proprietary PE resources:
//  - X-ParameterList: CC parameter definitions with names and ranges
//  - X-ProgramEdit: Current program data with parameter values
//

import Foundation

// MARK: - X-ParameterList Types

/// KORG X-ParameterList entry
///
/// Represents a single parameter from KORG's `X-ParameterList` resource.
/// This resource provides CC name discovery, allowing applications to display
/// meaningful names like "Inst Level" instead of "CC11".
///
/// ## JSON Format
///
/// ```json
/// {
///   "controlcc": 11,
///   "name": "Inst Level",
///   "default": 100,
///   "min": 0,
///   "max": 127
/// }
/// ```
///
/// ## Usage
///
/// ```swift
/// let params: [PEXParameter] = try await client.getXParameterList(from: muid)
/// for param in params {
///     print("\(param.displayName): CC\(param.controlCC)")
/// }
/// ```
public struct PEXParameter: Sendable, Codable, Identifiable, Hashable {
    public var id: Int { controlCC }

    /// CC number (0-127)
    public let controlCC: Int

    /// Human-readable parameter name
    public let name: String?

    /// Default value (0-127)
    public let defaultValue: Int?

    /// Minimum value (default: 0)
    public let minValue: Int?

    /// Maximum value (default: 127)
    public let maxValue: Int?

    /// Parameter category (e.g., "filter", "amp", "effect")
    public let category: String?

    enum CodingKeys: String, CodingKey {
        case controlCC = "controlcc"
        case name
        case defaultValue = "default"
        case minValue = "min"
        case maxValue = "max"
        case category
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // controlcc can be Int or String (required field)
        if let intValue = try? container.decode(Int.self, forKey: .controlCC) {
            controlCC = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .controlCC),
                  let parsed = Int(stringValue) {
            controlCC = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .controlCC,
                in: container,
                debugDescription: "controlcc must be an Int or String representing an Int"
            )
        }

        name = try container.decodeIfPresent(String.self, forKey: .name)
        defaultValue = try container.decodeIfPresent(Int.self, forKey: .defaultValue)
        minValue = try container.decodeIfPresent(Int.self, forKey: .minValue)
        maxValue = try container.decodeIfPresent(Int.self, forKey: .maxValue)
        category = try container.decodeIfPresent(String.self, forKey: .category)
    }

    public init(
        controlCC: Int,
        name: String? = nil,
        defaultValue: Int? = nil,
        minValue: Int? = nil,
        maxValue: Int? = nil,
        category: String? = nil
    ) {
        self.controlCC = controlCC
        self.name = name
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.category = category
    }

    /// Display name (name or "CC{number}")
    public var displayName: String {
        name ?? "CC\(controlCC)"
    }

    /// Effective minimum value (defaults to 0)
    public var effectiveMinValue: Int {
        minValue ?? 0
    }

    /// Effective maximum value (defaults to 127)
    public var effectiveMaxValue: Int {
        maxValue ?? 127
    }

    /// Value range
    public var valueRange: ClosedRange<Int> {
        effectiveMinValue...effectiveMaxValue
    }
}

// MARK: - X-ProgramEdit Types

/// KORG X-ProgramEdit parameter value
///
/// Represents a single parameter value in the current program.
public struct PEXParameterValue: Sendable, Codable, Identifiable, Hashable {
    public var id: Int { controlCC }

    /// CC number
    public let controlCC: Int

    /// Current value (0-127)
    public let value: Int

    enum CodingKeys: String, CodingKey {
        case controlCC = "controlcc"
        case value = "current"
    }

    // Alternative keys for decoding only
    private enum AlternativeKeys: String, CodingKey {
        case cc
        case val
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let altContainer = try? decoder.container(keyedBy: AlternativeKeys.self)

        // Try different key names for controlCC (required field)
        if let intValue = try? container.decode(Int.self, forKey: .controlCC) {
            controlCC = intValue
        } else if let intValue = try? altContainer?.decode(Int.self, forKey: .cc) {
            controlCC = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .controlCC),
                  let parsed = Int(stringValue) {
            controlCC = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .controlCC,
                in: container,
                debugDescription: "controlcc or cc must be present as Int or String"
            )
        }

        // Try different key names for value (default to 0 if missing, as 0 is valid MIDI value)
        if let intValue = try? container.decode(Int.self, forKey: .value) {
            value = intValue
        } else if let intValue = try? altContainer?.decode(Int.self, forKey: .val) {
            value = intValue
        } else {
            value = 0  // 0 is a valid MIDI value, so default is acceptable
        }
    }

    public init(controlCC: Int, value: Int) {
        self.controlCC = controlCC
        self.value = value
    }
}

/// KORG X-ProgramEdit data
///
/// Represents the current program state from KORG's `X-ProgramEdit` resource.
/// This resource provides:
/// - Current program name and metadata
/// - Current parameter values for all CCs
///
/// ## JSON Format
///
/// ```json
/// {
///   "name": "Grand Piano",
///   "category": "Keyboard",
///   "params": [
///     {"controlcc": 11, "current": 100},
///     {"controlcc": 12, "current": 64}
///   ]
/// }
/// ```
///
/// ## Usage
///
/// ```swift
/// let program = try await client.getXProgramEdit(from: muid)
/// print("Program: \(program.displayName)")
/// for (cc, value) in program.parameterValues {
///     print("CC\(cc) = \(value)")
/// }
/// ```
public struct PEXProgramEdit: Sendable, Codable {
    /// Program name
    public let name: String?

    /// Program category (e.g., "Keyboard", "Bass", "Pad")
    public let category: String?

    /// Bank MSB
    public let bankMSB: Int?

    /// Bank LSB
    public let bankLSB: Int?

    /// Program number
    public let programNumber: Int?

    /// Raw parameter values array
    public let params: [PEXParameterValue]?

    enum CodingKeys: String, CodingKey {
        case name
        case category
        case bankMSB = "bankPC"
        case bankLSB = "bankCC"
        case programNumber = "program"
        case params
    }

    // Alternative keys for decoding only
    private enum AlternativeKeys: String, CodingKey {
        case parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let altContainer = try? decoder.container(keyedBy: AlternativeKeys.self)

        name = try container.decodeIfPresent(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        bankMSB = try container.decodeIfPresent(Int.self, forKey: .bankMSB)
        bankLSB = try container.decodeIfPresent(Int.self, forKey: .bankLSB)
        programNumber = try container.decodeIfPresent(Int.self, forKey: .programNumber)

        // Try different key names for params
        if let paramsValue = try? container.decode([PEXParameterValue].self, forKey: .params) {
            params = paramsValue
        } else if let paramsValue = try? altContainer?.decode([PEXParameterValue].self, forKey: .parameters) {
            params = paramsValue
        } else {
            params = nil
        }
    }

    public init(
        name: String? = nil,
        category: String? = nil,
        bankMSB: Int? = nil,
        bankLSB: Int? = nil,
        programNumber: Int? = nil,
        params: [PEXParameterValue]? = nil
    ) {
        self.name = name
        self.category = category
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.programNumber = programNumber
        self.params = params
    }

    /// Display name (name or "Unknown Program")
    public var displayName: String {
        name ?? "Unknown Program"
    }

    /// Parameter values as dictionary (CC -> value)
    public var parameterValues: [Int: Int] {
        guard let params = params else { return [:] }
        return Dictionary(uniqueKeysWithValues: params.map { ($0.controlCC, $0.value) })
    }

    /// Get value for a specific CC
    public func value(for cc: Int) -> Int? {
        params?.first { $0.controlCC == cc }?.value
    }
}

// MARK: - Vendor Identification

/// Known MIDI device vendors
///
/// Used for vendor-specific optimizations and feature detection.
public enum MIDIVendor: String, Sendable, CaseIterable {
    case korg = "KORG"
    case roland = "Roland"
    case yamaha = "Yamaha"
    case native_instruments = "Native Instruments"
    case arturia = "Arturia"
    case novation = "Novation"
    case akai = "Akai"
    case unknown = "Unknown"

    /// Manufacturer ID bytes (first 3 bytes of SysEx manufacturer ID)
    public var manufacturerID: [UInt8]? {
        switch self {
        case .korg: return [0x42]
        case .roland: return [0x41]
        case .yamaha: return [0x43]
        case .native_instruments: return [0x00, 0x21, 0x09]
        case .arturia: return [0x00, 0x20, 0x6B]
        case .novation: return [0x00, 0x20, 0x29]
        case .akai: return [0x47]
        case .unknown: return nil
        }
    }

    /// Detect vendor from manufacturer name string
    public static func detect(from manufacturerName: String?) -> MIDIVendor {
        guard let name = manufacturerName?.uppercased() else { return .unknown }

        for vendor in MIDIVendor.allCases where vendor != .unknown {
            if name.contains(vendor.rawValue.uppercased()) {
                return vendor
            }
        }

        return .unknown
    }
}

// MARK: - Vendor Optimizations

/// Vendor-specific PE optimization strategies
///
/// These optimizations can significantly improve performance for specific vendors.
public enum VendorOptimization: String, Sendable, CaseIterable {
    /// Skip ResourceList fetch when possible
    ///
    /// KORG devices respond to `X-ParameterList` without requiring ResourceList.
    /// Using this optimization can reduce fetch time by 99%+ (16s → 144ms).
    case skipResourceListWhenPossible

    /// Use X-ParameterList as implicit warmup
    ///
    /// Fetching X-ParameterList first acts as a warmup for the BLE connection,
    /// making subsequent requests faster and more reliable.
    case useXParameterListAsWarmup

    /// Prefer vendor-specific resources over standard ones
    ///
    /// Use X-ParameterList instead of ChCtrlList when available.
    case preferVendorResources

    /// Extended timeout for multi-chunk responses
    ///
    /// Some devices need longer timeouts for large responses.
    case extendedMultiChunkTimeout
}

/// Vendor optimization configuration
public struct VendorOptimizationConfig: Sendable {
    /// Active optimizations per vendor
    public var optimizations: [MIDIVendor: Set<VendorOptimization>]

    /// Default optimizations for known vendors
    public static let `default` = VendorOptimizationConfig(optimizations: [
        .korg: [.skipResourceListWhenPossible, .useXParameterListAsWarmup, .preferVendorResources]
    ])

    /// No optimizations
    public static let none = VendorOptimizationConfig(optimizations: [:])

    public init(optimizations: [MIDIVendor: Set<VendorOptimization>] = [:]) {
        self.optimizations = optimizations
    }

    /// Check if an optimization is enabled for a vendor
    public func isEnabled(_ optimization: VendorOptimization, for vendor: MIDIVendor) -> Bool {
        optimizations[vendor]?.contains(optimization) ?? false
    }

    /// Enable an optimization for a vendor
    public mutating func enable(_ optimization: VendorOptimization, for vendor: MIDIVendor) {
        if optimizations[vendor] == nil {
            optimizations[vendor] = []
        }
        optimizations[vendor]?.insert(optimization)
    }

    /// Disable an optimization for a vendor
    public mutating func disable(_ optimization: VendorOptimization, for vendor: MIDIVendor) {
        optimizations[vendor]?.remove(optimization)
    }
}
