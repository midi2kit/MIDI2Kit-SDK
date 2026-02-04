//
//  PEControllerTypes.swift
//  MIDI2Kit
//
//  Property Exchange Controller and Program Types
//

import Foundation

// MARK: - Controller Definition

/// Controller definition from ChCtrlList resource
public struct PEControllerDef: Sendable, Codable, Identifiable {
    public var id: Int { ctrlIndex }

    /// Controller index (CC number for standard CCs)
    public let ctrlIndex: Int

    /// Human-readable name
    public let name: String?

    /// Controller type
    public let ctrlType: String?

    /// Minimum value
    public let minValue: Int?

    /// Maximum value
    public let maxValue: Int?

    /// Default value
    public let defaultValue: Int?

    /// Step size
    public let stepCount: Int?

    /// Value labels
    public let valueList: [String]?

    /// Unit string (e.g., "dB", "Hz")
    public let units: String?

    enum CodingKeys: String, CodingKey {
        case ctrlIndex
        case name
        case ctrlType
        case minValue
        case maxValue
        case defaultValue = "default"
        case stepCount
        case valueList
        case units
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // ctrlIndex can be Int or String
        if let intValue = try? container.decode(Int.self, forKey: .ctrlIndex) {
            ctrlIndex = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .ctrlIndex),
                  let parsed = Int(stringValue) {
            ctrlIndex = parsed
        } else {
            ctrlIndex = 0
        }

        name = try container.decodeIfPresent(String.self, forKey: .name)
        ctrlType = try container.decodeIfPresent(String.self, forKey: .ctrlType)
        minValue = try container.decodeIfPresent(Int.self, forKey: .minValue)
        maxValue = try container.decodeIfPresent(Int.self, forKey: .maxValue)
        defaultValue = try container.decodeIfPresent(Int.self, forKey: .defaultValue)
        stepCount = try container.decodeIfPresent(Int.self, forKey: .stepCount)
        valueList = try container.decodeIfPresent([String].self, forKey: .valueList)
        units = try container.decodeIfPresent(String.self, forKey: .units)
    }

    public init(
        ctrlIndex: Int,
        name: String? = nil,
        ctrlType: String? = nil,
        minValue: Int? = nil,
        maxValue: Int? = nil,
        defaultValue: Int? = nil,
        stepCount: Int? = nil,
        valueList: [String]? = nil,
        units: String? = nil
    ) {
        self.ctrlIndex = ctrlIndex
        self.name = name
        self.ctrlType = ctrlType
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.stepCount = stepCount
        self.valueList = valueList
        self.units = units
    }

    /// Display name (name or "CC{index}")
    public var displayName: String {
        name ?? "CC\(ctrlIndex)"
    }
}

// MARK: - Program Definition

/// Program/preset definition from ProgramList resource
public struct PEProgramDef: Sendable, Codable, Identifiable {
    public var id: String { "\(bankMSB)-\(bankLSB)-\(programNumber)" }

    /// Program number (0-127)
    public let programNumber: Int

    /// Bank MSB (0-127)
    public let bankMSB: Int

    /// Bank LSB (0-127)
    public let bankLSB: Int

    /// Program name
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case programNumber = "program"
        case bankMSB = "bankPC"
        case bankLSB = "bankCC"
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        programNumber = try container.decodeIfPresent(Int.self, forKey: .programNumber) ?? 0
        bankMSB = try container.decodeIfPresent(Int.self, forKey: .bankMSB) ?? 0
        bankLSB = try container.decodeIfPresent(Int.self, forKey: .bankLSB) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    public init(
        programNumber: Int,
        bankMSB: Int = 0,
        bankLSB: Int = 0,
        name: String? = nil
    ) {
        self.programNumber = programNumber
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.name = name
    }

    /// Display name (name or program number)
    public var displayName: String {
        name ?? "Program \(programNumber)"
    }
}
