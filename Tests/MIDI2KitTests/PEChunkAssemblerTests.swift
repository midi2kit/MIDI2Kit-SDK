//
//  PEChunkAssemblerTests.swift
//  MIDI2Kit
//
//  Tests for PE chunk assembly
//

import Testing
import Foundation
@testable import MIDI2PE

@Suite("PEChunkAssembler Tests")
struct PEChunkAssemblerTests {
    
    @Test("Single chunk returns complete immediately")
    func singleChunk() {
        var assembler = PEChunkAssembler()
        
        let header = Data("header".utf8)
        let body = Data("body".utf8)
        
        let result = assembler.addChunk(
            requestID: 1,
            thisChunk: 1,
            numChunks: 1,
            headerData: header,
            propertyData: body
        )
        
        if case .complete(let h, let b) = result {
            #expect(h == header)
            #expect(b == body)
        } else {
            Issue.record("Expected complete result")
        }
    }
    
    @Test("Multi-chunk assembly")
    func multiChunkAssembly() {
        var assembler = PEChunkAssembler()
        let header = Data("header".utf8)
        
        // Chunk 1
        let result1 = assembler.addChunk(
            requestID: 1,
            thisChunk: 1,
            numChunks: 3,
            headerData: header,
            propertyData: Data("AAA".utf8),
            resource: "test"
        )
        
        if case .incomplete(let received, let total) = result1 {
            #expect(received == 1)
            #expect(total == 3)
        } else {
            Issue.record("Expected incomplete after chunk 1")
        }
        
        // Chunk 2
        let result2 = assembler.addChunk(
            requestID: 1,
            thisChunk: 2,
            numChunks: 3,
            headerData: Data(),  // Empty header in subsequent chunks
            propertyData: Data("BBB".utf8)
        )
        
        if case .incomplete(let received, let total) = result2 {
            #expect(received == 2)
            #expect(total == 3)
        } else {
            Issue.record("Expected incomplete after chunk 2")
        }
        
        // Chunk 3 (final)
        let result3 = assembler.addChunk(
            requestID: 1,
            thisChunk: 3,
            numChunks: 3,
            headerData: Data(),
            propertyData: Data("CCC".utf8)
        )
        
        if case .complete(let h, let b) = result3 {
            #expect(h == header)  // Header from first chunk
            #expect(b == Data("AAABBBCCC".utf8))
        } else {
            Issue.record("Expected complete after chunk 3")
        }
    }
    
    @Test("Header preserved from first non-empty chunk")
    func headerPreservation() {
        var assembler = PEChunkAssembler()
        let header = Data("{\"status\":200}".utf8)
        
        // First chunk with header
        _ = assembler.addChunk(
            requestID: 5,
            thisChunk: 1,
            numChunks: 2,
            headerData: header,
            propertyData: Data("part1".utf8),
            resource: "test"
        )
        
        // Second chunk with empty header
        let result = assembler.addChunk(
            requestID: 5,
            thisChunk: 2,
            numChunks: 2,
            headerData: Data(),  // Device sends empty header
            propertyData: Data("part2".utf8)
        )
        
        if case .complete(let h, _) = result {
            #expect(h == header)  // Original header preserved
        } else {
            Issue.record("Expected complete result")
        }
    }
    
    @Test("Out of order chunks")
    func outOfOrderChunks() {
        var assembler = PEChunkAssembler()
        
        // Chunk 3 first
        _ = assembler.addChunk(
            requestID: 1,
            thisChunk: 3,
            numChunks: 3,
            headerData: Data(),
            propertyData: Data("CCC".utf8),
            resource: "test"
        )
        
        // Chunk 1
        _ = assembler.addChunk(
            requestID: 1,
            thisChunk: 1,
            numChunks: 3,
            headerData: Data("H".utf8),
            propertyData: Data("AAA".utf8)
        )
        
        // Chunk 2 (completes)
        let result = assembler.addChunk(
            requestID: 1,
            thisChunk: 2,
            numChunks: 3,
            headerData: Data(),
            propertyData: Data("BBB".utf8)
        )
        
        if case .complete(_, let b) = result {
            // Assembly should be in order 1,2,3
            #expect(b == Data("AAABBBCCC".utf8))
        } else {
            Issue.record("Expected complete result")
        }
    }
    
    @Test("Multiple concurrent requests")
    func concurrentRequests() {
        var assembler = PEChunkAssembler()
        
        // Start request 1
        _ = assembler.addChunk(requestID: 1, thisChunk: 1, numChunks: 2, headerData: Data("H1".utf8), propertyData: Data("A".utf8), resource: "r1")
        
        // Start request 2
        _ = assembler.addChunk(requestID: 2, thisChunk: 1, numChunks: 2, headerData: Data("H2".utf8), propertyData: Data("X".utf8), resource: "r2")
        
        // Complete request 2
        let result2 = assembler.addChunk(requestID: 2, thisChunk: 2, numChunks: 2, headerData: Data(), propertyData: Data("Y".utf8))
        
        if case .complete(let h, let b) = result2 {
            #expect(h == Data("H2".utf8))
            #expect(b == Data("XY".utf8))
        } else {
            Issue.record("Request 2 should be complete")
        }
        
        // Complete request 1
        let result1 = assembler.addChunk(requestID: 1, thisChunk: 2, numChunks: 2, headerData: Data(), propertyData: Data("B".utf8))
        
        if case .complete(let h, let b) = result1 {
            #expect(h == Data("H1".utf8))
            #expect(b == Data("AB".utf8))
        } else {
            Issue.record("Request 1 should be complete")
        }
    }
    
    @Test("Pending state tracking")
    func pendingStateTracking() {
        var assembler = PEChunkAssembler()
        
        #expect(!assembler.hasPending)
        #expect(assembler.pendingCount == 0)
        
        _ = assembler.addChunk(requestID: 1, thisChunk: 1, numChunks: 3, headerData: Data(), propertyData: Data(), resource: "test")
        
        #expect(assembler.hasPending)
        #expect(assembler.pendingCount == 1)
        
        assembler.cancel(requestID: 1)
        
        #expect(!assembler.hasPending)
        #expect(assembler.pendingCount == 0)
    }
    
    @Test("Cancel all pending")
    func cancelAll() {
        var assembler = PEChunkAssembler()
        
        _ = assembler.addChunk(requestID: 1, thisChunk: 1, numChunks: 2, headerData: Data(), propertyData: Data(), resource: "r1")
        _ = assembler.addChunk(requestID: 2, thisChunk: 1, numChunks: 2, headerData: Data(), propertyData: Data(), resource: "r2")
        
        #expect(assembler.pendingCount == 2)
        
        assembler.cancelAll()
        
        #expect(assembler.pendingCount == 0)
    }
}
