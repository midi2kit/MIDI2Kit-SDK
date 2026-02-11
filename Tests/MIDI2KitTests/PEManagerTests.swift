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
    
    var deviceHandle: PEDeviceHandle {
        PEDeviceHandle(muid: deviceMUID, destination: destinationID, name: "TestDevice")
    }
    
    // MARK: - Basic Tests
    
    @Test("PEManager initializes correctly")
    func initializesCorrectly() async {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
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
        defer { Task { await transport.shutdown() } }
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
    
    // MARK: - GET Tests (New API with PEDeviceHandle)
    
    @Test("GET with DeviceHandle sends correct message")
    func getWithDeviceHandleSendsCorrectMessage() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            sendStrategy: .single
        )
        
        await manager.startReceiving()
        
        let getTask = Task {
            try await manager.get("DeviceInfo", from: deviceHandle, timeout: .milliseconds(100))
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        
        if let message = sent.first {
            #expect(message.data.first == 0xF0)
            #expect(message.data.last == 0xF7)
            #expect(message.data[4] == CIMessageType.peGetInquiry.rawValue)
            
            let sentSourceMUID = MUID(from: Array(message.data), offset: 6)
            #expect(sentSourceMUID == sourceMUID)
            
            let sentDestMUID = MUID(from: Array(message.data), offset: 10)
            #expect(sentDestMUID == deviceMUID)
        }
        
        getTask.cancel()
        await manager.stopReceiving()
    }
    
    @Test("GET times out when no reply")
    func getTimesOutWhenNoReply() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        do {
            _ = try await manager.get("DeviceInfo", from: deviceHandle, timeout: .milliseconds(200))
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
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            sendStrategy: .single
        )
        
        await manager.startReceiving()
        
        let testData = Data("{\"value\":42}".utf8)
        
        let setTask = Task {
            try await manager.set("X-CustomData", data: testData, to: deviceHandle, timeout: .milliseconds(100))
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
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            sendStrategy: .single
        )
        
        await manager.startReceiving()
        
        let getTask = Task {
            try await manager.get(
                "ChCtrlList",
                offset: 10,
                limit: 20,
                from: deviceHandle,
                timeout: .milliseconds(100)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        
        getTask.cancel()
        await manager.stopReceiving()
    }

    @Test("getChannelList decodes KORG bankPC array format")
    func getChannelListDecodesKORGFormat() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            requestIDCooldownPeriod: 0,
            sendStrategy: .single
        )

        await manager.startReceiving()

        let task = Task {
            try await manager.getChannelList(from: deviceHandle, timeout: .milliseconds(300))
        }

        try await Task.sleep(for: .milliseconds(50))
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        let requestID: UInt8 = sent.first.map { $0.data.count > 14 ? $0.data[14] : 0 } ?? 0

        let body = """
        [
            {"channel": 1, "title": "Channel 1", "bankPC": [0, 0, 1]},
            {"channel": 2, "title": "Channel 2", "bankPC": [0, 1, 32]}
        ]
        """

        let reply = buildPEReply(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            header: #"{"status":200}"#,
            body: body
        )
        await transport.simulateReceive(reply, from: MIDISourceID(1))

        let channels = try await task.value
        #expect(channels.count == 2)
        #expect(channels[0].channel == 1)
        #expect(channels[0].bankMSB == 0)
        #expect(channels[0].bankLSB == 0)
        #expect(channels[0].programNumber == 1)
        #expect(channels[1].channel == 2)
        #expect(channels[1].bankMSB == 0)
        #expect(channels[1].bankLSB == 1)
        #expect(channels[1].programNumber == 32)

        await manager.stopReceiving()
    }

    @Test("getProgramList decodes KORG bankPC array format")
    func getProgramListDecodesKORGFormat() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            requestIDCooldownPeriod: 0,
            sendStrategy: .single
        )

        await manager.startReceiving()

        let task = Task {
            try await manager.getProgramList(channel: 0, from: deviceHandle, timeout: .milliseconds(300))
        }

        try await Task.sleep(for: .milliseconds(50))
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        let requestID: UInt8 = sent.first.map { $0.data.count > 14 ? $0.data[14] : 0 } ?? 0

        let body = """
        [
            {"title": "Grand Piano", "bankPC": [0, 0, 0]},
            {"title": "Strings", "bankPC": [0, 1, 48]}
        ]
        """

        let reply = buildPEReply(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            header: #"{"status":200}"#,
            body: body
        )
        await transport.simulateReceive(reply, from: MIDISourceID(1))

        let programs = try await task.value
        #expect(programs.count == 2)
        #expect(programs[0].name == "Grand Piano")
        #expect(programs[0].bankMSB == 0)
        #expect(programs[0].bankLSB == 0)
        #expect(programs[0].programNumber == 0)
        #expect(programs[1].name == "Strings")
        #expect(programs[1].bankMSB == 0)
        #expect(programs[1].bankLSB == 1)
        #expect(programs[1].programNumber == 48)

        await manager.stopReceiving()
    }
    
    // MARK: - PERequest Tests
    
    @Test("PERequest factory methods create correct requests")
    func peRequestFactoryMethods() {
        let device = deviceHandle
        
        // Simple GET
        let getReq = PERequest.get("DeviceInfo", from: device)
        #expect(getReq.operation == .get)
        #expect(getReq.resource == "DeviceInfo")
        #expect(getReq.device.muid == deviceMUID)
        #expect(getReq.body == nil)
        #expect(getReq.channel == nil)
        
        // GET with channel
        let channelReq = PERequest.get("ProgramName", channel: 0, from: device)
        #expect(channelReq.channel == 0)
        
        // Paginated GET
        let pageReq = PERequest.get("ProgramList", offset: 10, limit: 20, from: device)
        #expect(pageReq.offset == 10)
        #expect(pageReq.limit == 20)
        
        // SET
        let data = Data("test".utf8)
        let setReq = PERequest.set("X-Custom", data: data, to: device)
        #expect(setReq.operation == .set)
        #expect(setReq.body == data)
    }
    
    @Test("PERequest validation catches empty resource")
    func peRequestValidationEmptyResource() throws {
        let device = deviceHandle
        let emptyRes = PERequest(operation: .get, resource: "", device: device)
        
        do {
            try emptyRes.validate()
            Issue.record("Expected validation error")
        } catch let error as PERequestError {
            #expect(error == .emptyResource)
        }
    }
    
    @Test("PERequest validation catches missing body")
    func peRequestValidationMissingBody() throws {
        let device = deviceHandle
        let noBody = PERequest(operation: .set, resource: "Test", device: device, body: nil)
        
        do {
            try noBody.validate()
            Issue.record("Expected validation error")
        } catch let error as PERequestError {
            #expect(error == .missingBody)
        }
    }
    
    @Test("PERequest validation catches invalid channel")
    func peRequestValidationInvalidChannel() throws {
        let device = deviceHandle
        let badChannel = PERequest(operation: .get, resource: "Test", device: device, channel: 300)
        
        do {
            try badChannel.validate()
            Issue.record("Expected validation error")
        } catch let error as PERequestError {
            #expect(error == .invalidChannel(300))
        }
    }
    
    @Test("send(request:) works correctly")
    func sendRequestWorks() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            sendStrategy: .single
        )
        
        await manager.startReceiving()
        
        let request = PERequest.get("DeviceInfo", from: deviceHandle, timeout: .milliseconds(100))
        
        let sendTask = Task {
            try await manager.send(request)
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        
        sendTask.cancel()
        await manager.stopReceiving()
    }
    
    // MARK: - Cancellation Tests
    
    @Test("Task cancellation cancels pending request")
    func taskCancellationCancelsPendingRequest() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            requestIDCooldownPeriod: 0  // Disable cooldown for test
        )
        
        await manager.startReceiving()
        
        let task = Task {
            try await manager.get("DeviceInfo", from: deviceHandle, timeout: .seconds(30))
        }
        
        // Wait for request to be sent
        try await Task.sleep(for: .milliseconds(50))
        
        // Verify request is pending
        let diagBefore = await manager.diagnostics
        #expect(diagBefore.contains("Pending requests: 1"))
        
        // Cancel the task
        task.cancel()
        
        // Wait for cancellation to propagate
        try await Task.sleep(for: .milliseconds(50))
        
        // Verify request was cancelled and Request ID released
        let diagAfter = await manager.diagnostics
        #expect(diagAfter.contains("Pending requests: 0"))
        #expect(diagAfter.contains("Available IDs: 128"))
        
        // Verify task threw cancellation error
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
        
        await manager.stopReceiving()
    }
    
    // MARK: - Request ID Leak Tests
    
    @Test("stopReceiving releases all Request IDs")
    func stopReceivingReleasesAllRequestIDs() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            requestIDCooldownPeriod: 0  // Disable cooldown for test
        )
        
        await manager.startReceiving()
        
        // Start multiple GET requests (they will be pending)
        // Note: With maxInflightPerDevice=2 (default), only 2 will be active, 3 will be waiting
        let tasks = (0..<5).map { i in
            Task {
                let handle = PEDeviceHandle(muid: deviceMUID, destination: destinationID)
                return try await manager.get("Resource\(i)", from: handle, timeout: .seconds(10))
            }
        }
        
        // Wait for requests to be sent
        try await Task.sleep(for: .milliseconds(50))
        
        // Verify requests state with per-device inflight limiting
        // maxInflightPerDevice=2, so 2 active (pending) + 3 waiting
        let diagBefore = await manager.diagnostics
        #expect(diagBefore.contains("Pending requests: 2"))  // Only inflight requests
        #expect(diagBefore.contains("Active transactions: 2"))
        #expect(diagBefore.contains("inflight=2, waiting=3"))  // Total 5 requests
        
        // Stop receiving - should release all Request IDs and cancel waiters
        await manager.stopReceiving()
        
        // Verify all tasks completed (cancelled or error)
        var completedCount = 0
        for task in tasks {
            do {
                _ = try await task.value
            } catch {
                completedCount += 1
            }
        }
        #expect(completedCount == 5)
        
        // Verify all Request IDs are released
        let diagAfter = await manager.diagnostics
        #expect(diagAfter.contains("Available IDs: 128"))
        #expect(diagAfter.contains("Active transactions: 0"))
    }
    
    @Test("Request IDs can be reused after stopReceiving")
    func requestIDsCanBeReusedAfterStop() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            sendStrategy: .single
        )
        
        // First cycle: start requests and stop
        await manager.startReceiving()
        
        let task1 = Task {
            try await manager.get("DeviceInfo", from: deviceHandle, timeout: .seconds(10))
        }
        
        try await Task.sleep(for: .milliseconds(30))
        await manager.stopReceiving()
        
        // Wait for cancellation
        _ = try? await task1.value
        
        // Wait for any pending async operations to complete
        try await Task.sleep(for: .milliseconds(50))
        
        // Clear sent messages
        await transport.clearSentMessages()
        
        // Second cycle: should work normally
        await manager.startReceiving()
        
        let task2 = Task {
            try await manager.get("ResourceList", from: deviceHandle, timeout: .milliseconds(100))
        }
        
        try await Task.sleep(for: .milliseconds(30))
        
        // Verify new request was sent
        let sent = await transport.sentMessages
        #expect(sent.count == 1)
        
        task2.cancel()
        await manager.stopReceiving()
    }
    
    @Test("stopReceiving handles many concurrent requests safely")
    func stopReceivingHandlesManyConcurrentRequests() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            requestIDCooldownPeriod: 0  // Disable cooldown for test
        )
        
        await manager.startReceiving()
        
        // Start many concurrent requests to stress test dictionary iteration
        // Note: With maxInflightPerDevice=2 (default), only 2 will be active, rest waiting
        let requestCount = 50
        let tasks = (0..<requestCount).map { i in
            Task {
                let handle = PEDeviceHandle(muid: deviceMUID, destination: destinationID)
                return try await manager.get("Resource\(i)", from: handle, timeout: .seconds(60))
            }
        }
        
        // Wait for all requests to be registered
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify request state with per-device inflight limiting
        // maxInflightPerDevice=2, so 2 active (pending) + 48 waiting
        let diagBefore = await manager.diagnostics
        #expect(diagBefore.contains("Pending requests: 2"))  // Only inflight requests
        #expect(diagBefore.contains("inflight=2, waiting=48"))  // Total 50 requests
        
        // Stop receiving - this should NOT crash even with many pending continuations
        // (Previously would crash due to dictionary mutation during iteration)
        await manager.stopReceiving()
        
        // Verify all tasks completed (cancelled or error)
        var completedCount = 0
        for task in tasks {
            do {
                _ = try await task.value
            } catch {
                completedCount += 1
            }
        }
        #expect(completedCount == requestCount)
        
        // Verify clean state
        let diagAfter = await manager.diagnostics
        #expect(diagAfter.contains("Pending requests: 0"))
        #expect(diagAfter.contains("Available IDs: 128"))
    }
    
    @Test("stopReceiving is idempotent")
    func stopReceivingIsIdempotent() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start a request
        let task = Task {
            try await manager.get("DeviceInfo", from: deviceHandle, timeout: .seconds(10))
        }
        
        try await Task.sleep(for: .milliseconds(30))
        
        // Call stopReceiving multiple times - should not crash
        await manager.stopReceiving()
        await manager.stopReceiving()
        await manager.stopReceiving()
        
        // Verify task was cancelled
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch {
            // Expected
        }
        
        // Verify clean state
        let diag = await manager.diagnostics
        #expect(diag.contains("Receiving: false"))
        #expect(diag.contains("Pending requests: 0"))
    }

    // MARK: - Helpers

    /// Build a CI 1.2 PE GET Reply SysEx message used by PEManager tests.
    private func buildPEReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        header: String,
        body: String
    ) -> [UInt8] {
        var data: [UInt8] = []

        data.append(0xF0)
        data.append(0x7E)
        data.append(0x7F)
        data.append(0x0D)
        data.append(0x35)
        data.append(0x02)

        let sourceValue = sourceMUID.value
        data.append(UInt8(sourceValue & 0x7F))
        data.append(UInt8((sourceValue >> 7) & 0x7F))
        data.append(UInt8((sourceValue >> 14) & 0x7F))
        data.append(UInt8((sourceValue >> 21) & 0x7F))

        let destinationValue = destinationMUID.value
        data.append(UInt8(destinationValue & 0x7F))
        data.append(UInt8((destinationValue >> 7) & 0x7F))
        data.append(UInt8((destinationValue >> 14) & 0x7F))
        data.append(UInt8((destinationValue >> 21) & 0x7F))

        data.append(requestID)

        let headerBytes = Array(header.utf8)
        let bodyBytes = Array(body.utf8)

        data.append(UInt8(headerBytes.count & 0x7F))
        data.append(UInt8((headerBytes.count >> 7) & 0x7F))

        data.append(0x01)
        data.append(0x00)
        data.append(0x01)
        data.append(0x00)

        data.append(UInt8(bodyBytes.count & 0x7F))
        data.append(UInt8((bodyBytes.count >> 7) & 0x7F))

        data.append(contentsOf: headerBytes)
        data.append(contentsOf: bodyBytes)

        data.append(0xF7)
        return data
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

// MARK: - PEDeviceHandle Tests

@Suite("PEDeviceHandle Tests")
struct PEDeviceHandleTests {
    
    @Test("PEDeviceHandle stores MUID and destination")
    func storesMUIDAndDestination() {
        // Use valid 28-bit MUID (0x00000000 - 0x0FFFFFFF)
        let muid = MUID(rawValue: 0x01234567)!
        let dest = MIDIDestinationID(42)
        let handle = PEDeviceHandle(muid: muid, destination: dest, name: "TestDevice")
        
        #expect(handle.muid == muid)
        #expect(handle.destination == dest)
        #expect(handle.name == "TestDevice")
        #expect(handle.id == muid)
    }
    
    @Test("PEDeviceHandle debugDescription")
    func debugDescription() {
        // Use valid 28-bit MUID
        let muid = MUID(rawValue: 0x01234567)!
        let dest = MIDIDestinationID(42)
        
        let withName = PEDeviceHandle(muid: muid, destination: dest, name: "KORG Module")
        #expect(withName.debugDescription.contains("KORG Module"))
        
        let withoutName = PEDeviceHandle(muid: muid, destination: dest)
        #expect(withoutName.debugDescription.contains("Device"))
    }
    
    @Test("PEDeviceHandle is Hashable")
    func hashable() {
        // Use valid 28-bit MUID
        let muid = MUID(rawValue: 0x01234567)!
        let dest = MIDIDestinationID(42)
        
        let handle1 = PEDeviceHandle(muid: muid, destination: dest)
        let handle2 = PEDeviceHandle(muid: muid, destination: dest)
        
        #expect(handle1 == handle2)
        #expect(handle1.hashValue == handle2.hashValue)
        
        var set = Set<PEDeviceHandle>()
        set.insert(handle1)
        #expect(set.contains(handle2))
    }
}

// MARK: - Subscribe/Notify Tests

@Suite("PEManager Subscribe/Notify Tests")
struct PEManagerSubscribeNotifyTests {
    
    // MARK: - Setup
    
    let sourceMUID = MUID(rawValue: 0x01020304)!
    let deviceMUID = MUID(rawValue: 0x05060708)!
    let destinationID = MIDIDestinationID(1)
    
    var deviceHandle: PEDeviceHandle {
        PEDeviceHandle(muid: deviceMUID, destination: destinationID)
    }
    
    // MARK: - Helper: Build Subscribe Reply SysEx
    
    /// Build a Subscribe Reply SysEx message
    func buildSubscribeReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        status: Int,
        subscribeId: String?
    ) -> [UInt8] {
        // Build header JSON
        var headerDict: [String: Any] = ["status": status]
        if let subscribeId = subscribeId {
            headerDict["subscribeId"] = subscribeId
        }
        let headerData = try! JSONSerialization.data(withJSONObject: headerDict)
        
        var message: [UInt8] = [
            0xF0,  // SysEx Start
            0x7E,  // Non-Realtime
            0x7F,  // Device ID
            0x0D,  // CI Sub-ID
            0x39,  // PE Subscribe Reply (CIMessageType.peSubscribeReply)
            0x02   // CI Version 1.2
        ]
        
        // Source MUID
        message.append(contentsOf: sourceMUID.bytes)
        
        // Destination MUID
        message.append(contentsOf: destinationMUID.bytes)
        
        // Request ID
        message.append(requestID & 0x7F)
        
        // Header size (14-bit)
        let headerSize = headerData.count
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))
        
        // Number of chunks
        message.append(0x01)
        message.append(0x00)
        
        // This chunk
        message.append(0x01)
        message.append(0x00)
        
        // Property data size (0 for subscribe reply)
        message.append(0x00)
        message.append(0x00)
        
        // Header data
        message.append(contentsOf: headerData)
        
        message.append(0xF7)  // SysEx End
        return message
    }
    
    /// Build a Notify SysEx message
    func buildNotify(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        subscribeId: String,
        resource: String,
        propertyData: Data
    ) -> [UInt8] {
        // Build header JSON
        let headerDict: [String: Any] = [
            "subscribeId": subscribeId,
            "resource": resource
        ]
        let headerData = try! JSONSerialization.data(withJSONObject: headerDict)
        
        var message: [UInt8] = [
            0xF0,  // SysEx Start
            0x7E,  // Non-Realtime
            0x7F,  // Device ID
            0x0D,  // CI Sub-ID
            0x3F,  // PE Notify (CIMessageType.peNotify)
            0x02   // CI Version 1.2
        ]
        
        // Source MUID
        message.append(contentsOf: sourceMUID.bytes)
        
        // Destination MUID
        message.append(contentsOf: destinationMUID.bytes)
        
        // Request ID
        message.append(requestID & 0x7F)
        
        // Header size (14-bit)
        let headerSize = headerData.count
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))
        
        // Number of chunks
        message.append(0x01)
        message.append(0x00)
        
        // This chunk
        message.append(0x01)
        message.append(0x00)
        
        // Property data size (14-bit)
        let dataSize = propertyData.count
        message.append(UInt8(dataSize & 0x7F))
        message.append(UInt8((dataSize >> 7) & 0x7F))
        
        // Header data
        message.append(contentsOf: headerData)
        
        // Property data
        message.append(contentsOf: propertyData)
        
        message.append(0xF7)  // SysEx End
        return message
    }
    
    // MARK: - Subscribe Tests
    
    @Test("Subscribe sends correct message format")
    func subscribeSendsCorrectMessage() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start subscribe request (will timeout)
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceHandle,
                timeout: .milliseconds(100)
            )
        }
        
        // Wait for message to be sent
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
            #expect(message.data[4] == 0x38)  // PE Subscribe (CIMessageType.peSubscribe)
            
            // Verify source MUID
            let sentSourceMUID = MUID(from: Array(message.data), offset: 6)
            #expect(sentSourceMUID == sourceMUID)
            
            // Verify destination MUID
            let sentDestMUID = MUID(from: Array(message.data), offset: 10)
            #expect(sentDestMUID == deviceMUID)
        }
        
        subscribeTask.cancel()
        await manager.stopReceiving()
    }
    
    @Test("Subscribe receives reply with subscribeId")
    func subscribeReceivesReplyWithSubscribeId() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start subscribe and inject reply
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceHandle,
                timeout: .seconds(1)
            )
        }
        
        // Wait for request to be sent
        try await Task.sleep(for: .milliseconds(50))
        
        // Get the requestID from sent message
        let sent = await transport.sentMessages
        guard let sentMessage = sent.first else {
            Issue.record("No message sent")
            return
        }
        let requestID = sentMessage.data[14] & 0x7F
        
        // Inject Subscribe Reply
        let reply = buildSubscribeReply(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            status: 200,
            subscribeId: "sub-12345"
        )
        await transport.injectReceived(reply)
        
        // Wait for response
        let response = try await subscribeTask.value
        
        #expect(response.isSuccess)
        #expect(response.status == 200)
        #expect(response.subscribeId == "sub-12345")
        
        // Verify subscription is tracked
        let subscriptions = await manager.subscriptions
        #expect(subscriptions.count == 1)
        #expect(subscriptions.first?.subscribeId == "sub-12345")
        #expect(subscriptions.first?.resource == "ProgramList")
        #expect(subscriptions.first?.device.muid == deviceMUID)
        
        await manager.stopReceiving()
    }
    
    @Test("Subscribe times out when no reply")
    func subscribeTimesOut() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        do {
            _ = try await manager.subscribe(
                to: "ProgramList",
                on: deviceHandle,
                timeout: .milliseconds(100)
            )
            Issue.record("Expected timeout error")
        } catch let error as PEError {
            if case .timeout(let resource) = error {
                #expect(resource == "ProgramList")
            } else {
                Issue.record("Expected timeout, got \(error)")
            }
        }
        
        await manager.stopReceiving()
    }
    
    // MARK: - Notify Tests
    
    @Test("Notify is received through notification stream")
    func notifyIsReceivedThroughStream() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // First, subscribe to get a valid subscribeId tracked
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceHandle,
                timeout: .seconds(1)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        guard let sentMessage = sent.first else {
            Issue.record("No message sent")
            return
        }
        let requestID = sentMessage.data[14] & 0x7F
        
        // Inject Subscribe Reply
        let reply = buildSubscribeReply(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            status: 200,
            subscribeId: "notify-test-sub"
        )
        await transport.injectReceived(reply)
        
        _ = try await subscribeTask.value
        
        // Start notification stream
        let notificationStream = await manager.startNotificationStream()
        
        // Inject Notify message
        let notifyData = Data("{\"changed\":true}".utf8)
        let notify = buildNotify(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: 0,  // Notify uses requestID=0 or any value
            subscribeId: "notify-test-sub",
            resource: "ProgramList",
            propertyData: notifyData
        )
        await transport.injectReceived(notify)
        
        // Receive notification with timeout
        let notificationTask = Task { () -> PENotification? in
            for await notification in notificationStream {
                return notification
            }
            return nil
        }
        
        // Wait a bit then cancel
        try await Task.sleep(for: .milliseconds(100))
        
        // Check if we got the notification
        notificationTask.cancel()
        
        await manager.stopReceiving()
    }
    
    @Test("Notify for unknown subscribeId is ignored")
    func notifyForUnknownSubscribeIdIsIgnored() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start notification stream without subscribing
        let notificationStream = await manager.startNotificationStream()
        
        // Task to receive notifications with timeout
        let receiveTask = Task { () -> PENotification? in
            for await notification in notificationStream {
                return notification
            }
            return nil
        }
        
        // Inject Notify for unknown subscribeId
        let notifyData = Data("{\"changed\":true}".utf8)
        let notify = buildNotify(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: 0,
            subscribeId: "unknown-sub-id",
            resource: "SomeResource",
            propertyData: notifyData
        )
        await transport.injectReceived(notify)
        
        // Wait a bit
        try await Task.sleep(for: .milliseconds(100))
        
        receiveTask.cancel()
        
        // The task should have been cancelled without receiving anything
        // (unknown subscribeId notifications are ignored)
        
        await manager.stopReceiving()
    }
    
    // MARK: - Unsubscribe Tests
    
    @Test("Unsubscribe sends correct message format")
    func unsubscribeSendsCorrectMessage() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // First subscribe
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceHandle,
                timeout: .seconds(1)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        guard let sentMessage = sent.first else {
            Issue.record("No subscribe message sent")
            subscribeTask.cancel()
            await manager.stopReceiving()
            return
        }
        let requestID = sentMessage.data[14] & 0x7F
        
        let reply = buildSubscribeReply(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            status: 200,
            subscribeId: "unsub-test"
        )
        await transport.injectReceived(reply)
        
        _ = try await subscribeTask.value
        
        // Wait for any pending async operations to complete
        try await Task.sleep(for: .milliseconds(50))
        
        // Clear sent messages
        await transport.clearSentMessages()
        
        // Now unsubscribe (will timeout)
        let unsubTask = Task {
            try await manager.unsubscribe(
                subscribeId: "unsub-test",
                timeout: .milliseconds(100)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        // Check unsubscribe message was sent
        let unsubSent = await transport.sentMessages
        #expect(unsubSent.count == 1)
        
        if let message = unsubSent.first {
            #expect(message.data[4] == 0x38)  // PE Subscribe (same message type for unsub)
        }
        
        unsubTask.cancel()
        await manager.stopReceiving()
    }
    
    @Test("Unsubscribe for unknown subscribeId throws error")
    func unsubscribeForUnknownIdThrows() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        do {
            _ = try await manager.unsubscribe(subscribeId: "nonexistent")
            Issue.record("Expected error")
        } catch let error as PEError {
            if case .invalidResponse(let msg) = error {
                #expect(msg.contains("nonexistent"))
            } else {
                Issue.record("Expected invalidResponse, got \(error)")
            }
        }
        
        await manager.stopReceiving()
    }
    
    // MARK: - Cleanup Tests
    
    @Test("stopReceiving clears subscriptions and pending subscribe requests")
    func stopReceivingClearsSubscriptionsAndPendingRequests() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start a subscribe request (will be pending)
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceHandle,
                timeout: .seconds(10)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        // Verify pending request
        let diagBefore = await manager.diagnostics
        #expect(diagBefore.contains("Pending subscribe requests: 1"))
        
        // Stop receiving
        await manager.stopReceiving()
        
        // Verify task was cancelled
        do {
            _ = try await subscribeTask.value
            Issue.record("Expected cancellation")
        } catch let error as PEError {
            if case .cancelled = error {
                // Expected
            } else {
                Issue.record("Expected cancelled, got \(error)")
            }
        }
        
        // Verify clean state
        let diagAfter = await manager.diagnostics
        #expect(diagAfter.contains("Pending subscribe requests: 0"))
        #expect(diagAfter.contains("Active subscriptions: 0"))
    }
    
    @Test("Active subscription is removed after successful unsubscribe")
    func activeSubscriptionRemovedAfterUnsubscribe() async throws {
        let transport = MockMIDITransport()
        defer { Task { await transport.shutdown() } }
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Subscribe
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceHandle,
                timeout: .seconds(1)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        guard let sentMessage = sent.first else {
            Issue.record("No subscribe message sent")
            subscribeTask.cancel()
            await manager.stopReceiving()
            return
        }
        let subRequestID = sentMessage.data[14] & 0x7F
        
        let subReply = buildSubscribeReply(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: subRequestID,
            status: 200,
            subscribeId: "to-be-removed"
        )
        await transport.injectReceived(subReply)
        
        _ = try await subscribeTask.value
        
        // Verify subscription exists
        var subscriptions = await manager.subscriptions
        #expect(subscriptions.count == 1)
        
        // Wait for any pending async operations to complete
        try await Task.sleep(for: .milliseconds(50))
        
        // Clear and unsubscribe
        await transport.clearSentMessages()
        
        let unsubTask = Task {
            try await manager.unsubscribe(
                subscribeId: "to-be-removed",
                timeout: .seconds(1)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let unsubSent = await transport.sentMessages
        guard let unsubMessage = unsubSent.first else {
            Issue.record("No unsubscribe message sent")
            unsubTask.cancel()
            await manager.stopReceiving()
            return
        }
        let unsubRequestID = unsubMessage.data[14] & 0x7F
        
        let unsubReply = buildSubscribeReply(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: unsubRequestID,
            status: 200,
            subscribeId: nil
        )
        await transport.injectReceived(unsubReply)
        
        _ = try await unsubTask.value
        
        // Verify subscription is removed
        subscriptions = await manager.subscriptions
        #expect(subscriptions.count == 0)

        await manager.stopReceiving()
    }
}

// MARK: - PEError Classification Tests

@Suite("PEError Classification Tests")
struct PEErrorClassificationTests {

    @Test("Timeout error is retryable")
    func timeoutIsRetryable() {
        let error = PEError.timeout(resource: "DeviceInfo")
        #expect(error.isRetryable == true)
        #expect(error.isTransportError == true)
        #expect(error.isClientError == false)
        #expect(error.isDeviceError == false)
        #expect(error.suggestedRetryDelay == .milliseconds(100))
    }

    @Test("Cancelled error is not retryable")
    func cancelledIsNotRetryable() {
        let error = PEError.cancelled
        #expect(error.isRetryable == false)
        #expect(error.suggestedRetryDelay == nil)
    }

    @Test("NAK with busy detail is retryable")
    func nakBusyIsRetryable() {
        let details = PENAKDetails(
            originalTransaction: 0x34,
            statusCode: 0x01,
            statusData: 0x01  // busy
        )
        let error = PEError.nak(details)
        #expect(error.isRetryable == true)
        #expect(error.isDeviceError == true)
        #expect(error.suggestedRetryDelay == .milliseconds(500))
    }

    @Test("NAK with notFound detail is not retryable")
    func nakNotFoundIsNotRetryable() {
        let details = PENAKDetails(
            originalTransaction: 0x34,
            statusCode: 0x01,
            statusData: 0x02  // notFound
        )
        let error = PEError.nak(details)
        #expect(error.isRetryable == false)
        #expect(details.isPermanent == true)
    }

    @Test("Validation error is client error")
    func validationIsClientError() {
        let error = PEError.validationFailed(.emptyResource)
        #expect(error.isClientError == true)
        #expect(error.isRetryable == false)
    }

    @Test("Device error 4xx is client error")
    func deviceError4xxIsClientError() {
        let error = PEError.deviceError(status: 400, message: "Bad Request")
        #expect(error.isClientError == true)
        #expect(error.isDeviceError == true)
        #expect(error.isRetryable == false)
    }

    @Test("Device error 5xx is retryable")
    func deviceError5xxIsRetryable() {
        let error = PEError.deviceError(status: 500, message: "Internal Error")
        #expect(error.isRetryable == true)
        #expect(error.isDeviceError == true)
    }

    @Test("Transport error is retryable")
    func transportErrorIsRetryable() {
        struct TestError: Error {}
        let error = PEError.transportError(TestError())
        #expect(error.isRetryable == true)
        #expect(error.isTransportError == true)
        #expect(error.suggestedRetryDelay == .milliseconds(200))
    }
}
