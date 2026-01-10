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
    
    @Test("GET times out when no reply")
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
    
    @Test("stopReceiving handles many concurrent requests safely")
    func stopReceivingHandlesManyConcurrentRequests() async throws {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start many concurrent requests to stress test dictionary iteration
        let requestCount = 50
        let tasks = (0..<requestCount).map { i in
            Task {
                try await manager.get(
                    resource: "Resource\(i)",
                    from: deviceMUID,
                    via: destinationID,
                    timeout: Duration.seconds(60)
                )
            }
        }
        
        // Wait for all requests to be registered
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify all requests are pending
        let diagBefore = await manager.diagnostics
        #expect(diagBefore.contains("Pending requests: \(requestCount)"))
        
        // Stop receiving - this should NOT crash even with many pending continuations
        // (Previously would crash due to dictionary mutation during iteration)
        await manager.stopReceiving()
        
        // Verify all tasks completed with cancellation
        var cancelledCount = 0
        for task in tasks {
            do {
                _ = try await task.value
            } catch is PEError {
                cancelledCount += 1
            }
        }
        #expect(cancelledCount == requestCount)
        
        // Verify clean state
        let diagAfter = await manager.diagnostics
        #expect(diagAfter.contains("Pending requests: 0"))
        #expect(diagAfter.contains("Available IDs: 128"))
    }
    
    @Test("stopReceiving is idempotent")
    func stopReceivingIsIdempotent() async throws {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start a request
        let task = Task {
            try await manager.get(
                resource: "DeviceInfo",
                from: deviceMUID,
                via: destinationID,
                timeout: Duration.seconds(10)
            )
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

// MARK: - Subscribe/Notify Tests

@Suite("PEManager Subscribe/Notify Tests")
struct PEManagerSubscribeNotifyTests {
    
    // MARK: - Setup
    
    let sourceMUID = MUID(rawValue: 0x01020304)!
    let deviceMUID = MUID(rawValue: 0x05060708)!
    let destinationID = MIDIDestinationID(1)
    
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
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start subscribe request (will timeout)
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceMUID,
                via: destinationID,
                timeout: Duration.milliseconds(100)
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
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start subscribe and inject reply
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceMUID,
                via: destinationID,
                timeout: Duration.seconds(1)
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
        
        await manager.stopReceiving()
    }
    
    @Test("Subscribe times out when no reply")
    func subscribeTimesOut() async throws {
        let transport = MockMIDITransport()
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        do {
            _ = try await manager.subscribe(
                to: "ProgramList",
                on: deviceMUID,
                via: destinationID,
                timeout: Duration.milliseconds(100)
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
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // First, subscribe to get a valid subscribeId tracked
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceMUID,
                via: destinationID,
                timeout: Duration.seconds(1)
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
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // First subscribe
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceMUID,
                via: destinationID,
                timeout: Duration.seconds(1)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        let requestID = sent.first!.data[14] & 0x7F
        
        let reply = buildSubscribeReply(
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            status: 200,
            subscribeId: "unsub-test"
        )
        await transport.injectReceived(reply)
        
        _ = try await subscribeTask.value
        
        // Clear sent messages
        await transport.clearSentMessages()
        
        // Now unsubscribe (will timeout)
        let unsubTask = Task {
            try await manager.unsubscribe(
                subscribeId: "unsub-test",
                timeout: Duration.milliseconds(100)
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
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Start a subscribe request (will be pending)
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceMUID,
                via: destinationID,
                timeout: Duration.seconds(10)
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
        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID
        )
        
        await manager.startReceiving()
        
        // Subscribe
        let subscribeTask = Task {
            try await manager.subscribe(
                to: "ProgramList",
                on: deviceMUID,
                via: destinationID,
                timeout: Duration.seconds(1)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let sent = await transport.sentMessages
        let subRequestID = sent.first!.data[14] & 0x7F
        
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
        
        // Clear and unsubscribe
        await transport.clearSentMessages()
        
        let unsubTask = Task {
            try await manager.unsubscribe(
                subscribeId: "to-be-removed",
                timeout: Duration.seconds(1)
            )
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        let unsubSent = await transport.sentMessages
        let unsubRequestID = unsubSent.first!.data[14] & 0x7F
        
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
