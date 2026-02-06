//
//  PEKORGTypesTests.swift
//  MIDI2Kit
//
//  Tests for KORG-specific Property Exchange types
//

import Testing
import Foundation
@testable import MIDI2Core
@testable import MIDI2PE

// MARK: - PEXParameter Tests

@Suite("PEXParameter Tests")
struct PEXParameterTests {

    @Test("Decode standard JSON format")
    func decodeStandardFormat() throws {
        let json = """
        {
            "controlcc": 11,
            "name": "Inst Level",
            "default": 100,
            "min": 0,
            "max": 127
        }
        """
        let data = json.data(using: .utf8)!
        let param = try JSONDecoder().decode(PEXParameter.self, from: data)

        #expect(param.controlCC == 11)
        #expect(param.name == "Inst Level")
        #expect(param.defaultValue == 100)
        #expect(param.minValue == 0)
        #expect(param.maxValue == 127)
        #expect(param.displayName == "Inst Level")
    }

    @Test("Decode minimal JSON with only controlcc")
    func decodeMinimalFormat() throws {
        let json = """
        {"controlcc": 74}
        """
        let data = json.data(using: .utf8)!
        let param = try JSONDecoder().decode(PEXParameter.self, from: data)

        #expect(param.controlCC == 74)
        #expect(param.name == nil)
        #expect(param.displayName == "CC74")
        #expect(param.effectiveMinValue == 0)
        #expect(param.effectiveMaxValue == 127)
    }

    @Test("Decode controlcc as string")
    func decodeControlCCAsString() throws {
        let json = """
        {"controlcc": "64", "name": "Sustain"}
        """
        let data = json.data(using: .utf8)!
        let param = try JSONDecoder().decode(PEXParameter.self, from: data)

        #expect(param.controlCC == 64)
        #expect(param.name == "Sustain")
    }

    @Test("Decode array of parameters")
    func decodeArray() throws {
        let json = """
        [
            {"controlcc": 11, "name": "Inst Level", "default": 100},
            {"controlcc": 12, "name": "Mod Fx Edit 1", "default": 64},
            {"controlcc": 100, "name": "EQ High", "default": 64}
        ]
        """
        let data = json.data(using: .utf8)!
        let params = try JSONDecoder().decode([PEXParameter].self, from: data)

        #expect(params.count == 3)
        #expect(params[0].controlCC == 11)
        #expect(params[1].controlCC == 12)
        #expect(params[2].controlCC == 100)
    }

    @Test("Value range calculation")
    func valueRange() throws {
        let param1 = PEXParameter(controlCC: 1, minValue: 10, maxValue: 100)
        #expect(param1.valueRange == 10...100)

        let param2 = PEXParameter(controlCC: 2)
        #expect(param2.valueRange == 0...127)
    }

    @Test("Array convenience extensions")
    func arrayExtensions() throws {
        let params = [
            PEXParameter(controlCC: 11, name: "Level"),
            PEXParameter(controlCC: 74, name: "Filter"),
            PEXParameter(controlCC: 1)
        ]

        #expect(params.parameter(for: 11)?.name == "Level")
        #expect(params.parameter(for: 99) == nil)
        #expect(params.displayName(for: 74) == "Filter")
        #expect(params.displayName(for: 1) == "CC1")
        #expect(params.displayName(for: 99) == "CC99")
        #expect(params.byControlCC[11]?.name == "Level")
    }

    @Test("Decode throws error when controlcc is missing")
    func decodeThrowsOnMissingControlCC() throws {
        let json = """
        {"name": "Test Parameter"}
        """
        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PEXParameter.self, from: data)
        }
    }

    @Test("Decode throws error when controlcc is invalid")
    func decodeThrowsOnInvalidControlCC() throws {
        let json = """
        {"controlcc": "not-a-number", "name": "Test"}
        """
        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PEXParameter.self, from: data)
        }
    }

    @Test("Encode and decode roundtrip")
    func encodeDecodeRoundtrip() throws {
        let original = PEXParameter(
            controlCC: 11,
            name: "Inst Level",
            defaultValue: 100,
            minValue: 0,
            maxValue: 127,
            category: "amp"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PEXParameter.self, from: encoded)

        #expect(decoded.controlCC == original.controlCC)
        #expect(decoded.name == original.name)
        #expect(decoded.defaultValue == original.defaultValue)
    }
}

// MARK: - PEXParameterValue Tests

