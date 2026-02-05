//
//  MockDeviceTests.swift
//  MIDI2Kit
//
//  Tests for MockDevice and LoopbackTransport
//

import Testing
import Foundation
@testable import MIDI2Core
@testable import MIDI2Transport
@testable import MIDI2CI
@testable import MIDI2PE
@testable import MIDI2Kit

// Helper actor for thread-safe counting
private actor Counter {
    var value: Int = 0
    func increment() { value += 1 }
}

@Suite("MockDevice Tests")
struct MockDeviceTests {

    // MARK: - LoopbackTransport Tests

    @Test("LoopbackTransport creates paired transports")
    func loopbackTransportCreatesPair() async throws {
        let (initiator, responder) = await LoopbackTransport.createPair()

        // Verify roles
        await #expect(initiator.role == .initiator)
        await #expect(responder.role == .responder)

        // Verify endpoints are set up
        let initiatorSources = await initiator.sources
        let initiatorDests = await initiator.destinations
        let responderSources = await responder.sources
        let responderDests = await responder.destinations

        #expect(initiatorSources.count == 1)
        #expect(initiatorDests.count == 1)
        #expect(responderSources.count == 1)
        #expect(responderDests.count == 1)

        // Clean up
        await initiator.shutdown()
        await responder.shutdown()
    }

    @Test("LoopbackTransport delivers messages between peers", .disabled("Timing issues with AsyncStream"))
    func loopbackTransportDeliversMessages() async throws {
        let (initiator, responder) = await LoopbackTransport.createPair()

        let testData: [UInt8] = [0xF0, 0x7E, 0x7F, 0x0D, 0x70, 0xF7]

        // Use actor to collect received data
        actor Collector {
            var received: [UInt8] = []
            func set(_ data: [UInt8]) { received = data }
            func get() -> [UInt8] { received }
        }
        let collector = Collector()

        // Start listening on responder
        let receiveTask = Task {
            for await received in responder.received {
                await collector.set(received.data)
                break  // Exit after first message
            }
        }

        // Small delay to ensure listener is ready
        try await Task.sleep(for: .milliseconds(10))

        // Send from initiator
        let dest = await initiator.destinations.first!
        try await initiator.send(testData, to: dest.destinationID)

        // Wait for receive with timeout
        try await Task.sleep(for: .milliseconds(50))

        let result = await collector.get()
        #expect(result == testData)

        // Clean up
        receiveTask.cancel()
        await initiator.shutdown()
        await responder.shutdown()
    }

    // MARK: - CIMessageParser+Inquiry Tests

    @Test("Parse PE GET Inquiry")
    func parsePEGetInquiry() async throws {
        // Build a PE GET Inquiry message
        let sourceMUID = MUID(rawValue: 0x01020304)!
        let destMUID = MUID(rawValue: 0x05060708)!
        let requestID: UInt8 = 42
        let headerData = Data("{\"resource\":\"DeviceInfo\"}".utf8)

        let message = CIMessageBuilder.peGetInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            requestID: requestID,
            headerData: headerData
        )

        // Parse it
        let parsed = CIMessageParser.parseFullPEGetInquiry(message)

