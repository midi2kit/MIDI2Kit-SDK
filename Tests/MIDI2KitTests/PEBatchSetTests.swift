//
//  PEBatchSetTests.swift
//  MIDI2Kit
//
//  Tests for Batch SET API (Phase 2)
//

import Testing
import Foundation
@testable import MIDI2PE
@testable import MIDI2Core
@testable import MIDI2Transport

// MARK: - PESetItem Tests

@Suite("PESetItem")
struct PESetItemTests {

    @Test("Create SET item from raw data")
    func createFromRawData() {
        let data = Data([0x01, 0x02, 0x03])
        let item = PESetItem(resource: "TestResource", data: data)

        #expect(item.resource == "TestResource")
        #expect(item.data == data)
        #expect(item.channel == nil)
    }

    @Test("Create SET item with channel")
    func createWithChannel() {
        let data = Data([0x01, 0x02, 0x03])
        let item = PESetItem(resource: "TestResource", data: data, channel: 5)

        #expect(item.resource == "TestResource")
        #expect(item.channel == 5)
    }

    @Test("Create SET item from JSON Encodable")
    func createFromEncodable() throws {
        struct Volume: Codable {
            let level: Int
        }

        let item = try PESetItem.json(resource: "Volume", value: Volume(level: 100))

        #expect(item.resource == "Volume")
        #expect(!item.data.isEmpty)

        // Verify data is valid JSON
        let decoded = try JSONDecoder().decode(Volume.self, from: item.data)
        #expect(decoded.level == 100)
    }

    @Test("Create SET item from dictionary")
    func createFromDictionary() throws {
        let item = try PESetItem.dictionary(resource: "Volume", ["level": 100, "channel": 0])

        #expect(item.resource == "Volume")
        #expect(!item.data.isEmpty)

        // Verify data is valid JSON
        let json = try JSONSerialization.jsonObject(with: item.data) as? [String: Any]
        #expect(json?["level"] as? Int == 100)
    }

    @Test("PESetItem is Hashable")
    func isHashable() {
        let data = Data([0x01, 0x02, 0x03])
        let item1 = PESetItem(resource: "Test", data: data)
        let item2 = PESetItem(resource: "Test", data: data)
        let item3 = PESetItem(resource: "Other", data: data)

        #expect(item1 == item2)
        #expect(item1 != item3)

        var set = Set<PESetItem>()
        set.insert(item1)
        set.insert(item2)
        #expect(set.count == 1)
    }
}

// MARK: - PEBatchSetOptions Tests

@Suite("PEBatchSetOptions")
struct PEBatchSetOptionsTests {

    @Test("Default options")
    func defaultOptions() {
        let options = PEBatchSetOptions.default

        #expect(options.maxConcurrency == 4)
        #expect(options.stopOnFirstFailure == false)
        #expect(options.timeout == .seconds(5))
        #expect(options.validatePayloads == false)
    }

    @Test("Strict options")
    func strictOptions() {
        let options = PEBatchSetOptions.strict

        #expect(options.stopOnFirstFailure == true)
        #expect(options.validatePayloads == true)
    }

    @Test("Fast options")
    func fastOptions() {
        let options = PEBatchSetOptions.fast

        #expect(options.maxConcurrency == 8)
        #expect(options.timeout == .seconds(3))
    }

    @Test("Serial options")
    func serialOptions() {
        let options = PEBatchSetOptions.serial

        #expect(options.maxConcurrency == 1)
    }

    @Test("Custom options")
    func customOptions() {
        let options = PEBatchSetOptions(
            maxConcurrency: 2,
            stopOnFirstFailure: true,
            timeout: .seconds(10),
            validatePayloads: true
        )

        #expect(options.maxConcurrency == 2)
        #expect(options.stopOnFirstFailure == true)
        #expect(options.timeout == .seconds(10))
        #expect(options.validatePayloads == true)
    }

    @Test("Max concurrency cannot be zero")
    func maxConcurrencyCannotBeZero() {
        let options = PEBatchSetOptions(maxConcurrency: 0)
        #expect(options.maxConcurrency == 1)
    }
}

// MARK: - PEBatchSetResponse Tests

@Suite("PEBatchSetResponse")
struct PEBatchSetResponseTests {

    @Test("Empty response properties")
    func emptyResponseProperties() {
        let response = PEBatchSetResponse(results: [:])

        #expect(response.allSucceeded == false) // Empty is not successful
        #expect(response.successCount == 0)
        #expect(response.failureCount == 0)
    }

    @Test("All success response")
    func allSuccessResponse() {
        let mockResponse = PEResponse(status: 200, header: nil, body: Data())
        let results: [String: PEBatchResult] = [
            "Resource1": .success(mockResponse),
            "Resource2": .success(mockResponse)
        ]
        let response = PEBatchSetResponse(results: results)

        #expect(response.allSucceeded == true)
        #expect(response.successCount == 2)
        #expect(response.failureCount == 0)
    }

