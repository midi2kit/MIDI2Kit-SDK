//
//  PEManagerTests.swift
//  MIDI2KitTests
//
//  Tests for PEManager
//

import Testing
import Foundation
@testable import MIDI2Kit

@Suite("PEManager Tests")
struct PEManagerTests {
    
    // MARK: - Setup
    
    let sourceMUID = MUID(rawValue: 0x01020304)!
    let deviceMUID = MUID(rawValue: 0x05060708)!
    let destinationID = MIDIDestinationID(1)
    
    // MARK: - Basic Tests
    
    @Test("PEManager initializes correctly")
    func initializesCorrectly() async {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        let diag = await manager.diagnostics
        #expect(diag.contains("Source MUID: \(sourceMUID)"))
        #expect(diag.contains("Receiving: false"))
    }
    
    @Test("PEManager starts and stops receiving")
    func startsAndStopsReceiving() async {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        var diag = await manager.diagnostics
        #expect(diag.contains("Receiving: true"))
        
        await manager.stopReceiving()
        diag = await manager.diagnostics
        #expect(diag.contains("Receiving: false"))
    }
    
    // MARK: - GET Tests
    
    @Test("GET sends correct message format")
    func getSendsCorrectMessage() async throws {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start GET request (will timeout, but we can check sent message)
        let getTask = Task {
            try await manager.get(
                resource: "DeviceInfo",
                from: deviceMUID,
                via: destinationID,
                timeout: Duration.milliseconds(100)
            )
        }
        
        // Wait a bit for message to be sent
        try await Task.sleep(for: .milliseconds(50))
        
        // Check sent message
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        
        if let message = sent.first {
            // Verify SysEx framing
            #expect(message.data.first == 0xF0)
            #expect(message.data.last == 0xF7)
            
            // Verify CI header
            #expect(message.data[1] == 0x7E)  // Non-Realtime
            #expect(message.data[3] == 0x0D)  // CI Sub-ID
            #expect(message.data[4] == CIMessageType.peGetInquiry.rawValue)
            
            // Verify source MUID
            let sentSourceMUID = MUID(from: Array(message.data), offset: 6)
            #expect(sentSourceMUID == sourceMUID)
            
            // Verify destination MUID
            let sentDestMUID = MUID(from: Array(message.data), offset: 10)
            #expect(sentDestMUID == deviceMUID)
        }
        
        // Cancel the task (will timeout anyway)
        getTask.cancel()
        await manager.stopReceiving()
    }
    
    // TEMPORARILY DISABLED - investigating crash
    @Test("GET times out when no reply", .disabled("Investigating segfault"))
    func getTimesOutWhenNoReply() async throws {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        do {
            _ = try await manager.get(
                resource: "DeviceInfo",
                from: deviceMUID,
                via: destinationID,
                timeout: Duration.milliseconds(200)
            )
            Issue.record("Expected timeout error")
        } catch let error as PEError {
            if case .timeout = error {
                // Expected
            } else {
                Issue.record("Expected timeout, got \(error)")
            }
        }
        
        await manager.stopReceiving()
    }
    
    // MARK: - SET Tests
    
