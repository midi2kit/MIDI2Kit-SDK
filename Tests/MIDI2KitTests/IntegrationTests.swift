//
//  IntegrationTests.swift
//  MIDI2KitTests
//
//  Integration tests for CIManager + PEManager workflows
//

import Testing
import Foundation
@testable import MIDI2Kit

@Suite("Integration Tests")
struct IntegrationTests {

    // MARK: - Test Fixtures

    let destinationID = MIDIDestinationID(1)
    let sourceID = MIDISourceID(1)

    // MARK: - Discovery → PE Flow

    @Test("Discovery to PE Get flow works end-to-end")
    func discoveryToPEFlow() async throws {
        // Setup transport
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        await transport.addDestination(MIDIDestinationInfo(
            destinationID: destinationID,
            name: "TestDevice"
        ))

        // Setup CIManager
        let ciManager = CIManager(transport: transport)
        let ciMUID = ciManager.muid

        // Setup PEManager
        let peManager = PEManager(
            transport: transport,
            sourceMUID: ciMUID,
            sendStrategy: .single
        )

        // Start both managers
        try await ciManager.start()
        await peManager.startReceiving()

        // Simulate device discovery
        let deviceMUID = MUID(rawValue: 0x01234567)!
        let discoveryReply = CIMessageBuilder.discoveryReply(
            sourceMUID: deviceMUID,
            destinationMUID: ciMUID,
            deviceIdentity: DeviceIdentity(
                manufacturerID: .korg,
                familyID: 0x0001,
                modelID: 0x0002,
                versionID: 0x00010000
            ),
            categorySupport: .propertyExchange
        )

        await transport.simulateReceive(discoveryReply, from: sourceID)
        try await Task.sleep(for: .milliseconds(100))

        // Verify device discovered
        let devices = await ciManager.discoveredDevices
        #expect(devices.count == 1)
        #expect(devices.first?.muid == deviceMUID)

        // Create device handle for PE
        let handle = PEDeviceHandle(muid: deviceMUID, destination: destinationID, name: "TestDevice")

        // Start PE request
        let peTask = Task {
            try await peManager.get("DeviceInfo", from: handle, timeout: .milliseconds(200))
        }

        // Wait for request to be sent
        try await Task.sleep(for: .milliseconds(50))

        // Verify PE request was sent
        let sentMessages = await transport.sentMessages
        let peRequests = sentMessages.filter { msg in
            msg.data.count > 4 && msg.data[4] == 0x34 // PE Get Request
        }
        #expect(peRequests.count == 1)

        // Simulate PE response
        let peReply = buildPEReply(
            sourceMUID: deviceMUID,
            destinationMUID: ciMUID,
            requestID: 0,
            header: "{\"status\":200}",
            body: "{\"name\":\"TestDevice\"}"
        )
        await transport.simulateReceive(peReply, from: sourceID)

        // Wait for response processing
        let response = try await peTask.value
        #expect(response.status == 200)

        // Cleanup
        await peManager.stopReceiving()
        await ciManager.stop()
    }

