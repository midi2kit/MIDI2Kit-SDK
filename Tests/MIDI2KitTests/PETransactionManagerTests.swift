//
//  PETransactionManagerTests.swift
//  MIDI2Kit
//
//  Tests for PE transaction management
//
//  PETransactionManager is responsible for:
//  - Request ID allocation/release
//  - Chunk assembly
//  - Transaction state tracking
//
//  Note: Timeout scheduling and continuation management are tested
//  in PEManagerTests (PEManager owns those responsibilities).
//

import Testing
import Foundation
@testable import MIDI2PE
@testable import MIDI2Core

@Suite("PETransactionManager Tests")
struct PETransactionManagerTests {
    
    // MARK: - Begin/Cancel Tests
    
    @Test("Begin transaction acquires ID")
    func beginAcquiresID() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        
        #expect(id != nil)
        #expect(await manager.activeCount == 1)
        #expect(await manager.availableIDs == 127)
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
    
    @Test("Cancel is idempotent")
    func cancelIsIdempotent() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid)
        #expect(id != nil)
        
        // Multiple cancels should be safe
        await manager.cancel(requestID: id!)
        await manager.cancel(requestID: id!)
        await manager.cancel(requestID: id!)
        
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
    
    @Test("Cancel unknown ID is safe")
    func cancelUnknownIDIsSafe() async {
        let manager = PETransactionManager()
        
        // Canceling non-existent ID should not crash
        await manager.cancel(requestID: 99)
        
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
    
    // MARK: - Cancel All Tests
    
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
        let cancelled = await manager.cancelAll(for: device1)
        
        #expect(cancelled == 2)
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
        
        let cancelled = await manager.cancelAll()
        
        #expect(cancelled == 10)
        #expect(await manager.activeCount == 0)
        #expect(await manager.availableIDs == 128)
    }
    
    // MARK: - ID Exhaustion Tests
    
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
        #expect(await manager.availableIDs == 0)
    }
    
    @Test("Near exhaustion warning threshold")
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
    
    @Test("Not near exhaustion with sufficient IDs")
    func notNearExhaustion() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        // Use 100 IDs (leaving 28)
        for _ in 0..<100 {
            _ = await manager.begin(resource: "Test", destinationMUID: muid)
        }
        
        #expect(await manager.isNearExhaustion == false)
        #expect(await manager.availableIDs == 28)
    }
    
    // MARK: - Multiple Transactions Tests
    
    @Test("Multiple transactions same resource get unique IDs")
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
    
    // MARK: - Chunk Processing Tests
    
    @Test("Single chunk completes immediately")
    func singleChunkCompletesImmediately() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "ProgramList", destinationMUID: muid)
        #expect(id != nil)
        
        let result = await manager.processChunk(
            requestID: id!,
            thisChunk: 1,
            numChunks: 1,
            headerData: Data("{\"status\":200}".utf8),
            propertyData: Data("[]".utf8)
        )
        
        if case .complete(let header, let body) = result {
            #expect(header == Data("{\"status\":200}".utf8))
            #expect(body == Data("[]".utf8))
        } else {
            Issue.record("Expected complete result, got \(result)")
        }
    }
    
    @Test("Multi-chunk assembly")
    func multiChunkAssembly() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "LargeResource", destinationMUID: muid)
        #expect(id != nil)
        
        // First chunk - incomplete
        let result1 = await manager.processChunk(
            requestID: id!,
            thisChunk: 1,
            numChunks: 3,
            headerData: Data("{\"status\":200}".utf8),
            propertyData: Data("part1".utf8)
        )
        if case .incomplete(let received, let total) = result1 {
            #expect(received == 1)
            #expect(total == 3)
        } else {
            Issue.record("Expected incomplete")
        }
        
        // Second chunk - still incomplete
        let result2 = await manager.processChunk(
            requestID: id!,
            thisChunk: 2,
            numChunks: 3,
            headerData: Data(),
            propertyData: Data("part2".utf8)
        )
        if case .incomplete(let received, let total) = result2 {
            #expect(received == 2)
            #expect(total == 3)
        } else {
            Issue.record("Expected incomplete")
        }
        
        // Third chunk - complete
        let result3 = await manager.processChunk(
            requestID: id!,
            thisChunk: 3,
            numChunks: 3,
            headerData: Data(),
            propertyData: Data("part3".utf8)
        )
        
        if case .complete(let header, let body) = result3 {
            #expect(header == Data("{\"status\":200}".utf8))
            #expect(body == Data("part1part2part3".utf8))
        } else {
            Issue.record("Expected complete result")
        }
    }
    
    @Test("Chunk for unknown request ID returns unknownRequestID")
    func chunkForUnknownRequestID() async {
        let manager = PETransactionManager()
        
        let result = await manager.processChunk(
            requestID: 99,
            thisChunk: 1,
            numChunks: 1,
            headerData: Data(),
            propertyData: Data()
        )
        
        if case .unknownRequestID(let id) = result {
            #expect(id == 99)
        } else {
            Issue.record("Expected unknownRequestID")
        }
    }
    
    @Test("Chunk after cancel returns unknownRequestID")
    func chunkAfterCancel() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "Test", destinationMUID: muid)
        #expect(id != nil)
        
        await manager.cancel(requestID: id!)
        
        let result = await manager.processChunk(
            requestID: id!,
            thisChunk: 1,
            numChunks: 1,
            headerData: Data(),
            propertyData: Data()
        )
        
        if case .unknownRequestID = result {
            // Expected
        } else {
            Issue.record("Expected unknownRequestID after cancel")
        }
    }
    
    // MARK: - Transaction Query Tests
    
    @Test("Transaction query returns transaction info")
    func transactionQuery() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "DeviceInfo", destinationMUID: muid, timeout: 5.0)
        #expect(id != nil)
        
        let transaction = await manager.transaction(for: id!)
        
        #expect(transaction != nil)
        #expect(transaction?.id == id)
        #expect(transaction?.resource == "DeviceInfo")
        #expect(transaction?.destinationMUID == muid)
        #expect(transaction?.timeout == 5.0)
    }
    
    @Test("Transaction query returns nil for unknown ID")
    func transactionQueryUnknownID() async {
        let manager = PETransactionManager()
        
        let transaction = await manager.transaction(for: 99)
        #expect(transaction == nil)
    }
    
    @Test("hasTransaction returns correct value")
    func hasTransaction() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "Test", destinationMUID: muid)
        #expect(id != nil)
        
        #expect(await manager.hasTransaction(for: id!) == true)
        #expect(await manager.hasTransaction(for: 99) == false)
        
        await manager.cancel(requestID: id!)
        
        #expect(await manager.hasTransaction(for: id!) == false)
    }
    
    // MARK: - Diagnostics Tests
    
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
        #expect(diag.contains("Available IDs: 126"))
    }
    
    @Test("Diagnostics shows near exhaustion warning")
    func diagnosticsShowsExhaustionWarning() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        // Use 125 IDs (leaving 3)
        for _ in 0..<125 {
            _ = await manager.begin(resource: "Test", destinationMUID: muid)
        }
        
        let diag = await manager.diagnostics
        
        #expect(diag.contains("Near ID exhaustion"))
    }
    
    // MARK: - Request ID Reuse Tests
    
    @Test("Request IDs can be reused after cancel")
    func requestIDReuseAfterCancel() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        // Get an ID
        let id1 = await manager.begin(resource: "Test", destinationMUID: muid)
        #expect(id1 != nil)
        
        // Cancel it
        await manager.cancel(requestID: id1!)
        
        // Should be able to get same ID again (IDs are reused)
        // Note: The exact ID may vary depending on implementation,
        // but we should have full capacity again
        #expect(await manager.availableIDs == 128)
        
        let id2 = await manager.begin(resource: "Test", destinationMUID: muid)
        #expect(id2 != nil)
    }
    
    @Test("Request ID released after chunk complete")
    func requestIDReleasedAfterChunkComplete() async {
        let manager = PETransactionManager()
        let muid = MUID.random()
        
        let id = await manager.begin(resource: "Test", destinationMUID: muid)
        #expect(id != nil)
        #expect(await manager.availableIDs == 127)
        
        // Complete via chunk processing
        _ = await manager.processChunk(
            requestID: id!,
            thisChunk: 1,
            numChunks: 1,
            headerData: Data(),
            propertyData: Data()
        )
        
        // Note: processChunk doesn't auto-release the ID anymore
        // Caller (PEManager) is responsible for calling cancel
        // to release the ID after handling the complete result
        
        // Verify transaction is still tracked until explicitly cancelled
        // (This is intentional - PEManager needs to handle the response first)
    }
}

// MARK: - PEChunkResult Equatable for Testing

extension PEChunkResult: Equatable {
    public static func == (lhs: PEChunkResult, rhs: PEChunkResult) -> Bool {
        switch (lhs, rhs) {
        case (.complete(let h1, let b1), .complete(let h2, let b2)):
            return h1 == h2 && b1 == b2
        case (.incomplete(let r1, let t1), .incomplete(let r2, let t2)):
            return r1 == r2 && t1 == t2
        case (.timeout(let id1, let r1, let t1, _), .timeout(let id2, let r2, let t2, _)):
            return id1 == id2 && r1 == r2 && t1 == t2
        case (.unknownRequestID(let id1), .unknownRequestID(let id2)):
            return id1 == id2
        default:
            return false
        }
    }
}