    @Test("SET sends correct message format")
    func setSendsCorrectMessage() async throws {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        let testData = Data("{\"value\":42}".utf8)
        
        let setTask = Task {
            try await manager.set(
                resource: "X-CustomData",
                data: testData,
                to: deviceMUID,
                via: destinationID,
                timeout: Duration.milliseconds(100)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        
        if let message = sent.first {
            #expect(message.data[4] == CIMessageType.peSetInquiry.rawValue)
        }
        
        setTask.cancel()
        await manager.stopReceiving()
    }
    
    // MARK: - Paginated GET Tests
    
    @Test("Paginated GET sends offset and limit")
    func paginatedGetSendsOffsetAndLimit() async throws {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        let getTask = Task {
            try await manager.get(
                resource: "ChCtrlList",
                offset: 10,
                limit: 20,
                from: deviceMUID,
                via: destinationID,
                timeout: Duration.milliseconds(100)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        
        getTask.cancel()
        await manager.stopReceiving()
    }
    
    // MARK: - Request ID Leak Tests
    
    @Test("stopReceiving releases all Request IDs")
    func stopReceivingReleasesAllRequestIDs() async throws {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start multiple GET requests (they will be pending)
        let tasks = (0..<5).map { i in
            Task {
                try await manager.get(
                    resource: "Resource\(i)",
                    from: deviceMUID,
                    via: destinationID,
                    timeout: Duration.seconds(10)  // Long timeout
                )
            }
        }
        
        // Wait for requests to be sent
        try await Task.sleep(for: .milliseconds(50))
        
        // Verify requests are pending
        let diagBefore = await manager.diagnostics
        #expect(diagBefore.contains("Pending requests: 5"))
        #expect(diagBefore.contains("Active transactions: 5"))
        
        // Stop receiving - should release all Request IDs
        await manager.stopReceiving()
        
        // Verify all tasks were cancelled
        for task in tasks {
            do {
                _ = try await task.value
                Issue.record("Expected cancellation error")
            } catch let error as PEError {
                if case .cancelled = error {
                    // Expected
                } else {
                    Issue.record("Expected cancelled, got \(error)")
                }
            }
        }
        
        // Verify all Request IDs are released
        let diagAfter = await manager.diagnostics
        #expect(diagAfter.contains("Available IDs: 128"))
        #expect(diagAfter.contains("Active transactions: 0"))
    }
    
    @Test("Request IDs can be reused after stopReceiving")
    func requestIDsCanBeReusedAfterStop() async throws {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        // First cycle: start requests and stop
        await manager.startReceiving()
        
        let task1 = Task {
            try await manager.get(
                resource: "DeviceInfo",
                from: deviceMUID,
                via: destinationID,
                timeout: Duration.seconds(10)
            )
        }
        
        try await Task.sleep(for: .milliseconds(30))
        await manager.stopReceiving()
        
        // Wait for cancellation
        _ = try? await task1.value
        
        // Clear sent messages
        await transport.clearSentMessages()
        
        // Second cycle: should work normally
        await manager.startReceiving()
        
        let task2 = Task {
            try await manager.get(
                resource: "ResourceList",
                from: deviceMUID,
                via: destinationID,
                timeout: Duration.milliseconds(100)
            )
        }
        
        try await Task.sleep(for: .milliseconds(30))
        
        // Verify new request was sent
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        
        task2.cancel()
        await manager.stopReceiving()
    }
}

// MARK: - PEResponse Tests

@Suite("PEResponse Tests")
struct PEResponseTests {
    
    @Test("isSuccess for 2xx status codes")
    func isSuccessFor2xx() {
        let header: PEHeader? = nil
        #expect(PEResponse(status: 200, header: header, body: Data()).isSuccess)
        #expect(PEResponse(status: 202, header: header, body: Data()).isSuccess)
        #expect(!PEResponse(status: 400, header: header, body: Data()).isSuccess)
        #expect(!PEResponse(status: 500, header: header, body: Data()).isSuccess)
    }
    
    @Test("isError for 4xx and 5xx status codes")
    func isErrorFor4xx5xx() {
        let header: PEHeader? = nil
        #expect(!PEResponse(status: 200, header: header, body: Data()).isError)
        #expect(PEResponse(status: 400, header: header, body: Data()).isError)
        #expect(PEResponse(status: 404, header: header, body: Data()).isError)
        #expect(PEResponse(status: 500, header: header, body: Data()).isError)
    }
    
    @Test("bodyString returns UTF8 string")
    func bodyStringReturnsUTF8() {
        let body = Data("{\"test\":\"value\"}".utf8)
        let header: PEHeader? = nil
        let response = PEResponse(status: 200, header: header, body: body)
        #expect(response.bodyString == "{\"test\":\"value\"}")
    }
}