    @Test("Partial failure response")
    func partialFailureResponse() {
        let mockResponse = PEResponse(status: 200, header: nil, body: Data())
        let results: [String: PEBatchResult] = [
            "Resource1": .success(mockResponse),
            "Resource2": .failure(PEError.timeout(resource: "Resource2"))
        ]
        let response = PEBatchSetResponse(results: results)

        #expect(response.allSucceeded == false)
        #expect(response.successCount == 1)
        #expect(response.failureCount == 1)
    }

    @Test("Subscript access")
    func subscriptAccess() {
        let mockResponse = PEResponse(status: 200, header: nil, body: Data())
        let results: [String: PEBatchResult] = [
            "Resource1": .success(mockResponse)
        ]
        let response = PEBatchSetResponse(results: results)

        let result = response["Resource1"]
        #expect(result?.isSuccess == true)

        let missing = response["Unknown"]
        #expect(missing == nil)
    }

    @Test("Successes and failures extraction")
    func successesAndFailuresExtraction() {
        let mockResponse = PEResponse(status: 200, header: nil, body: Data())
        let mockError = PEError.timeout(resource: "Resource2")
        let results: [String: PEBatchResult] = [
            "Resource1": .success(mockResponse),
            "Resource2": .failure(mockError)
        ]
        let response = PEBatchSetResponse(results: results)

        let successes = response.successes
        let failures = response.failures

        #expect(successes.count == 1)
        #expect(successes["Resource1"] != nil)
        #expect(failures.count == 1)
        #expect(failures["Resource2"] != nil)
    }
}

// MARK: - Batch SET Integration Tests

@Suite("PEManager batchSet Integration")
struct PEBatchSetIntegrationTests {

    /// Helper to create a mock transport and PE manager
    func createMockSetup() async -> (MockMIDITransport, PEManager) {
        let transport = MockMIDITransport()
        let muid = MUID(rawValue: 0x1234567)!
        let manager = PEManager(
            transport: transport,
            sourceMUID: muid,
            requestIDCooldownPeriod: 0
        )
        return (transport, manager)
    }

    @Test("batchSet creates correct item structure")
    func batchSetCreatesCorrectStructure() throws {
        let items = [
            try PESetItem.json(resource: "Volume", value: ["level": 100]),
            try PESetItem.json(resource: "Pan", value: ["position": 64]),
        ]

        #expect(items.count == 2)
        #expect(items[0].resource == "Volume")
        #expect(items[1].resource == "Pan")
    }

    @Test("batchSet with validation options")
    func batchSetWithValidationOptions() async throws {
        let (transport, manager) = await createMockSetup()

        // Create validator registry with strict validation
        let registry = PEPayloadValidatorRegistry()

        // Create a validator that rejects empty data
        struct StrictValidator: PEPayloadValidator {
            let resource: String
            func validate(_ data: Data) throws {
                if data.count < 10 {
                    throw PEPayloadValidationError.customValidation("Data too short")
                }
            }
        }

        await registry.register(StrictValidator(resource: "TestResource"))
        await manager.setPayloadValidatorRegistry(registry)

        // Create items
        let items = [
            PESetItem(resource: "TestResource", data: Data([0x01])) // Too short
        ]

        let destinations = await transport.destinations
        let destID = destinations.first?.destinationID ?? MIDIDestinationID(1)
        let device = PEDeviceHandle(muid: MUID(rawValue: 0x1234567)!, destination: destID)

        // With validation enabled, should fail
        let options = PEBatchSetOptions(validatePayloads: true)
        let response = await manager.batchSet(items, to: device, options: options)

        #expect(response.allSucceeded == false)
        #expect(response.failureCount == 1)
    }
}

// MARK: - Batch SET Channel Tests

@Suite("PEManager batchSetChannels")
struct PEBatchSetChannelTests {

    @Test("batchSetChannels creates channel-keyed results")
    func batchSetChannelsCreatesChannelKeyedResults() async throws {
        let transport = MockMIDITransport()
        let muid = MUID(rawValue: 0x1234567)!
        let manager = PEManager(
            transport: transport,
            sourceMUID: muid,
            requestIDCooldownPeriod: 0
        )

        let destinations = await transport.destinations
        let destID = destinations.first?.destinationID ?? MIDIDestinationID(1)
        let device = PEDeviceHandle(muid: muid, destination: destID)
        let data = try JSONEncoder().encode(["level": 100])

        // Note: This will timeout since no mock responses, but we can check the key format
        let channels = [0, 1, 2]

        // Use very short timeout for test
        let options = PEBatchSetOptions(timeout: .milliseconds(50))
        let response = await manager.batchSetChannels(
            "Volume",
            data: data,
            channels: channels,
            to: device,
            options: options
        )

        // All should fail with timeout (no mock responses)
        #expect(response.failureCount == 3)

        // Check key format
        for (key, _) in response.results {
            #expect(key.hasPrefix("Volume["))
            #expect(key.hasSuffix("]"))
        }
    }
}
