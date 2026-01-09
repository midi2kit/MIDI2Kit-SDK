//
//  PETransactionManagerTests.swift
//  MIDI2Kit
//
//  Tests for PE transaction management and leak prevention
//

import Testing
import Foundation
@testable import MIDI2PE
@testable import MIDI2Core

@Suite("PETransactionManager Tests")
struct PETransactionManagerTests {
    
    @Test("Begin transaction acquires ID")
    func beginAcquiresID() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        
        #expect(id != nil)
        #expect(await manager.activeCount == 1)
        #expect(await manager.availableIDs == 127)
    }
    
    @Test("Complete releases ID")
    func completeReleasesID() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        #expect(id != nil)
        
        await manager.complete(requestID: id!, header: Data(), body: Data())
        
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
    
    @Test("Error completion releases ID")
    func errorReleasesID() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        #expect(id != nil)
        
        // Simulate 404 error
        await manager.completeWithError(requestID: id!, status: 404, message: "Not found")
        
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
    
    @Test("Cancel releases ID")
    func cancelReleasesID() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        #expect(id != nil)
        
        await manager.cancel(requestID: id!)
        
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
    
    @Test("Timeout releases ID")
    func timeoutReleasesID() async throws {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        // Very short timeout
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid, timeout: 0.01)
        #expect(id != nil)
        
        // Wait for timeout
        try await Task.sleep(for: .milliseconds(50))
        
        let timedOut = await manager.checkTimeouts()
        
        #expect(timedOut.contains(id!))
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
    
    @Test("Cancel all for device")
    func cancelAllForDevice() async {
        let manager = PETransactionManager()
        let device1 = MUID.random()
        let device2 = MUID.random()
        
        // Create transactions for two devices
        _ = await manager.begin(resource: "DeviceInfo", destinationMUID: device1)
        _ = await manager.begin(resource: "ChCtrlList", destinationMUID: device1)
        _ = await manager.begin(resource: "DeviceInfo", destinationMUID: device2)
        
        #expect(await manager.activeCount == 3)
        
        // Cancel only device1
        await manager.cancelAll(for: device1)
        
        #expect(await manager.activeCount == 1)
        #expect(await manager.availableIDs == 127)
    }
    
    @Test("Cancel all")
    func cancelAll() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        for i in 0..<10 {
            _ = await manager.begin(resource: "Resource\(i)", destinationMUID: muid)
        }
        
        #expect(await manager.activeCount == 10)
        
        await manager.cancelAll()
        
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
    
    @Test("Exhaustion returns nil")
    func exhaustionReturnsNil() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        // Exhaust all 128 IDs
        for _ in 0..<128 {
            let id = await manager.begin(resource: "Test", destinationMUID: muid)
            #expect(id != nil)
        }
        
        // 129th should fail
        let exhausted = await manager.begin(resource: "Test", destinationMUID: muid)
        #expect(exhausted == nil)
        #expect(await manager.isNearExhaustion == true)  // 0 < 10, so still "near exhaustion"
        #expect(await manager.availableIDs == 0)
    }
    
    @Test("Near exhaustion warning")
    func nearExhaustionWarning() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        // Use 120 IDs (leaving 8)
        for _ in 0..<120 {
            _ = await manager.begin(resource: "Test", destinationMUID: muid)
        }
        
        #expect(await manager.isNearExhaustion == true)
        #expect(await manager.availableIDs == 8)
    }
    
    @Test("Multiple transactions same resource")
    func multipleTransactionsSameResource() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id1 = await manager.begin(resource: "ChCtrlList", destinationMUID: muid)
        let id2 = await manager.begin(resource: "ChCtrlList", destinationMUID: muid)
        
        #expect(id1 != nil)
        #expect(id2 != nil)
        #expect(id1 != id2)
        #expect(await manager.activeCount == 2)
    }
    
    @Test("Chunk assembly auto-completes")
    func chunkAssemblyAutoCompletes() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "ProgramList", destinationMUID: muid)
        #expect(id != nil)
        
        // Single chunk auto-completes
        let result = await manager.processChunk(
            requestID: id!,
            thisChunk: 1,
            numChunks: 1,
            headerData: Data("{\"status\":200}".utf8),
            propertyData: Data("[]".utf8)
        )
        
        if case .complete = result {
            // Expected
        } else {
            Issue.record("Expected complete result")
        }
        
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
    
    @Test("Diagnostics output")
    func diagnosticsOutput() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        _ = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        _ = await manager.begin(resource: "ChCtrlList", destinationMUID: muid)
        
        let diag = await manager.diagnostics
        
        #expect(diag.contains("Active transactions: 2"))
        #expect(diag.contains("DeviceInfo"))
        #expect(diag.contains("ChCtrlList"))
    }
}