    @Test("Multiple devices can be queried simultaneously")
    func multipleDevicesSimultaneously() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }

        // Add destinations
        await transport.addDestination(MIDIDestinationInfo(destinationID: MIDIDestinationID(1), name: "Device1"))
        await transport.addDestination(MIDIDestinationInfo(destinationID: MIDIDestinationID(2), name: "Device2"))

        let sourceMUID = MUID(rawValue: 0x00001111)!
        let peManager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            sendStrategy: .single
        )

        await peManager.startReceiving()

        let device1MUID = MUID(rawValue: 0x01111111)!
        let device2MUID = MUID(rawValue: 0x02222222)!

        let handle1 = PEDeviceHandle(muid: device1MUID, destination: MIDIDestinationID(1), name: "Device1")
        let handle2 = PEDeviceHandle(muid: device2MUID, destination: MIDIDestinationID(2), name: "Device2")

        // Start parallel requests
        async let task1 = peManager.get("DeviceInfo", from: handle1, timeout: .milliseconds(300))
        async let task2 = peManager.get("DeviceInfo", from: handle2, timeout: .milliseconds(300))

        try await Task.sleep(for: .milliseconds(50))

        // Simulate responses for both (need to check requestIDs in sent messages)
        let sent = await transport.sentMessages
        #expect(sent.count == 2)

        // Send responses
        let reply1 = buildPEReply(
            sourceMUID: device1MUID,
            destinationMUID: sourceMUID,
            requestID: 0,
            header: "{\"status\":200}",
            body: "{\"device\":\"Device1\"}"
        )
        let reply2 = buildPEReply(
            sourceMUID: device2MUID,
            destinationMUID: sourceMUID,
            requestID: 1,
            header: "{\"status\":200}",
            body: "{\"device\":\"Device2\"}"
        )

        await transport.simulateReceive(reply1, from: MIDISourceID(1))
        await transport.simulateReceive(reply2, from: MIDISourceID(2))

        // Both should complete
        let (response1, response2) = try await (task1, task2)
        #expect(response1.status == 200)
        #expect(response2.status == 200)

        await peManager.stopReceiving()
    }

    @Test("Timeout followed by retry succeeds")
    func timeoutThenRetrySucceeds() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        await transport.addDestination(MIDIDestinationInfo(destinationID: destinationID, name: "SlowDevice"))

        let sourceMUID = MUID(rawValue: 0x00002222)!
        let deviceMUID = MUID(rawValue: 0x03333333)!

        let peManager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            sendStrategy: .single
        )

        await peManager.startReceiving()

        let handle = PEDeviceHandle(muid: deviceMUID, destination: destinationID, name: "SlowDevice")

        // First request - let it timeout
        let firstTask = Task {
            try await peManager.get("DeviceInfo", from: handle, timeout: .milliseconds(100))
        }

        // Wait for timeout
        do {
            _ = try await firstTask.value
            Issue.record("Expected timeout error")
        } catch {
            // Timeout expected
            #expect(error is PEError)
            if case .timeout = error as? PEError {
                // Good
            } else {
                Issue.record("Expected timeout error, got \(error)")
            }
        }

        // Second request - respond immediately
        let secondTask = Task {
            try await peManager.get("DeviceInfo", from: handle, timeout: .milliseconds(200))
        }

        try await Task.sleep(for: .milliseconds(50))

        // This time respond
        let reply = buildPEReply(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: 1, // Second request uses next ID
            header: "{\"status\":200}",
            body: "{\"recovered\":true}"
        )
        await transport.simulateReceive(reply, from: sourceID)

        let response = try await secondTask.value
        #expect(response.status == 200)

        await peManager.stopReceiving()
    }

    @Test("Device loss during PE request returns error")
    func deviceLossDuringRequest() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        await transport.addDestination(MIDIDestinationInfo(destinationID: destinationID, name: "UnstableDevice"))

        let sourceMUID = MUID(rawValue: 0x00003333)!
        let deviceMUID = MUID(rawValue: 0x04444444)!

        let ciManager = CIManager(transport: transport)
        let peManager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            sendStrategy: .single
        )

        try await ciManager.start()
        await peManager.startReceiving()

        // Register device
        let discoveryReply = CIMessageBuilder.discoveryReply(
            sourceMUID: deviceMUID,
            destinationMUID: ciManager.muid,
            deviceIdentity: DeviceIdentity(
                manufacturerID: .korg,
                familyID: 0x0001,
                modelID: 0x0002,
                versionID: 0x00010000
            ),
            categorySupport: .propertyExchange
        )
        await transport.simulateReceive(discoveryReply, from: sourceID)
        try await Task.sleep(for: .milliseconds(50))

        let handle = PEDeviceHandle(muid: deviceMUID, destination: destinationID, name: "UnstableDevice")

        // Start request
        let peTask = Task {
            try await peManager.get("DeviceInfo", from: handle, timeout: .milliseconds(200))
        }

        // Simulate device sending InvalidateMUID (device going offline)
        let invalidate = CIMessageBuilder.invalidateMUID(
            sourceMUID: deviceMUID,
            targetMUID: deviceMUID
        )
        await transport.simulateReceive(invalidate, from: sourceID)

        // Request should timeout since no response comes
        do {
            _ = try await peTask.value
            Issue.record("Expected timeout error")
        } catch {
            #expect(error is PEError)
        }

        await peManager.stopReceiving()
        await ciManager.stop()
    }

    // MARK: - Helpers

    /// Build a simple PE Reply message
    private func buildPEReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        header: String,
        body: String
    ) -> [UInt8] {
        var data: [UInt8] = []

        // SysEx start + Universal SysEx
        data.append(0xF0)
        data.append(0x7E)
        data.append(0x7F) // Device ID (broadcast)
        data.append(0x0D) // MIDI-CI
        data.append(0x35) // PE Get Reply
        data.append(0x02) // MIDI-CI version

        // Source MUID (4 bytes, LSB first, 7-bit each)
        let srcValue = sourceMUID.value
        data.append(UInt8(srcValue & 0x7F))
        data.append(UInt8((srcValue >> 7) & 0x7F))
        data.append(UInt8((srcValue >> 14) & 0x7F))
        data.append(UInt8((srcValue >> 21) & 0x7F))

        // Destination MUID
        let dstValue = destinationMUID.value
        data.append(UInt8(dstValue & 0x7F))
        data.append(UInt8((dstValue >> 7) & 0x7F))
        data.append(UInt8((dstValue >> 14) & 0x7F))
        data.append(UInt8((dstValue >> 21) & 0x7F))

        // Request ID
        data.append(requestID)

        // Header data (length as 2 bytes + data)
        let headerBytes = Array(header.utf8)
        data.append(UInt8(headerBytes.count & 0x7F))
        data.append(UInt8((headerBytes.count >> 7) & 0x7F))
        data.append(contentsOf: headerBytes)

        // Chunk info: thisChunk=1, numChunks=1
        data.append(0x01) // numChunks LSB
        data.append(0x00) // numChunks MSB
        data.append(0x01) // thisChunk LSB
        data.append(0x00) // thisChunk MSB

        // Body data (length as 2 bytes + data)
        let bodyBytes = Array(body.utf8)
        data.append(UInt8(bodyBytes.count & 0x7F))
        data.append(UInt8((bodyBytes.count >> 7) & 0x7F))
        data.append(contentsOf: bodyBytes)

        // SysEx end
        data.append(0xF7)

        return data
    }
}

