//
//  VirtualEndpointTests.swift
//  MIDI2Kit
//
//  Tests for Virtual MIDI Endpoint support (Issue #9)
//

import Testing
import Foundation
@testable import MIDI2Transport

// MARK: - VirtualDevice Tests

@Suite("VirtualDevice Tests")
struct VirtualDeviceTests {

    @Test("VirtualDevice stores name, destinationID, and sourceID")
    func properties() {
        let dest = MIDIDestinationID(100)
        let src = MIDISourceID(200)
        let device = VirtualDevice(name: "Test Device", destinationID: dest, sourceID: src)

        #expect(device.name == "Test Device")
        #expect(device.destinationID == dest)
        #expect(device.sourceID == src)
    }

    @Test("VirtualDevice conforms to Hashable")
    func hashable() {
        let device1 = VirtualDevice(
            name: "Dev",
            destinationID: MIDIDestinationID(1),
            sourceID: MIDISourceID(2)
        )
        let device2 = VirtualDevice(
            name: "Dev",
            destinationID: MIDIDestinationID(1),
            sourceID: MIDISourceID(2)
        )
        let device3 = VirtualDevice(
            name: "Dev",
            destinationID: MIDIDestinationID(3),
            sourceID: MIDISourceID(4)
        )

        #expect(device1 == device2)
        #expect(device1 != device3)

        var set = Set<VirtualDevice>()
        set.insert(device1)
        set.insert(device2)
        #expect(set.count == 1)
    }
}

// MARK: - MockMIDITransport Virtual Endpoint Tests

@Suite("Mock Virtual Endpoint Tests")
struct MockVirtualEndpointTests {

    @Test("Create virtual destination returns unique ID")
    func createVirtualDestination() async throws {
        let mock = MockMIDITransport()
        let destID = try await mock.createVirtualDestination(name: "Test Dest")

        #expect(destID.value >= 1000)
        #expect(await mock.createdVirtualDestinations.contains(destID))

        // Should appear in destinations list
        let destinations = await mock.destinations
        #expect(destinations.contains { $0.destinationID == destID })
        #expect(destinations.contains { $0.name == "Test Dest" })
    }

    @Test("Create virtual source returns unique ID")
    func createVirtualSource() async throws {
        let mock = MockMIDITransport()
        let srcID = try await mock.createVirtualSource(name: "Test Src")

        #expect(srcID.value >= 1000)
        #expect(await mock.createdVirtualSources.contains(srcID))

        // Should appear in sources list
        let sources = await mock.sources
        #expect(sources.contains { $0.sourceID == srcID })
        #expect(sources.contains { $0.name == "Test Src" })
    }

    @Test("Remove virtual destination succeeds")
    func removeVirtualDestination() async throws {
        let mock = MockMIDITransport()
        let destID = try await mock.createVirtualDestination(name: "To Remove")

        try await mock.removeVirtualDestination(destID)

        #expect(await mock.createdVirtualDestinations.isEmpty)
        let destinations = await mock.destinations
        #expect(!destinations.contains { $0.destinationID == destID })
    }

    @Test("Remove virtual source succeeds")
    func removeVirtualSource() async throws {
        let mock = MockMIDITransport()
        let srcID = try await mock.createVirtualSource(name: "To Remove")

        try await mock.removeVirtualSource(srcID)

        #expect(await mock.createdVirtualSources.isEmpty)
        let sources = await mock.sources
        #expect(!sources.contains { $0.sourceID == srcID })
    }

