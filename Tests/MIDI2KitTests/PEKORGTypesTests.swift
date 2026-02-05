//
//  PEKORGTypesTests.swift
//  MIDI2Kit
//
//  Tests for KORG-specific Property Exchange types
//

import Testing
import Foundation
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