        try #require(parsed != nil)
        #expect(parsed!.sourceMUID == sourceMUID)
        #expect(parsed!.destinationMUID == destMUID)
        #expect(parsed!.requestID == requestID)
        #expect(parsed!.resource == "DeviceInfo")
    }

    @Test("Parse PE SET Inquiry")
    func parsePESetInquiry() async throws {
        let sourceMUID = MUID(rawValue: 0x01020304)!
        let destMUID = MUID(rawValue: 0x05060708)!
        let requestID: UInt8 = 43
        let headerData = Data("{\"resource\":\"ProgramName\"}".utf8)
        let propertyData = Data("{\"name\":\"New Program\"}".utf8)

        let message = CIMessageBuilder.peSetInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            requestID: requestID,
            headerData: headerData,
            propertyData: propertyData
        )

        let parsed = CIMessageParser.parseFullPESetInquiry(message)

        try #require(parsed != nil)
        #expect(parsed!.sourceMUID == sourceMUID)
        #expect(parsed!.destinationMUID == destMUID)
        #expect(parsed!.requestID == requestID)
        #expect(parsed!.resource == "ProgramName")
        #expect(parsed!.propertyData == propertyData)
    }

    @Test("Parse Discovery Inquiry")
    func parseDiscoveryInquiry() async throws {
        let sourceMUID = MUID(rawValue: 0x01020304)!
        let identity = DeviceIdentity.default

        let message = CIMessageBuilder.discoveryInquiry(
            sourceMUID: sourceMUID,
            deviceIdentity: identity,
            categorySupport: .propertyExchange
        )

        let parsed = CIMessageParser.parseFullDiscoveryInquiry(message)

        try #require(parsed != nil)
        #expect(parsed!.sourceMUID == sourceMUID)
        #expect(parsed!.categorySupport.contains(CategorySupport.propertyExchange))
    }

    // MARK: - CIMessageBuilder+Reply Tests

    @Test("Build PE GET Reply")
    func buildPEGetReply() async throws {
        let sourceMUID = MUID(rawValue: 0x01020304)!
        let destMUID = MUID(rawValue: 0x05060708)!
        let requestID: UInt8 = 42
        let headerData = CIMessageBuilder.successResponseHeader()
        let propertyData = Data("{\"manufacturer\":\"Test\"}".utf8)

        let message = CIMessageBuilder.peGetReply(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            requestID: requestID,
            headerData: headerData,
            propertyData: propertyData
        )

        // Parse it back
        let parsed = CIMessageParser.parseFullPEReply(message)

        try #require(parsed != nil)
        #expect(parsed!.sourceMUID == sourceMUID)
        #expect(parsed!.destinationMUID == destMUID)
        #expect(parsed!.requestID == requestID)
        #expect(parsed!.propertyData == propertyData)
    }

    @Test("Build PE Subscribe Reply with subscribeId")
    func buildPESubscribeReply() async throws {
        let sourceMUID = MUID(rawValue: 0x01020304)!
        let destMUID = MUID(rawValue: 0x05060708)!
        let requestID: UInt8 = 44
        let subscribeId = "sub-123"
        let headerData = CIMessageBuilder.subscribeResponseHeader(
            status: 200,
            subscribeId: subscribeId
        )

        let message = CIMessageBuilder.peSubscribeReply(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            requestID: requestID,
            headerData: headerData
        )

        // Parse it back
        let parsed = CIMessageParser.parseFullSubscribeReply(message)

        try #require(parsed != nil)
        #expect(parsed!.subscribeId == subscribeId)
        #expect(parsed!.status == 200)
    }

    // MARK: - PEResponderResource Tests

    @Test("InMemoryResource handles GET and SET")
    func inMemoryResourceGetSet() async throws {
        let initialData = Data("{\"value\":1}".utf8)
        let resource = InMemoryResource(data: initialData)
        let emptyHeader = PERequestHeader()

        // GET
        let getData = try await resource.get(header: emptyHeader)
        #expect(getData == initialData)

        // SET
        let newData = Data("{\"value\":2}".utf8)
        _ = try await resource.set(header: emptyHeader, body: newData)

        // GET again
        let updatedData = try await resource.get(header: emptyHeader)
        #expect(updatedData == newData)
    }

    @Test("StaticResource returns fixed data")
    func staticResourceReturnsFixed() async throws {
        let json = "{\"constant\":true}"
        let resource = StaticResource(json: json)
        let emptyHeader = PERequestHeader()

        let data = try await resource.get(header: emptyHeader)
        #expect(String(data: data, encoding: .utf8) == json)
    }

    @Test("ComputedResource uses custom handler")
    func computedResourceUsesHandler() async throws {
        let counter = Counter()
        let resource = ComputedResource { _ in
            await counter.increment()
            let count = await counter.value
            return Data("{\"calls\":\(count)}".utf8)
        }
        let emptyHeader = PERequestHeader()

        _ = try await resource.get(header: emptyHeader)
        _ = try await resource.get(header: emptyHeader)

        let finalCount = await counter.value
        #expect(finalCount == 2)
    }

    // MARK: - MockDevice Tests (Integration - Disabled for now due to timing issues)
    // TODO: Re-enable when AsyncStream timing is fixed

    @Test("MockDevice responds to Discovery Inquiry", .disabled("Timing issues with AsyncStream"))
    func mockDeviceRespondsToDiscovery() async throws {
        let (initiator, responder) = await LoopbackTransport.createPair()

        let mockDevice = await MockDevice.korgModulePro(transport: responder)
        await mockDevice.start()

        // Build Discovery Inquiry
        let myMUID = MUID.random()
        let inquiry = CIMessageBuilder.discoveryInquiry(
            sourceMUID: myMUID,
            categorySupport: .propertyExchange
        )

        // Listen for reply
        let receiveTask = Task<CIMessageParser.ParsedMessage?, Never> {
            for await received in initiator.received {
                if let parsed = CIMessageParser.parse(received.data),
                   parsed.messageType == .discoveryReply {
                    return parsed
                }
            }
            return nil
        }

        // Small delay
        try await Task.sleep(for: .milliseconds(10))

        // Send inquiry
        let dest = await initiator.destinations.first!
        try await initiator.send(inquiry, to: dest.destinationID)

        // Wait for reply with timeout
        let result = await withTaskGroup(of: CIMessageParser.ParsedMessage?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(500))
                return nil
            }
            return await group.first { $0 != nil } ?? nil
        }

        try #require(result != nil)
        #expect(result!.messageType == .discoveryReply)
        #expect(result!.destinationMUID == myMUID)

        // Clean up
        receiveTask.cancel()
        await mockDevice.stop()
        await initiator.shutdown()
        await responder.shutdown()
    }

    @Test("MockDevice responds to PE Capability Inquiry", .disabled("Timing issues with AsyncStream"))
    func mockDeviceRespondsToPECapability() async throws {
        let (initiator, responder) = await LoopbackTransport.createPair()

        let mockDevice = await MockDevice.generic(name: "Test", transport: responder)
        await mockDevice.start()

        let myMUID = MUID.random()
        let deviceMUID = await mockDevice.muid

        let inquiry = CIMessageBuilder.peCapabilityInquiry(
            sourceMUID: myMUID,
            destinationMUID: deviceMUID
        )

        // Listen for reply
        let receiveTask = Task<CIMessageParser.ParsedMessage?, Never> {
            for await received in initiator.received {
                if let parsed = CIMessageParser.parse(received.data),
                   parsed.messageType == .peCapabilityReply {
                    return parsed
                }
            }
            return nil
        }

        try await Task.sleep(for: .milliseconds(10))

        let dest = await initiator.destinations.first!
        try await initiator.send(inquiry, to: dest.destinationID)

        let result = await withTaskGroup(of: CIMessageParser.ParsedMessage?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(500))
                return nil
            }
            return await group.first { $0 != nil } ?? nil
        }

        try #require(result != nil)
        #expect(result!.messageType == .peCapabilityReply)

        // Parse capability reply
        let capReply = CIMessageParser.parsePECapabilityReply(result!.payload)
        try #require(capReply != nil)
        #expect(capReply!.numSimultaneousRequests >= 1)

        // Clean up
        receiveTask.cancel()
        await mockDevice.stop()
        await initiator.shutdown()
        await responder.shutdown()
    }

    @Test("MockDevice responds to PE GET Inquiry", .disabled("Timing issues with AsyncStream"))
    func mockDeviceRespondsToPEGet() async throws {
        let (initiator, responder) = await LoopbackTransport.createPair()

        let mockDevice = await MockDevice.korgModulePro(transport: responder)
        await mockDevice.start()

        let myMUID = MUID.random()
        let deviceMUID = await mockDevice.muid

        let headerData = Data("{\"resource\":\"DeviceInfo\"}".utf8)
        let inquiry = CIMessageBuilder.peGetInquiry(
            sourceMUID: myMUID,
            destinationMUID: deviceMUID,
            requestID: 1,
            headerData: headerData
        )

        // Listen for reply
        let receiveTask = Task<CIMessageParser.FullPEReply?, Never> {
            for await received in initiator.received {
                if let reply = CIMessageParser.parseFullPEReply(received.data) {
                    return reply
                }
            }
            return nil
        }

        try await Task.sleep(for: .milliseconds(10))

        let dest = await initiator.destinations.first!
        try await initiator.send(inquiry, to: dest.destinationID)

        let result = await withTaskGroup(of: CIMessageParser.FullPEReply?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(500))
                return nil
            }
            return await group.first { $0 != nil } ?? nil
        }

        try #require(result != nil)
        #expect(result!.requestID == 1)

        // Verify we got DeviceInfo data
        let bodyString = String(data: result!.propertyData, encoding: .utf8) ?? ""
        #expect(bodyString.contains("KORG"))

        // Clean up
        receiveTask.cancel()
        await mockDevice.stop()
        await initiator.shutdown()
        await responder.shutdown()
    }

    // MARK: - MockDevicePreset Tests

    @Test("KORG preset has expected resources")
    func korgPresetHasResources() {
        let preset = MockDevicePreset.korgModulePro

        #expect(preset.resources.keys.contains("DeviceInfo"))
        #expect(preset.resources.keys.contains("ResourceList"))
        #expect(preset.resources.keys.contains("CMList"))
        #expect(preset.resources.keys.contains("ChannelList"))

        // Verify identity is KORG
        #expect(preset.identity.manufacturerID == .standard(0x42))
    }

    @Test("Generic preset creates valid device")
    func genericPresetIsValid() {
        let preset = MockDevicePreset.generic(name: "MyDevice", manufacturer: "MyCompany")

        #expect(preset.resources.keys.contains("DeviceInfo"))
        #expect(preset.resources.keys.contains("ResourceList"))

        // Verify DeviceInfo contains custom name
        let deviceInfo = preset.resources["DeviceInfo"]!
        #expect(deviceInfo.contains("MyDevice"))
        #expect(deviceInfo.contains("MyCompany"))
    }
}
