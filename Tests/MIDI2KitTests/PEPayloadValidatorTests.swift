//
//  PEPayloadValidatorTests.swift
//  MIDI2Kit
//
//  Tests for Payload Validation Layer (Phase 1)
//

import Testing
import Foundation
@testable import MIDI2PE
@testable import MIDI2Core

// MARK: - Custom Validator Tests

@Suite("PEPayloadValidator Protocol")
struct PEPayloadValidatorProtocolTests {

    /// A simple test validator
    struct VolumeValidator: PEPayloadValidator {
        let resource = "Volume"

        func validate(_ data: Data) throws {
            let json = try JSONSerialization.jsonObject(with: data)
            guard let dict = json as? [String: Any],
                  let level = dict["level"] as? Int else {
                throw PEPayloadValidationError.missingField("level")
            }
            guard (0...127).contains(level) else {
                throw PEPayloadValidationError.invalidFieldValue(
                    field: "level",
                    reason: "must be 0-127"
                )
            }
        }
    }

    @Test("Custom validator passes valid data")
    func customValidatorPassesValidData() throws {
        let validator = VolumeValidator()
        let data = try JSONEncoder().encode(["level": 64])
        #expect(throws: Never.self) {
            try validator.validate(data)
        }
    }

    @Test("Custom validator rejects missing field")
    func customValidatorRejectsMissingField() throws {
        let validator = VolumeValidator()
        let data = try JSONEncoder().encode(["other": 64])

        #expect(throws: PEPayloadValidationError.self) {
            try validator.validate(data)
        }
    }

    @Test("Custom validator rejects out of range value")
    func customValidatorRejectsOutOfRange() throws {
        let validator = VolumeValidator()
        let data = try JSONEncoder().encode(["level": 200])

        #expect(throws: PEPayloadValidationError.self) {
            try validator.validate(data)
        }
    }
}

// MARK: - Registry Tests

@Suite("PEPayloadValidatorRegistry")
struct PEPayloadValidatorRegistryTests {

    struct TestValidator: PEPayloadValidator {
        let resource: String

        func validate(_ data: Data) throws {
            // Simple validator that rejects empty data
            if data.isEmpty {
                throw PEPayloadValidationError.customValidation("Empty data not allowed")
            }
        }
    }

    @Test("Registry registration and lookup")
    func registryRegistrationAndLookup() async {
        let registry = PEPayloadValidatorRegistry()
        let validator = TestValidator(resource: "TestResource")

        await registry.register(validator)

        let retrieved = await registry.validator(for: "TestResource")
        #expect(retrieved != nil)
        #expect(retrieved?.resource == "TestResource")
    }

    @Test("Registry returns nil for unregistered resource")
    func registryReturnsNilForUnregistered() async {
        let registry = PEPayloadValidatorRegistry()

        let retrieved = await registry.validator(for: "UnknownResource")
        #expect(retrieved == nil)
    }

    @Test("Registry unregister removes validator")
    func registryUnregister() async {
        let registry = PEPayloadValidatorRegistry()
        let validator = TestValidator(resource: "TestResource")

        await registry.register(validator)
        #expect(await registry.hasValidator(for: "TestResource"))

        await registry.unregister("TestResource")
        #expect(await !registry.hasValidator(for: "TestResource"))
    }