@Suite("PEXParameterValue Tests")
struct PEXParameterValueTests {

    @Test("Decode standard format")
    func decodeStandardFormat() throws {
        let json = """
        {"controlcc": 11, "current": 85}
        """
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(PEXParameterValue.self, from: data)

        #expect(value.controlCC == 11)
        #expect(value.value == 85)
    }

    @Test("Decode alternative key names")
    func decodeAlternativeKeys() throws {
        let json = """
        {"cc": 74, "val": 64}
        """
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(PEXParameterValue.self, from: data)

        #expect(value.controlCC == 74)
        #expect(value.value == 64)
    }

    @Test("Encode and decode roundtrip")
    func encodeDecodeRoundtrip() throws {
        let original = PEXParameterValue(controlCC: 11, value: 100)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PEXParameterValue.self, from: encoded)

        #expect(decoded.controlCC == original.controlCC)
        #expect(decoded.value == original.value)
    }

    @Test("Decode throws error when controlcc is missing")
    func decodeThrowsOnMissingControlCC() throws {
        let json = """
        {"current": 85}
        """
        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PEXParameterValue.self, from: data)
        }
    }

    @Test("Decode defaults value to 0 when missing")
    func decodeDefaultsValueToZero() throws {
        let json = """
        {"controlcc": 11}
        """
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(PEXParameterValue.self, from: data)

        #expect(value.controlCC == 11)
        #expect(value.value == 0)  // 0 is valid MIDI value, so default is acceptable
    }
}

// MARK: - PEXProgramEdit Tests

@Suite("PEXProgramEdit Tests")
struct PEXProgramEditTests {

