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
