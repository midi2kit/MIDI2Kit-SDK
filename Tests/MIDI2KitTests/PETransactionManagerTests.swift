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
    
    // MARK: - Monitor Handle Tests
    
    @Test("startMonitoring returns handle")
    func startMonitoringReturnsHandle() async {
        let manager = PETransactionManager()
        
        #expect(await manager.isMonitoring == false)
        
        let handle = await manager.startMonitoring()
        
        #expect(handle.isActive == true)
        #expect(await manager.isMonitoring == true)
        
        await handle.stop()
        
        // Give time for async cleanup
        try? await Task.sleep(for: .milliseconds(10))
        #expect(await manager.isMonitoring == false)
    }
    
    @Test("startMonitoring is idempotent - returns same handle")
    func startMonitoringIdempotent() async {
        let manager = PETransactionManager()
        
        let handle1 = await manager.startMonitoring()
        let handle2 = await manager.startMonitoring()
        
        // Should return the same handle (identity check)
        #expect(handle1 === handle2)
        #expect(handle1.isActive == true)
        
        await handle1.stop()
    }
    
    @Test("Handle deallocation stops monitoring")
    func handleDeallocationStopsMonitoring() async throws {
        let manager = PETransactionManager()
        
        // Create handle in inner scope
        do {
            let handle = await manager.startMonitoring()
            #expect(handle.isActive == true)
            #expect(await manager.isMonitoring == true)
            // handle goes out of scope here
        }
        
        // Give time for deinit and cleanup
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(await manager.isMonitoring == false)
    }
    
    @Test("Automatic timeout cleanup via monitoring")
    func automaticTimeoutCleanup() async throws {
        let config = PEMonitoringConfiguration(checkInterval: 0.05)
        let manager = PETransactionManager(monitoringConfig: config)
        let muid = MUID.random()
        
        // Start monitoring - hold the handle
        let handle = await manager.startMonitoring()
        
        // Create transaction with very short timeout
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid, timeout: 0.02)
        #expect(id != nil)
        #expect(await manager.activeCount == 1)
        
        // Wait for monitoring to clean up (timeout 20ms + check interval 50ms + buffer)
        try await Task.sleep(for: .milliseconds(150))
        
        // Transaction should be automatically cleaned up
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
        
        await handle.stop()
    }
    
    @Test("Handle.stop() is idempotent")
    func handleStopIdempotent() async {
        let manager = PETransactionManager()
        let handle = await manager.startMonitoring()
        
        // Multiple stops should be safe
        await handle.stop()
        await handle.stop()
        await handle.stop()
        
        #expect(handle.isActive == false)
    }
    
    @Test("New handle after previous stopped")
    func newHandleAfterStopped() async throws {
        let manager = PETransactionManager()
        
        let handle1 = await manager.startMonitoring()
        await handle1.stop()
        
        try await Task.sleep(for: .milliseconds(20))
        
        // Should be able to start again with new handle
        let handle2 = await manager.startMonitoring()
        
        #expect(handle1 !== handle2)  // Different handle
        #expect(handle2.isActive == true)
        #expect(await manager.isMonitoring == true)
        
        await handle2.stop()
    }
    
    @Test("Diagnostics shows monitoring status")
    func diagnosticsShowsMonitoringStatus() async {
        let manager = PETransactionManager()
        
        var diag = await manager.diagnostics
        #expect(diag.contains("Monitoring: stopped"))
        
        let handle = await manager.startMonitoring()
        
        diag = await manager.diagnostics
        #expect(diag.contains("Monitoring: active"))
        
        await handle.stop()
    }
    
    @Test("Manager can be deallocated while monitoring")
    func managerDeallocationStopsMonitoring() async throws {
        var handle: PEMonitorHandle?
        
        do {
            // Use short check interval so Task checks weak self quickly
            let config = PEMonitoringConfiguration(checkInterval: 0.02)
            let manager = PETransactionManager(monitoringConfig: config)
            handle = await manager.startMonitoring()
            #expect(handle?.isActive == true)
            // manager goes out of scope here
        }
        
        // Wait for Task to complete its sleep and check weak self
        // (checkInterval 20ms + buffer)
        try await Task.sleep(for: .milliseconds(100))
        
        // Task should have stopped since manager is gone
        // (weak self in Task causes loop to exit)
        #expect(handle?.isActive == false)
    }
    
    // MARK: - waitForCompletion Tests
    
    @Test("waitForCompletion returns result on complete")
    func waitForCompletionReturnsResultOnComplete() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        #expect(id != nil)
        
        // Start waiting in background
        let waitTask = Task {
            await manager.waitForCompletion(requestID: id!)
        }
        
        // Give time for wait to register
        try? await Task.sleep(for: .milliseconds(10))
        
        // Complete the transaction
        await manager.complete(requestID: id!, header: Data(), body: Data("test".utf8))
        
        // Wait should return success
        let result = await waitTask.value
        if case .success(_, let body) = result {
            #expect(body == Data("test".utf8))
        } else {
            Issue.record("Expected success result, got \(result)")
        }
    }
    
    @Test("waitForCompletion returns cancelled for unknown requestID")
    func waitForCompletionReturnsCancelledForUnknownID() async {
        let manager = PETransactionManager()
        
        // Wait for non-existent request
        let result = await manager.waitForCompletion(requestID: 99)
        
        if case .cancelled = result {
            // Expected
        } else {
            Issue.record("Expected cancelled, got \(result)")
        }
    }
    
    @Test("waitForCompletion duplicate call returns cancelled")
    func waitForCompletionDuplicateCallReturnsCancelled() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        #expect(id != nil)
        
        // First waiter
        let waiter1 = Task {
            await manager.waitForCompletion(requestID: id!)
        }
        
        // Give time for first wait to register
        try? await Task.sleep(for: .milliseconds(10))
        
        // Second waiter (should return cancelled immediately)
        let result2 = await manager.waitForCompletion(requestID: id!)
        
        // Second call should return cancelled
        if case .cancelled = result2 {
            // Expected - duplicate wait returns cancelled
        } else {
            Issue.record("Expected cancelled for duplicate wait, got \(result2)")
        }
        
        // Complete the transaction for first waiter
        await manager.complete(requestID: id!, header: Data(), body: Data())
        
        // First waiter should get success
        let result1 = await waiter1.value
        if case .success = result1 {
            // Expected
        } else {
            Issue.record("Expected success for first waiter, got \(result1)")
        }
    }
    
    @Test("waitForCompletion does not leak continuation on duplicate call")
    func waitForCompletionDoesNotLeakContinuationOnDuplicate() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        #expect(id != nil)
        
        // First waiter
        let waiter1 = Task {
            await manager.waitForCompletion(requestID: id!)
        }
        
        try? await Task.sleep(for: .milliseconds(10))
        
        // Multiple duplicate calls - all should return cancelled immediately
        for _ in 0..<5 {
            let result = await manager.waitForCompletion(requestID: id!)
            if case .cancelled = result {
                // Expected
            } else {
                Issue.record("Expected cancelled for duplicate wait")
            }
        }
        
        // Complete transaction
        await manager.complete(requestID: id!, header: Data(), body: Data())
        
        // First waiter should complete normally
        let result1 = await waiter1.value
        if case .success = result1 {
            // Expected
        } else {
            Issue.record("First waiter should get success")
        }
        
        // Verify clean state
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
}