    @Test("Decode full program data")
    func decodeFullProgram() throws {
        let json = """
        {
            "name": "Grand Piano",
            "category": "Keyboard",
            "bankPC": 0,
            "bankCC": 0,
            "program": 0,
            "params": [
                {"controlcc": 11, "current": 100},
                {"controlcc": 12, "current": 64}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.name == "Grand Piano")
        #expect(program.category == "Keyboard")
        #expect(program.bankMSB == 0)
        #expect(program.bankLSB == 0)
        #expect(program.programNumber == 0)
        #expect(program.params?.count == 2)
        #expect(program.displayName == "Grand Piano")
    }

    @Test("Decode minimal program data")
    func decodeMinimalProgram() throws {
        let json = """
        {"name": "Test"}
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.name == "Test")
        #expect(program.params == nil)
        #expect(program.parameterValues.isEmpty)
    }

    @Test("Parameter values dictionary")
    func parameterValuesDictionary() throws {
        let program = PEXProgramEdit(
            name: "Test",
            params: [
                PEXParameterValue(controlCC: 11, value: 100),
                PEXParameterValue(controlCC: 74, value: 64)
            ]
        )

        let values = program.parameterValues
        #expect(values[11] == 100)
        #expect(values[74] == 64)
        #expect(values[1] == nil)
    }

    @Test("Get value for specific CC")
    func valueForCC() throws {
        let program = PEXProgramEdit(
            params: [
                PEXParameterValue(controlCC: 11, value: 100),
                PEXParameterValue(controlCC: 74, value: 64)
            ]
        )

        #expect(program.value(for: 11) == 100)
        #expect(program.value(for: 74) == 64)
        #expect(program.value(for: 1) == nil)
    }

    @Test("Decode with alternative params key")
    func decodeAlternativeParamsKey() throws {
        let json = """
        {
            "name": "Test",
            "parameters": [
                {"controlcc": 11, "current": 100}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.params?.count == 1)
        #expect(program.params?[0].controlCC == 11)
    }
}

// MARK: - PEXProgramEdit bankPC Array Tests

@Suite("PEXProgramEdit bankPC Array Tests")
struct PEXProgramEditBankPCTests {

    @Test("Decode bankPC as 3-element array")
    func decodeBankPCArray3() throws {
        let json = """
        {
            "name": "Piano",
            "bankPC": [0, 1, 5],
            "params": [{"controlcc": 11, "current": 100}]
        }
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.bankMSB == 0)
        #expect(program.bankLSB == 1)
        #expect(program.programNumber == 5)
    }

    @Test("Decode bankPC as 2-element array")
    func decodeBankPCArray2() throws {
        let json = """
        {"name": "Test", "bankPC": [3, 7]}
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.bankMSB == 3)
        #expect(program.bankLSB == 7)
        #expect(program.programNumber == nil)
    }

    @Test("Decode bankPC as 1-element array")
    func decodeBankPCArray1() throws {
        let json = """
        {"name": "Test", "bankPC": [5]}
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.bankMSB == 5)
        #expect(program.bankLSB == nil)
    }

    @Test("Empty bankPC array is handled gracefully")
    func decodeBankPCEmptyArray() throws {
        let json = """
        {"name": "Test", "bankPC": []}
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.bankMSB == nil)
        #expect(program.bankLSB == nil)
    }

    @Test("Explicit program: 0 is not overwritten by bankPC array")
    func explicitProgramZeroProtection() throws {
        let json = """
        {"name": "Test", "program": 0, "bankPC": [0, 0, 42]}
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.programNumber == 0)
        #expect(program.bankMSB == 0)
        #expect(program.bankLSB == 0)
    }

    @Test("bankPC as Int still works (standard format)")
    func decodeBankPCAsInt() throws {
        let json = """
        {"name": "Test", "bankPC": 5, "bankCC": 3, "program": 10}
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.bankMSB == 5)
        #expect(program.bankLSB == 3)
        #expect(program.programNumber == 10)
    }

    @Test("bankPC array with program not set uses array value")
    func bankPCArraySetsProgram() throws {
        let json = """
        {"name": "Test", "bankPC": [1, 2, 99]}
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.programNumber == 99)
    }

    @Test("Out-of-range values are recorded without throwing")
    func outOfRangeValues() throws {
        let json = """
        {"name": "Test", "bankPC": [200, 300, 999]}
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.bankMSB == 200)
        #expect(program.bankLSB == 300)
        #expect(program.programNumber == 999)
    }
}

// MARK: - PEXCurrentValue Tests

@Suite("PEXCurrentValue Tests")
struct PEXCurrentValueTests {

    @Test("Decode with integer value")
    func decodeIntValue() throws {
        let json = """
        {"controlcc": 11, "current": 100}
        """
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(PEXCurrentValue.self, from: data)

        #expect(value.controlCC == 11)
        #expect(value.value == .int(100))
        #expect(value.intValue == 100)
    }

    @Test("Decode with string value")
    func decodeStringValue() throws {
        let json = """
        {"controlcc": 12, "current": "High"}
        """
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(PEXCurrentValue.self, from: data)

        #expect(value.controlCC == 12)
        #expect(value.value == .string("High"))
        #expect(value.stringValue == "High")
        #expect(value.intValue == nil)
    }

    @Test("Decode with boolean value")
    func decodeBoolValue() throws {
        let json = """
        {"controlcc": 64, "current": true}
        """
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(PEXCurrentValue.self, from: data)

        #expect(value.controlCC == 64)
        #expect(value.value == .bool(true))
    }

    @Test("Decode with null value defaults to null")
    func decodeNullValue() throws {
        let json = """
        {"controlcc": 50, "current": null}
        """
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(PEXCurrentValue.self, from: data)

        #expect(value.controlCC == 50)
        #expect(value.value == .null)
    }

    @Test("Decode missing value defaults to null")
    func decodeMissingValue() throws {
        let json = """
        {"controlcc": 50}
        """
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(PEXCurrentValue.self, from: data)

        #expect(value.controlCC == 50)
        #expect(value.value == .null)
    }

    @Test("Decode array of mixed-type currentValues")
    func decodeCurrentValuesArray() throws {
        let json = """
        [
            {"controlcc": 11, "current": 100},
            {"controlcc": 12, "current": "High"},
            {"controlcc": 64, "current": true}
        ]
        """
        let data = json.data(using: .utf8)!
        let values = try JSONDecoder().decode([PEXCurrentValue].self, from: data)

        #expect(values.count == 3)
        #expect(values[0].value == .int(100))
        #expect(values[1].value == .string("High"))
        #expect(values[2].value == .bool(true))
    }

    @Test("Decode throws on missing controlcc")
    func throwsOnMissingCC() {
        let json = """
        {"current": 100}
        """
        let data = json.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PEXCurrentValue.self, from: data)
        }
    }
}

// MARK: - PEXProgramEdit currentValues Tests

@Suite("PEXProgramEdit currentValues Tests")
struct PEXProgramEditCurrentValuesTests {

    @Test("Decode with currentValues key")
    func decodeCurrentValues() throws {
        let json = """
        {
            "name": "Grand Piano",
            "currentValues": [
                {"controlcc": 11, "current": 100},
                {"controlcc": 12, "current": "High"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let program = try JSONDecoder().decode(PEXProgramEdit.self, from: data)

        #expect(program.currentValues?.count == 2)
        #expect(program.currentValues?[0].value == .int(100))
        #expect(program.currentValues?[1].value == .string("High"))
    }

    @Test("allValues merges params and currentValues")
    func allValuesMerge() throws {
        let program = PEXProgramEdit(
            name: "Test",
            params: [
                PEXParameterValue(controlCC: 11, value: 100),
                PEXParameterValue(controlCC: 74, value: 64)
            ],
            currentValues: [
                PEXCurrentValue(controlCC: 74, value: .string("Override")),
                PEXCurrentValue(controlCC: 12, value: .int(50))
            ]
        )

        let all = program.allValues
        #expect(all[11] == .int(100))       // From params
        #expect(all[74] == .string("Override")) // currentValues overrides params
        #expect(all[12] == .int(50))        // From currentValues only
    }

    @Test("allValues is empty when both params and currentValues are nil")
    func allValuesEmpty() {
        let program = PEXProgramEdit(name: "Empty")
        #expect(program.allValues.isEmpty)
    }
}

// MARK: - MIDIVendor Tests

@Suite("MIDIVendor Tests")
struct MIDIVendorTests {

    @Test("Detect KORG from manufacturer name")
    func detectKORG() {
        #expect(MIDIVendor.detect(from: "KORG Inc.") == .korg)
        #expect(MIDIVendor.detect(from: "KORG") == .korg)
        #expect(MIDIVendor.detect(from: "korg") == .korg)
    }

    @Test("Detect other vendors")
    func detectOtherVendors() {
        #expect(MIDIVendor.detect(from: "Roland Corporation") == .roland)
        #expect(MIDIVendor.detect(from: "Yamaha") == .yamaha)
        #expect(MIDIVendor.detect(from: "Native Instruments") == .native_instruments)
    }

    @Test("Detect unknown vendor")
    func detectUnknown() {
        #expect(MIDIVendor.detect(from: "Unknown Manufacturer") == .unknown)
        #expect(MIDIVendor.detect(from: nil) == .unknown)
        #expect(MIDIVendor.detect(from: "") == .unknown)
    }

    @Test("Manufacturer IDs")
    func manufacturerIDs() {
        #expect(MIDIVendor.korg.manufacturerID == [0x42])
        #expect(MIDIVendor.roland.manufacturerID == [0x41])
        #expect(MIDIVendor.yamaha.manufacturerID == [0x43])
        #expect(MIDIVendor.unknown.manufacturerID == nil)
    }
}

// MARK: - VendorOptimizationConfig Tests

@Suite("VendorOptimizationConfig Tests")
struct VendorOptimizationConfigTests {

    @Test("Default config has KORG optimizations")
    func defaultConfig() {
        let config = VendorOptimizationConfig.default

        #expect(config.isEnabled(.skipResourceListWhenPossible, for: .korg))
        #expect(config.isEnabled(.useXParameterListAsWarmup, for: .korg))
        #expect(config.isEnabled(.preferVendorResources, for: .korg))
        #expect(!config.isEnabled(.extendedMultiChunkTimeout, for: .korg))
    }

    @Test("None config has no optimizations")
    func noneConfig() {
        let config = VendorOptimizationConfig.none

        #expect(!config.isEnabled(.skipResourceListWhenPossible, for: .korg))
        #expect(!config.isEnabled(.skipResourceListWhenPossible, for: .roland))
    }

    @Test("Enable and disable optimizations")
    func enableDisable() {
        var config = VendorOptimizationConfig.none

        config.enable(.skipResourceListWhenPossible, for: .korg)
        #expect(config.isEnabled(.skipResourceListWhenPossible, for: .korg))

        config.disable(.skipResourceListWhenPossible, for: .korg)
        #expect(!config.isEnabled(.skipResourceListWhenPossible, for: .korg))
    }

    @Test("Optimizations are vendor-specific")
    func vendorSpecific() {
        let config = VendorOptimizationConfig.default

        #expect(config.isEnabled(.skipResourceListWhenPossible, for: .korg))
        #expect(!config.isEnabled(.skipResourceListWhenPossible, for: .roland))
        #expect(!config.isEnabled(.skipResourceListWhenPossible, for: .yamaha))
    }
}