    @Test("Remove nonexistent virtual destination throws error")
    func removeNonexistentDestination() async {
        let mock = MockMIDITransport()
        let fakeID = MIDIDestinationID(9999)

        await #expect(throws: MIDITransportError.self) {
            try await mock.removeVirtualDestination(fakeID)
        }
    }

    @Test("Remove nonexistent virtual source throws error")
    func removeNonexistentSource() async {
        let mock = MockMIDITransport()
        let fakeID = MIDISourceID(9999)

        await #expect(throws: MIDITransportError.self) {
            try await mock.removeVirtualSource(fakeID)
        }
    }

    @Test("sendFromVirtualSource records message")
    func sendFromVirtualSource() async throws {
        let mock = MockMIDITransport()
        let srcID = try await mock.createVirtualSource(name: "Sender")

        let data: [UInt8] = [0x90, 60, 127]
        try await mock.sendFromVirtualSource(data, source: srcID)

        let messages = await mock.virtualSourceMessages
        #expect(messages.count == 1)
        #expect(messages[0].data == data)
    }

    @Test("sendFromVirtualSource with invalid source throws error")
    func sendFromInvalidSource() async {
        let mock = MockMIDITransport()
        let fakeID = MIDISourceID(9999)

        await #expect(throws: MIDITransportError.self) {
            try await mock.sendFromVirtualSource([0x90, 60, 127], source: fakeID)
        }
    }

    @Test("publishVirtualDevice creates both source and destination")
    func publishVirtualDevice() async throws {
        let mock = MockMIDITransport()
        let device = try await mock.publishVirtualDevice(name: "My App")

        #expect(device.name == "My App")
        #expect(await mock.createdVirtualDestinations.contains(device.destinationID))
        #expect(await mock.createdVirtualSources.contains(device.sourceID))
        #expect(device.destinationID.value != device.sourceID.value)

        // Both should appear in lists
        let sources = await mock.sources
        let destinations = await mock.destinations
        #expect(sources.contains { $0.sourceID == device.sourceID })
        #expect(destinations.contains { $0.destinationID == device.destinationID })
    }

    @Test("unpublishVirtualDevice removes both source and destination")
    func unpublishVirtualDevice() async throws {
        let mock = MockMIDITransport()
        let device = try await mock.publishVirtualDevice(name: "My App")

        try await mock.unpublishVirtualDevice(device)

        #expect(await mock.createdVirtualDestinations.isEmpty)
        #expect(await mock.createdVirtualSources.isEmpty)
        let sources = await mock.sources
        let destinations = await mock.destinations
        #expect(!sources.contains { $0.sourceID == device.sourceID })
        #expect(!destinations.contains { $0.destinationID == device.destinationID })
    }

    @Test("Virtual destination receives data through received stream")
    func virtualDestinationReceive() async throws {
        let mock = MockMIDITransport()
        let destID = try await mock.createVirtualDestination(name: "Receiver")

        // Inject data simulating another app sending to our virtual destination
        let testData: [UInt8] = [0xF0, 0x7E, 0x7F, 0x0D, 0x70, 0xF7]
        await mock.injectReceived(testData)

        // Verify it appears in the received stream
        var receivedData: [UInt8]?
        for await data in mock.received {
            receivedData = data.data
            break
        }

        #expect(receivedData == testData)

        // Cleanup
        try await mock.removeVirtualDestination(destID)
    }

    @Test("Multiple virtual devices have unique IDs")
    func multipleVirtualDevices() async throws {
        let mock = MockMIDITransport()
        let device1 = try await mock.publishVirtualDevice(name: "Device 1")
        let device2 = try await mock.publishVirtualDevice(name: "Device 2")

        // All IDs should be unique
        let allIDs: Set<UInt32> = [
            device1.destinationID.value,
            device1.sourceID.value,
            device2.destinationID.value,
            device2.sourceID.value
        ]
        #expect(allIDs.count == 4)

        #expect(await mock.createdVirtualDestinations.count == 2)
        #expect(await mock.createdVirtualSources.count == 2)

        // Cleanup
        try await mock.unpublishVirtualDevice(device1)
        try await mock.unpublishVirtualDevice(device2)

        #expect(await mock.createdVirtualDestinations.isEmpty)
        #expect(await mock.createdVirtualSources.isEmpty)
    }

    @Test("Lifecycle: create, verify, remove, verify")
    func fullLifecycle() async throws {
        let mock = MockMIDITransport()

        // Create
        let device = try await mock.publishVirtualDevice(name: "Lifecycle Test")
        #expect(await mock.createdVirtualDestinations.count == 1)
        #expect(await mock.createdVirtualSources.count == 1)

        // Use: send data from virtual source
        try await mock.sendFromVirtualSource([0x90, 60, 127], source: device.sourceID)
        #expect(await mock.virtualSourceMessages.count == 1)

        // Remove
        try await mock.unpublishVirtualDevice(device)
        #expect(await mock.createdVirtualDestinations.isEmpty)
        #expect(await mock.createdVirtualSources.isEmpty)

        // Verify: sending from removed source throws
        await #expect(throws: MIDITransportError.self) {
            try await mock.sendFromVirtualSource([0x90, 60, 0], source: device.sourceID)
        }
    }
}

// MARK: - MIDITransportError Virtual Cases Tests

@Suite("MIDITransportError Virtual Cases Tests")
struct MIDITransportErrorVirtualTests {

    @Test("virtualEndpointCreationFailed description")
    func creationFailedDescription() {
        let error = MIDITransportError.virtualEndpointCreationFailed(-10830)
        #expect(error.description.contains("virtual endpoint"))
        #expect(error.description.contains("-10830"))
    }

    @Test("virtualEndpointNotFound description")
    func notFoundDescription() {
        let error = MIDITransportError.virtualEndpointNotFound(42)
        #expect(error.description.contains("not found"))
        #expect(error.description.contains("42"))
    }

    @Test("virtualEndpointDisposeFailed description")
    func disposeFailedDescription() {
        let error = MIDITransportError.virtualEndpointDisposeFailed(-10831)
        #expect(error.description.contains("dispose"))
        #expect(error.description.contains("-10831"))
    }
}
