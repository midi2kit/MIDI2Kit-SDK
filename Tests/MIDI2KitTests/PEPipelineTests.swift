//
//  PEPipelineTests.swift
//  MIDI2Kit
//
//  Tests for Pipeline/Chain API (Phase 3)
//

import Testing
import Foundation
@testable import MIDI2PE
@testable import MIDI2Core
@testable import MIDI2Transport

// MARK: - Pipeline Builder Tests

@Suite("PEPipeline Builder")
struct PEPipelineBuilderTests {

    func createTestSetup() async -> (MockMIDITransport, PEManager, PEDeviceHandle) {
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
        return (transport, manager, device)
    }

    @Test("Pipeline can be created")
    func pipelineCanBeCreated() async {
        let (_, manager, device) = await createTestSetup()

        let pipeline = PEPipeline(manager: manager, device: device)

        // Pipeline should be created without error
        #expect(pipeline.timeout == .seconds(5))
    }

    @Test("Pipeline with custom timeout")
    func pipelineWithCustomTimeout() async {
        let (_, manager, device) = await createTestSetup()

        let pipeline = PEPipeline(manager: manager, device: device, timeout: .seconds(10))

        #expect(pipeline.timeout == .seconds(10))
    }

    @Test("Pipeline extension on PEManager")
    func pipelineExtensionOnManager() async {
        let (_, manager, device) = await createTestSetup()

        let pipeline = await manager.pipeline(for: device)

        #expect(pipeline.timeout == .seconds(5))
    }

    @Test("Pipeline extension with custom timeout")
    func pipelineExtensionWithCustomTimeout() async {
        let (_, manager, device) = await createTestSetup()

        let pipeline = await manager.pipeline(for: device, timeout: .seconds(10))

        #expect(pipeline.timeout == .seconds(10))
    }
}

// MARK: - Transform Tests

@Suite("PEPipeline Transform")
struct PEPipelineTransformTests {

    @Test("Transform modifies value")
    func transformModifiesValue() async throws {
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

        // Create a simple pipeline that transforms a constant value
        let result = try await PEPipeline(manager: manager, device: device, timeout: .seconds(5), operation: { 10 })
            .transform { $0 * 2 }
            .execute()

        #expect(result == 20)
    }

    @Test("Map is alias for transform")
    func mapIsAliasForTransform() async throws {
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

        let result = try await PEPipeline(manager: manager, device: device, timeout: .seconds(5), operation: { "hello" })
            .map { $0.uppercased() }
            .execute()

        #expect(result == "HELLO")
    }

    @Test("Chained transforms")
    func chainedTransforms() async throws {
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

        let result = try await PEPipeline(manager: manager, device: device, timeout: .seconds(5), operation: { 5 })
            .transform { $0 + 5 }     // 10
            .transform { $0 * 2 }     // 20
            .transform { $0 - 3 }     // 17
            .execute()

        #expect(result == 17)
    }

    @Test("Transform with type change")
    func transformWithTypeChange() async throws {
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

        let result: String = try await PEPipeline(manager: manager, device: device, timeout: .seconds(5), operation: { 42 })
            .transform { "Number: \($0)" }
            .execute()

        #expect(result == "Number: 42")
    }
}

// MARK: - Conditional Tests

@Suite("PEPipeline Conditional")
struct PEPipelineConditionalTests {

    @Test("Where passes when condition met")
    func wherePassesWhenConditionMet() async throws {
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

        let result = try await PEPipeline(manager: manager, device: device, timeout: .seconds(5), operation: { 10 })
            .where { $0 > 5 }
            .execute()

        #expect(result == 10)
    }

    @Test("Where throws when condition not met")
    func whereThrowsWhenConditionNotMet() async {
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

        do {
            _ = try await PEPipeline(manager: manager, device: device, timeout: .seconds(5), operation: { 3 })
                .where { $0 > 5 }
                .execute()
            Issue.record("Expected to throw")
        } catch let error as PEPipelineError {
            if case .conditionNotMet = error {
                // Expected
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("WhereOr returns default when condition not met")
    func whereOrReturnsDefaultWhenConditionNotMet() async throws {
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

        let result = try await PEPipeline(manager: manager, device: device, timeout: .seconds(5), operation: { 3 })
            .whereOr({ $0 > 5 }, default: 100)
            .execute()

        #expect(result == 100)
    }

    @Test("WhereOr returns value when condition met")
    func whereOrReturnsValueWhenConditionMet() async throws {
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

        let result = try await PEPipeline(manager: manager, device: device, timeout: .seconds(5), operation: { 10 })
            .whereOr({ $0 > 5 }, default: 100)
            .execute()

        #expect(result == 10)
    }
}

// MARK: - Pipeline Error Tests

@Suite("PEPipelineError")
struct PEPipelineErrorTests {

    @Test("Error descriptions are informative")
    func errorDescriptionsAreInformative() {
        let errors: [PEPipelineError] = [
            .conditionNotMet,
            .transformFailed(NSError(domain: "test", code: 1))
        ]

        for error in errors {
            let description = error.description
            #expect(!description.isEmpty)
        }
    }
}

// MARK: - Conditional SET Tests

@Suite("PEConditionalSet")
struct PEConditionalSetTests {

    @Test("ConditionalResult properties")
    func conditionalResultProperties() {
        // Updated case
        let mockResponse = PEResponse(status: 200, header: nil, body: Data())
        let updated = PEConditionalResult<Int>.updated(mockResponse, oldValue: 5, newValue: 10)
        #expect(updated.wasUpdated == true)
        #expect(updated.wasSkipped == false)
        #expect(updated.didFail == false)
        #expect(updated.response != nil)
        #expect(updated.currentValue == 5)
        #expect(updated.error == nil)

        // Skipped case
        let skipped = PEConditionalResult<Int>.skipped(5)
        #expect(skipped.wasUpdated == false)
        #expect(skipped.wasSkipped == true)
        #expect(skipped.didFail == false)
        #expect(skipped.response == nil)
        #expect(skipped.currentValue == 5)
        #expect(skipped.error == nil)

        // Failed case
        let mockError = NSError(domain: "test", code: 1)
        let failed = PEConditionalResult<Int>.failed(mockError)
        #expect(failed.wasUpdated == false)
        #expect(failed.wasSkipped == false)
        #expect(failed.didFail == true)
        #expect(failed.response == nil)
        #expect(failed.currentValue == nil)
        #expect(failed.error != nil)
    }

    @Test("ConditionalSet can be created via manager extension")
    func conditionalSetCanBeCreatedViaManagerExtension() async {
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

        struct TestValue: Codable {
            let value: Int
        }

        let conditional = await manager.conditionalSet("TestResource", as: TestValue.self, on: device)

        #expect(conditional.resource == "TestResource")
        #expect(conditional.channel == nil)
        #expect(conditional.timeout == .seconds(5))
    }

    @Test("ConditionalSet with channel")
    func conditionalSetWithChannel() async {
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

        struct TestValue: Codable {
            let value: Int
        }

        let conditional = await manager.conditionalSet(
            "TestResource",
            as: TestValue.self,
            on: device,
            channel: 5,
            timeout: .seconds(10)
        )

        #expect(conditional.resource == "TestResource")
        #expect(conditional.channel == 5)
        #expect(conditional.timeout == .seconds(10))
    }
}
