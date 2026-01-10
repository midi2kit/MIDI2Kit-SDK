//
//  CIManagerTests.swift
//  MIDI2KitTests
//
//  Tests for CIManager
//

import Testing
import Foundation
@testable import MIDI2Kit

@Suite("CIManager Tests")
struct CIManagerTests {
    
    @Test("CIManager initializes with random MUID")
    func initWithRandomMUID() async {
        let transport = MockMIDITransport()
        let manager = CIManager(transport: transport)
        
        let muid = manager.muid
        #expect(!muid.isBroadcast)
        #expect(muid != MUID.reserved)
    }
    
    @Test("CIManager generates unique MUIDs")
    func uniqueMUIDs() async {
        let transport = MockMIDITransport()
        let manager1 = CIManager(transport: transport)
        let manager2 = CIManager(transport: transport)
        
        let muid1 = manager1.muid
        let muid2 = manager2.muid
        
        // Different managers should have different MUIDs (with very high probability)
        #expect(muid1 != muid2)
    }
    
    @Test("CIManager uses default configuration")
    func defaultConfiguration() async {
        // Test that CIManagerConfiguration has proper defaults
        let config = CIManagerConfiguration()
        
        #expect(config.discoveryInterval == 5.0)
        #expect(config.deviceTimeout == 15.0)
        #expect(config.maxSysExSize == 0)
        #expect(config.categorySupport == .propertyExchange)
    }
    
    @Test("CIManager discovers device from Discovery Reply")
    func discoversDeviceFromReply() async throws {
        let transport = MockMIDITransport()
        await transport.addDestination(MIDIDestinationInfo(
            destinationID: MIDIDestinationID(1),
            name: "Test"
        ))
        
        let manager = CIManager(transport: transport)
        let managerMUID = manager.muid
        
        // Start manager (begins receiving) and discovery
        try await manager.start()
        
        // Simulate receiving a Discovery Reply
        let deviceMUID = MUID(rawValue: 0xABCDEF0)!
        let reply = CIMessageBuilder.discoveryReply(
            sourceMUID: deviceMUID,
            destinationMUID: managerMUID,
            deviceIdentity: DeviceIdentity(
                manufacturerID: .korg,
                familyID: 0x0001,
                modelID: 0x0002,
                versionID: 0x00010000
            ),
            categorySupport: .propertyExchange
        )
        
        await transport.simulateReceive(reply, from: MIDISourceID(1))
        
        // Wait for processing
        try await Task.sleep(for: .milliseconds(200))
        
        // Check device was registered
        let devices = await manager.discoveredDevices
        #expect(devices.count == 1)
        #expect(devices.first?.muid == deviceMUID)
        
        await manager.stop()
    }
    
    @Test("CIManager removes device on InvalidateMUID")
    func removesDeviceOnInvalidate() async throws {
        let transport = MockMIDITransport()
        await transport.addDestination(MIDIDestinationInfo(
            destinationID: MIDIDestinationID(1),
            name: "Test"
        ))
        
        let manager = CIManager(transport: transport)
        let managerMUID = manager.muid
        
        try await manager.start()
        
        // First, discover a device
        let deviceMUID = MUID(rawValue: 0xABCDEF0)!
        let reply = CIMessageBuilder.discoveryReply(
            sourceMUID: deviceMUID,
            destinationMUID: managerMUID,
            deviceIdentity: .default,
            categorySupport: .propertyExchange
        )
        await transport.simulateReceive(reply, from: MIDISourceID(1))
        
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify device is discovered
        var devices = await manager.discoveredDevices
        #expect(devices.count == 1)
        
        // Now send InvalidateMUID
        let invalidate = CIMessageBuilder.invalidateMUID(
            sourceMUID: deviceMUID,
            targetMUID: MUID.broadcast
        )
        await transport.simulateReceive(invalidate, from: MIDISourceID(1))
        
        try await Task.sleep(for: .milliseconds(100))
        
        // Device should be removed
        devices = await manager.discoveredDevices
        #expect(devices.count == 0)
        
        await manager.stop()
    }
    
    @Test("CIManager can clear all devices")
    func clearDevices() async throws {
        let transport = MockMIDITransport()
        await transport.addDestination(MIDIDestinationInfo(
            destinationID: MIDIDestinationID(1),
            name: "Test"
        ))
        
        let manager = CIManager(transport: transport)
        let managerMUID = manager.muid
        
        try await manager.start()
        
        // Discover two devices
        for i in 1...2 {
            let reply = CIMessageBuilder.discoveryReply(
                sourceMUID: MUID(rawValue: UInt32(i * 0x1000000))!,
                destinationMUID: managerMUID,
                deviceIdentity: .default,
                categorySupport: .propertyExchange
            )
            await transport.simulateReceive(reply, from: MIDISourceID(1))
        }
        
        try await Task.sleep(for: .milliseconds(100))
        
        var devices = await manager.discoveredDevices
        #expect(devices.count == 2)
        
        // Clear all
        await manager.clearDevices()
        
        devices = await manager.discoveredDevices
        #expect(devices.count == 0)
        
        await manager.stop()
    }
    
    @Test("CIManager gets device by MUID")
    func getDeviceByMUID() async throws {
        let transport = MockMIDITransport()
        await transport.addDestination(MIDIDestinationInfo(
            destinationID: MIDIDestinationID(1),
            name: "Test"
        ))
        
        let manager = CIManager(transport: transport)
        let managerMUID = manager.muid
        
        try await manager.start()
        
        let deviceMUID = MUID(rawValue: 0xABCDEF0)!
        let identity = DeviceIdentity(
            manufacturerID: .korg,
            familyID: 0x0042,
            modelID: 0x0001,
            versionID: 0x00010200
        )
        
        let reply = CIMessageBuilder.discoveryReply(
            sourceMUID: deviceMUID,
            destinationMUID: managerMUID,
            deviceIdentity: identity,
            categorySupport: .propertyExchange
        )
        await transport.simulateReceive(reply, from: MIDISourceID(1))
        
        try await Task.sleep(for: .milliseconds(100))
        
        // Lookup by MUID
        let device = await manager.device(for: deviceMUID)
        #expect(device != nil)
        #expect(device?.identity.manufacturerID == .korg)
        #expect(device?.identity.familyID == 0x0042)
        
        // Lookup non-existent MUID
        let notFound = await manager.device(for: MUID(rawValue: 0xFFFFFF)!)
        #expect(notFound == nil)
        
        await manager.stop()
    }
}