// MARK: - Request ID Pool Tests

@Suite("Request ID Pool Integration")
struct RequestIDPoolIntegrationTests {

    @Test("Request IDs are properly recycled after completion")
    func requestIDRecycling() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        await transport.addDestination(MIDIDestinationInfo(
            destinationID: MIDIDestinationID(1),
            name: "Test"
        ))

        let sourceMUID = MUID(rawValue: 0x00004444)!
        let deviceMUID = MUID(rawValue: 0x05555555)!

        let peManager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            sendStrategy: .single
        )

        await peManager.startReceiving()

        let handle = PEDeviceHandle(muid: deviceMUID, destination: MIDIDestinationID(1), name: "Test")

        // Make multiple sequential requests
        for i in 0..<5 {
            let task = Task {
                try await peManager.get("Resource\(i)", from: handle, timeout: .milliseconds(100))
            }

            try await Task.sleep(for: .milliseconds(20))

            // Send reply with matching request ID
            var reply: [UInt8] = [0xF0, 0x7E, 0x7F, 0x0D, 0x35, 0x02]

            // Source MUID
            let srcValue = deviceMUID.value
            reply.append(UInt8(srcValue & 0x7F))
            reply.append(UInt8((srcValue >> 7) & 0x7F))
            reply.append(UInt8((srcValue >> 14) & 0x7F))
            reply.append(UInt8((srcValue >> 21) & 0x7F))

            // Dest MUID
            let dstValue = sourceMUID.value
            reply.append(UInt8(dstValue & 0x7F))
            reply.append(UInt8((dstValue >> 7) & 0x7F))
            reply.append(UInt8((dstValue >> 14) & 0x7F))
            reply.append(UInt8((dstValue >> 21) & 0x7F))

            // Request ID (should cycle 0, 1, 2, 3, 4 with recycling)
            reply.append(UInt8(i % 128))

            // Minimal header
            reply.append(contentsOf: [0x0E, 0x00]) // header length = 14
            reply.append(contentsOf: Array("{\"status\":200}".utf8))

            // Chunk info
            reply.append(contentsOf: [0x01, 0x00, 0x01, 0x00])

            // Body
            reply.append(contentsOf: [0x02, 0x00]) // body length = 2
            reply.append(contentsOf: Array("{}".utf8))

            reply.append(0xF7)

            await transport.simulateReceive(reply, from: MIDISourceID(1))

            let response = try await task.value
            #expect(response.status == 200)
        }

        await peManager.stopReceiving()
    }
}