    @Test("Registry validates with registered validator")
    func registryValidatesWithRegisteredValidator() async throws {
        let registry = PEPayloadValidatorRegistry()
        let validator = TestValidator(resource: "TestResource")
        await registry.register(validator)

        // Valid data
        let validData = Data("test".utf8)
        try await registry.validate(validData, for: "TestResource")

        // Invalid data (empty)
        do {
            try await registry.validate(Data(), for: "TestResource")
            Issue.record("Expected validation to fail")
        } catch let error as PEPayloadValidationError {
            if case .customValidation(let msg) = error {
                #expect(msg.contains("Empty"))
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test("Registry falls back to schema validation")
    func registryFallsBackToSchemaValidation() async throws {
        let registry = PEPayloadValidatorRegistry(useSchemaFallback: true)

        // Valid DeviceInfo
        let validDeviceInfo: [String: Any] = [
            "manufacturerId": [0, 1, 2],
            "familyId": [0, 1],
            "modelId": [0, 1],
            "versionId": [0, 0, 1, 0]
        ]
        let validData = try JSONSerialization.data(withJSONObject: validDeviceInfo)
        try await registry.validate(validData, for: "DeviceInfo")

        // Invalid DeviceInfo (missing required fields)
        let invalidDeviceInfo: [String: Any] = [
            "manufacturer": "Test"
        ]
        let invalidData = try JSONSerialization.data(withJSONObject: invalidDeviceInfo)

        do {
            try await registry.validate(invalidData, for: "DeviceInfo")
            Issue.record("Expected validation to fail")
        } catch let error as PEPayloadValidationError {
            if case .schemaViolation = error {
                // Expected
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test("Registry checks payload size")
    func registryChecksPayloadSize() async throws {
        let registry = PEPayloadValidatorRegistry()
        await registry.setMaxPayloadSize(100)

        // Large payload
        let largeData = Data(repeating: 0x41, count: 200)

        do {
            try await registry.validate(largeData, for: "TestResource")
            Issue.record("Expected validation to fail")
        } catch let error as PEPayloadValidationError {
            if case .payloadTooLarge(let size, let maxSize) = error {
                #expect(size == 200)
                #expect(maxSize == 100)
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test("Registry lists registered resources")
    func registryListsRegisteredResources() async {
        let registry = PEPayloadValidatorRegistry()
        await registry.register(TestValidator(resource: "Resource1"))
        await registry.register(TestValidator(resource: "Resource2"))

        let resources = await registry.registeredResources
        #expect(resources.count == 2)
        #expect(resources.contains("Resource1"))
        #expect(resources.contains("Resource2"))
    }

    @Test("Registry disables schema fallback")
    func registryDisablesSchemaFallback() async throws {
        let registry = PEPayloadValidatorRegistry(useSchemaFallback: false)

        // Invalid DeviceInfo should pass when fallback is disabled
        let invalidDeviceInfo: [String: Any] = [
            "manufacturer": "Test"
        ]
        let invalidData = try JSONSerialization.data(withJSONObject: invalidDeviceInfo)

        // Should not throw because fallback is disabled
        try await registry.validate(invalidData, for: "DeviceInfo")
    }
}

// MARK: - Schema-Based Validator Tests

@Suite("PESchemaBasedValidator")
struct PESchemaBasedValidatorTests {

    @Test("Schema validator validates DeviceInfo")
    func schemaValidatorValidatesDeviceInfo() throws {
        let validator = PESchemaBasedValidator(resource: "DeviceInfo")

        let validData = try JSONSerialization.data(withJSONObject: [
            "manufacturerId": [0, 1, 2],
            "familyId": [0, 1],
            "modelId": [0, 1],
            "versionId": [0, 0, 1, 0]
        ])

        #expect(throws: Never.self) {
            try validator.validate(validData)
        }
    }

    @Test("Schema validator rejects invalid DeviceInfo")
    func schemaValidatorRejectsInvalidDeviceInfo() throws {
        let validator = PESchemaBasedValidator(resource: "DeviceInfo")

        let invalidData = try JSONSerialization.data(withJSONObject: [
            "manufacturer": "Test"
            // Missing required fields
        ])

        #expect(throws: PEPayloadValidationError.self) {
            try validator.validate(invalidData)
        }
    }
}

// MARK: - Builtin Validators Tests

@Suite("PEBuiltinValidators")
struct PEBuiltinValidatorsTests {

    @Test("Builtin validators have correct resources")
    func builtinValidatorsHaveCorrectResources() {
        #expect(PEBuiltinValidators.deviceInfo.resource == "DeviceInfo")
        #expect(PEBuiltinValidators.resourceList.resource == "ResourceList")
        #expect(PEBuiltinValidators.channelList.resource == "ChannelList")
        #expect(PEBuiltinValidators.cmList.resource == "CMList")
    }

    @Test("All builtin validators available")
    func allBuiltinValidatorsAvailable() {
        let all = PEBuiltinValidators.all
        #expect(all.count == 4)
    }
}

// MARK: - Validation Error Tests

@Suite("PEPayloadValidationError")
struct PEPayloadValidationErrorTests {

    @Test("Error descriptions are informative")
    func errorDescriptionsAreInformative() {
        let errors: [PEPayloadValidationError] = [
            .invalidJSON("parse error"),
            .schemaViolation([.missingRequiredField("field")]),
            .customValidation("custom message"),
            .payloadTooLarge(size: 1000, maxSize: 100),
            .missingField("required"),
            .invalidFieldValue(field: "volume", reason: "must be 0-127")
        ]

        for error in errors {
            let description = error.description
            #expect(!description.isEmpty)
        }
    }

    @Test("Error equatable works correctly")
    func errorEquatableWorks() {
        let error1 = PEPayloadValidationError.missingField("test")
        let error2 = PEPayloadValidationError.missingField("test")
        let error3 = PEPayloadValidationError.missingField("other")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}

// MARK: - Registry Concurrency Tests

@Suite("PEPayloadValidatorRegistry Concurrency")
struct PEPayloadValidatorRegistryConcurrencyTests {

    struct ConcurrentValidator: PEPayloadValidator {
        let resource: String
        func validate(_ data: Data) throws {}
    }

    @Test("Registry is thread-safe for registration")
    func registryIsThreadSafeForRegistration() async {
        let registry = PEPayloadValidatorRegistry()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await registry.register(ConcurrentValidator(resource: "Resource\(i)"))
                }
            }
        }

        let resources = await registry.registeredResources
        #expect(resources.count == 100)
    }
}

// MARK: - Helper extension for test

extension PEPayloadValidatorRegistry {
    func setMaxPayloadSize(_ size: Int) {
        maxPayloadSize = size
    }
}
