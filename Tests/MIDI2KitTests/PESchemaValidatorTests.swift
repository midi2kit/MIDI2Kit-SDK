//
//  PESchemaValidatorTests.swift
//  MIDI2KitTests
//
//  Tests for PE JSON Schema validation
//

import Testing
import Foundation
@testable import MIDI2PE

@Suite("PE Schema Validator Tests")
struct PESchemaValidatorTests {

    let validator = PESchemaValidator()

    // MARK: - DeviceInfo Tests

    @Test("Valid DeviceInfo passes validation")
    func validDeviceInfo() {
        let json = """
        {
            "manufacturerId": [0, 72, 7],
            "familyId": [1, 0],
            "modelId": [2, 0],
            "versionId": [1, 0, 0, 0],
            "manufacturer": "Test Corp",
            "family": "Test Family",
            "model": "Test Model",
            "version": "1.0.0"
        }
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "DeviceInfo")
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    @Test("DeviceInfo with missing manufacturerId fails")
    func deviceInfoMissingManufacturer() {
        let json = """
        {
            "familyId": [1, 0],
            "modelId": [2, 0],
            "versionId": [1, 0, 0, 0]
        }
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "DeviceInfo")
        #expect(!result.isValid)
        #expect(result.errors.contains { error in
            if case .missingRequiredField("manufacturerId") = error { return true }
            return false
        })
    }

    @Test("DeviceInfo with wrong type manufacturerId fails")
    func deviceInfoWrongTypeManufacturer() {
        let json = """
        {
            "manufacturerId": "invalid",
            "familyId": [1, 0],
            "modelId": [2, 0],
            "versionId": [1, 0, 0, 0]
        }
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "DeviceInfo")
        #expect(!result.isValid)
    }

    @Test("DeviceInfo with wrong array length fails")
    func deviceInfoWrongArrayLength() {
        let json = """
        {
            "manufacturerId": [0, 72],
            "familyId": [1, 0],
            "modelId": [2, 0],
            "versionId": [1, 0, 0, 0]
        }
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "DeviceInfo")
        #expect(!result.isValid)
    }

    @Test("DeviceInfo minimal (required fields only) passes")
    func deviceInfoMinimal() {
        let json = """
        {
            "manufacturerId": [0, 72, 7],
            "familyId": [1, 0],
            "modelId": [2, 0],
            "versionId": [1, 0, 0, 0]
        }
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "DeviceInfo")
        #expect(result.isValid)
    }

    // MARK: - ResourceList Tests

    @Test("Valid ResourceList passes validation")
    func validResourceList() {
        let json = """
        [
            {
                "resource": "DeviceInfo",
                "canGet": true,
                "canSet": false,
                "canSubscribe": false
            },
            {
                "resource": "ChannelList",
                "canGet": true,
                "canSet": true,
                "requireResId": true
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "ResourceList")
        #expect(result.isValid)
    }

    @Test("ResourceList missing resource field fails")
    func resourceListMissingResource() {
        let json = """
        [
            {
                "canGet": true,
                "canSet": false
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "ResourceList")
        #expect(!result.isValid)
    }

    @Test("ResourceList with wrong type resource fails")
    func resourceListWrongTypeResource() {
        let json = """
        [
            {
                "resource": 123,
                "canGet": true
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "ResourceList")
        #expect(!result.isValid)
    }

    @Test("Empty ResourceList passes")
    func emptyResourceList() {
        let json = "[]".data(using: .utf8)!

        let result = validator.validate(json, forResource: "ResourceList")
        #expect(result.isValid)
    }

    @Test("ResourceList with mediaTypes array passes")
    func resourceListWithMediaTypes() {
        let json = """
        [
            {
                "resource": "CustomResource",
                "mediaTypes": ["application/json", "text/plain"]
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "ResourceList")
        #expect(result.isValid)
    }

    // MARK: - ChannelList Tests

    @Test("Valid ChannelList passes validation")
    func validChannelList() {
        let json = """
        [
            {
                "title": "Piano",
                "channel": 0,
                "programTitle": "Grand Piano",
                "bankPC": [0, 0, 0]
            },
            {
                "title": "Bass",
                "channel": 1
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "ChannelList")
        #expect(result.isValid)
    }

    @Test("ChannelList missing title fails")
    func channelListMissingTitle() {
        let json = """
        [
            {
                "channel": 0
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "ChannelList")
        #expect(!result.isValid)
    }

    @Test("ChannelList with invalid channel fails")
    func channelListInvalidChannel() {
        let json = """
        [
            {
                "title": "Piano",
                "channel": 16
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "ChannelList")
        #expect(!result.isValid)
    }

    @Test("ChannelList with wrong bankPC length fails")
    func channelListWrongBankPC() {
        let json = """
        [
            {
                "title": "Piano",
                "channel": 0,
                "bankPC": [0, 0]
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "ChannelList")
        #expect(!result.isValid)
    }

    // MARK: - CMList Tests

    @Test("Valid CMList passes validation")
    func validCMList() {
        let json = """
        [
            {
                "title": "Control Map 1",
                "index": 0
            },
            {
                "title": "Control Map 2",
                "index": 1
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "CMList")
        #expect(result.isValid)
    }

    @Test("CMList missing index fails")
    func cmListMissingIndex() {
        let json = """
        [
            {
                "title": "Control Map 1"
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "CMList")
        #expect(!result.isValid)
    }

    // MARK: - Auto-Detection Tests

    @Test("Auto-detect DeviceInfo")
    func autoDetectDeviceInfo() {
        let json = """
        {
            "manufacturerId": [0, 72, 7],
            "familyId": [1, 0],
            "modelId": [2, 0],
            "versionId": [1, 0, 0, 0]
        }
        """.data(using: .utf8)!

        let result = validator.validateAuto(json)
        #expect(result.isValid)
    }

    @Test("Auto-detect ResourceList")
    func autoDetectResourceList() {
        let json = """
        [
            {
                "resource": "DeviceInfo",
                "canGet": true
            }
        ]
        """.data(using: .utf8)!

        let result = validator.validateAuto(json)
        #expect(result.isValid)
    }

    // MARK: - Unknown Resource Tests

    @Test("Unknown resource passes (forward compatibility)")
    func unknownResourcePasses() {
        let json = """
        {
            "customField": "value"
        }
        """.data(using: .utf8)!

        let result = validator.validate(json, forResource: "UnknownResource")
        #expect(result.isValid)
    }

    // MARK: - Invalid JSON Tests

    @Test("Invalid JSON fails")
    func invalidJSONFails() {
        let json = "not valid json".data(using: .utf8)!

        let result = validator.validate(json, forResource: "DeviceInfo")
        #expect(!result.isValid)
        #expect(result.errors.contains { error in
            if case .invalidJSON = error { return true }
            return false
        })
    }

    // MARK: - Error Description Tests

    @Test("Error descriptions are readable")
    func errorDescriptionsReadable() {
        let errors: [PESchemaValidationError] = [
            .invalidJSON(NSError(domain: "test", code: 0)),
            .expectedObject,
            .expectedArray,
            .missingRequiredField("field"),
            .wrongFieldType(field: "f", expected: "int", actual: "string"),
            .valueOutOfRange(field: "f", valueDescription: "100", range: "0-50"),
            .unknownResource("Unknown"),
        ]

        for error in errors {
            #expect(!error.description.isEmpty)
        }
    }

    @Test("Multiple errors description")
    func multipleErrorsDescription() {
        let error = PESchemaValidationError.multipleErrors([
            .missingRequiredField("a"),
            .missingRequiredField("b"),
        ])
        #expect(error.description.contains("a"))
        #expect(error.description.contains("b"))
    }
}
