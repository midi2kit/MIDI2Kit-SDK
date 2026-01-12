//
//  PENotifyAssemblyTests.swift
//  MIDI2KitTests
//
//  Notify multi-chunk assembly tests (reorder/duplicate/missing).
//

import Testing
import Foundation
@testable import MIDI2Kit
@testable import MIDI2PE

private struct TimeoutError: Error {}

@Suite("PE Notify Chunk Assembly Tests")
struct PENotifyAssemblyTests {

    let sourceMUID = MUID(rawValue: 0x01020304)!
    let deviceMUID = MUID(rawValue: 0x05060708)!
    let destinationID = MIDIDestinationID(1)

    var deviceHandle: PEDeviceHandle {
        PEDeviceHandle(muid: deviceMUID, destination: destinationID, name: "TestDevice")
    }

    // MARK: - Helpers

    private func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimeoutError()
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private func buildCIMessageChunk(
        messageType: CIMessageType,
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        headerData: Data,
        propertyData: Data,
        numChunks: Int,
        thisChunk: Int
    ) -> [UInt8] {
        var msg: [UInt8] = [0xF0, 0x7E, 0x7F, 0x0D, messageType.rawValue, 0x02]
        msg.append(contentsOf: sourceMUID.bytes)
        msg.append(contentsOf: destinationMUID.bytes)
        msg.append(requestID & 0x7F)

        let headerSize = headerData.count
        msg.append(UInt8(headerSize & 0x7F))
        msg.append(UInt8((headerSize >> 7) & 0x7F))

        msg.append(UInt8(numChunks & 0x7F))
        msg.append(UInt8((numChunks >> 7) & 0x7F))

        msg.append(UInt8(thisChunk & 0x7F))
        msg.append(UInt8((thisChunk >> 7) & 0x7F))

        let dataSize = propertyData.count
        msg.append(UInt8(dataSize & 0x7F))
        msg.append(UInt8((dataSize >> 7) & 0x7F))

        msg.append(contentsOf: headerData)
        msg.append(contentsOf: propertyData)
        msg.append(0xF7)
        return msg
    }

    private func subscribe(
        manager: PEManager,
        transport: MockMIDITransport,
        resource: String,
        subscribeId: String
    ) async throws {
        let subscribeTask = Task {
            try await manager.subscribe(to: resource, on: deviceHandle, timeout: .milliseconds(200))
        }

        try await Task.sleep(for: .milliseconds(30))
        guard let sent = await transport.sentMessages.first else {
            subscribeTask.cancel()
            throw TimeoutError()
        }

        let requestID = sent.data[14] & 0x7F

        let header = Data("{\"status\":200,\"subscribeId\":\"\(subscribeId)\"}".utf8)
        let reply = buildCIMessageChunk(
            messageType: .peSubscribeReply,
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            headerData: header,
            propertyData: Data(),
            numChunks: 1,
            thisChunk: 1
        )

        await transport.injectReceived(reply)

        let response = try await subscribeTask.value
        #expect(response.isSuccess)
        #expect(response.subscribeId == subscribeId)
    }

    private func makeNotify3Chunks(
        subscribeId: String,
        resource: String,
        requestID: UInt8
    ) -> (n1: [UInt8], n2: [UInt8], n3: [UInt8]) {
        let header = Data("{\"subscribeId\":\"\(subscribeId)\",\"resource\":\"\(resource)\"}".utf8)

        let n1 = buildCIMessageChunk(
            messageType: .peNotify,
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            headerData: header,
            propertyData: Data("AAA".utf8),
            numChunks: 3,
            thisChunk: 1
        )
        let n2 = buildCIMessageChunk(
            messageType: .peNotify,
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            headerData: Data(),
            propertyData: Data("BBB".utf8),
            numChunks: 3,
            thisChunk: 2
        )
        let n3 = buildCIMessageChunk(
            messageType: .peNotify,
            sourceMUID: deviceMUID,
            destinationMUID: sourceMUID,
            requestID: requestID,
            headerData: Data(),
            propertyData: Data("CCC".utf8),
            numChunks: 3,
            thisChunk: 3
        )

        return (n1, n2, n3)
    }

    // MARK: - Tests

    @Test("Notify: out-of-order chunks are reassembled")
    func notifyOutOfOrderIsAssembled() async throws {
        let transport = MockMIDITransport()

        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            notifyAssemblyTimeout: 0.2,
            logger: NullMIDI2Logger()
        )
        await manager.startReceiving()

        let stream = await manager.startNotificationStream()

        try await subscribe(manager: manager, transport: transport, resource: "X-Thing", subscribeId: "sub-1")

        let (n1, n2, n3) = makeNotify3Chunks(subscribeId: "sub-1", resource: "X-Thing", requestID: 9)

        // reorder: 2 -> 1 -> 3
        await transport.injectReceived(n2)
        await transport.injectReceived(n1)
        await transport.injectReceived(n3)

        // Get one notification with timeout
        let notification = try await withTimeout(.milliseconds(300)) {
            var it = stream.makeAsyncIterator()
            guard let n = await it.next() else { throw TimeoutError() }
            return n
        }

        #expect(notification.subscribeId == "sub-1")
        #expect(notification.resource == "X-Thing")
        #expect(notification.data == Data("AAABBBCCC".utf8))

        // Explicit cleanup
        await manager.stopReceiving()
        await transport.shutdown()
    }

    @Test("Notify: duplicate chunks do not break assembly and yield only once")
    func notifyDuplicateChunkDoesNotDuplicateYield() async throws {
        let transport = MockMIDITransport()

        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            notifyAssemblyTimeout: 0.2,
            logger: NullMIDI2Logger()
        )
        await manager.startReceiving()

        try await subscribe(manager: manager, transport: transport, resource: "X-Thing", subscribeId: "sub-1")

        let stream = await manager.startNotificationStream()

        // Collect notifications with a bounded approach
        actor NotificationCollector {
            var items: [PENotification] = []
            func append(_ n: PENotification) { items.append(n) }
            var count: Int { items.count }
            var first: PENotification? { items.first }
        }

        let collector = NotificationCollector()

        // Task that collects notifications but can be cancelled
        let collectorTask = Task {
            var it = stream.makeAsyncIterator()
            while !Task.isCancelled {
                // Use a polling approach with small sleep to allow cancellation
                let next = await it.next()
                if let n = next {
                    await collector.append(n)
                } else {
                    break
                }
            }
        }

        let (n1, n2, n3) = makeNotify3Chunks(subscribeId: "sub-1", resource: "X-Thing", requestID: 10)

        // duplicate chunk1 (before completion)
        await transport.injectReceived(n1)
        await transport.injectReceived(n1)
        await transport.injectReceived(n2)
        await transport.injectReceived(n3)

        // Wait for first notification to arrive
        try await Task.sleep(for: .milliseconds(100))

        let collectedCount = await collector.count
        #expect(collectedCount == 1, Comment(rawValue: "Expected exactly 1 notification, got \(collectedCount)"))

        if let first = await collector.first {
            #expect(first.subscribeId == "sub-1")
            #expect(first.resource == "X-Thing")
            #expect(first.data == Data("AAABBBCCC".utf8))
        }

        // Wait a bit more to ensure no second notification
        try await Task.sleep(for: .milliseconds(100))

        let finalCount = await collector.count
        #expect(finalCount == 1, Comment(rawValue: "Expected still 1 notification after waiting, got \(finalCount)"))

        // Cleanup - cancel collector first, then stop manager
        collectorTask.cancel()
        await manager.stopReceiving()
        await transport.shutdown()
    }

    @Test("Notify: missing chunk -> pollTimeouts triggers timeout and clears pending")
    func notifyMissingChunkTimesOutViaPolling() async throws {
        let transport = MockMIDITransport()

        let manager = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            notifyAssemblyTimeout: 0.05,
            logger: NullMIDI2Logger()
        )
        await manager.startReceiving()

        try await subscribe(manager: manager, transport: transport, resource: "X-Thing", subscribeId: "sub-1")

        let stream = await manager.startNotificationStream()

        let (n1, _n2, n3) = makeNotify3Chunks(subscribeId: "sub-1", resource: "X-Thing", requestID: 33)

        // missing chunk2
        await transport.injectReceived(n1)
        await transport.injectReceived(n3)

        // Should not yield - try to get notification with short timeout
        var gotNotification = false
        do {
            _ = try await withTimeout(.milliseconds(80)) {
                var it = stream.makeAsyncIterator()
                guard let _ = await it.next() else { throw TimeoutError() }
                return true
            }
            gotNotification = true
        } catch is TimeoutError {
            // Expected - no notification due to missing chunk
        }

        #expect(!gotNotification, Comment(rawValue: "Expected no notification due to missing chunk"))

        // Pending should exist until we poll timeouts
        let pendingBefore = await manager.notifyPendingCountForTesting()
        #expect(pendingBefore >= 1)

        // Wait past timeout and poll
        try await Task.sleep(for: .milliseconds(80))

        let timeouts = await manager.pollNotifyTimeoutsForTesting()
        #expect(!timeouts.isEmpty)

        let hit = timeouts.contains { t in
            guard t.sourceMUID == deviceMUID else { return false }
            if case .timeout(let id, _, _, _) = t.result {
                return id == 33
            }
            return false
        }
        #expect(hit)

        let pendingAfter = await manager.notifyPendingCountForTesting()
        #expect(pendingAfter == 0)

        // Cleanup
        await manager.stopReceiving()
        await transport.shutdown()
    }
}
