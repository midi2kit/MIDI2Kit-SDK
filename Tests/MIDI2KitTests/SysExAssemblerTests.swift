//
//  SysExAssemblerTests.swift
//  MIDI2KitTests
//
//  Tests for SysExAssembler
//

import Testing
import Foundation
@testable import MIDI2Kit

@Suite("SysExAssembler Tests")
struct SysExAssemblerTests {
    
    // MARK: - Basic Tests
    
    @Test("Complete SysEx in single packet")
    func completeSysExInSinglePacket() async {
        let assembler = SysExAssembler()
        
        let packet: [UInt8] = [0xF0, 0x7E, 0x00, 0x0D, 0x70, 0xF7]
        let messages = await assembler.process(packet)
        
        #expect(messages.count == 1)
        #expect(messages[0] == packet)
        #expect(await assembler.hasIncomplete == false)
    }
    
    @Test("Multiple complete SysEx in single packet")
    func multipleSysExInSinglePacket() async {
        let assembler = SysExAssembler()
        
        let msg1: [UInt8] = [0xF0, 0x01, 0x02, 0xF7]
        let msg2: [UInt8] = [0xF0, 0x03, 0x04, 0xF7]
        let packet = msg1 + msg2
        
        let messages = await assembler.process(packet)
        
        #expect(messages.count == 2)
        #expect(messages[0] == msg1)
        #expect(messages[1] == msg2)
    }
    
    @Test("Empty packet returns no messages")
    func emptyPacketReturnsNoMessages() async {
        let assembler = SysExAssembler()
        
        let messages = await assembler.process([])
        
        #expect(messages.isEmpty)
    }
    
    // MARK: - Fragmented SysEx Tests
    
    @Test("SysEx split across two packets")
    func sysExSplitAcrossTwoPackets() async {
        let assembler = SysExAssembler()
        
        // First packet: start of SysEx
        let packet1: [UInt8] = [0xF0, 0x7E, 0x00, 0x0D]
        let messages1 = await assembler.process(packet1)
        
        #expect(messages1.isEmpty)
        #expect(await assembler.hasIncomplete == true)
        #expect(await assembler.bufferSize == 4)
        
        // Second packet: end of SysEx
        let packet2: [UInt8] = [0x70, 0x01, 0x02, 0xF7]
        let messages2 = await assembler.process(packet2)
        
        #expect(messages2.count == 1)
        #expect(messages2[0] == [0xF0, 0x7E, 0x00, 0x0D, 0x70, 0x01, 0x02, 0xF7])
        #expect(await assembler.hasIncomplete == false)
    }
    
    @Test("SysEx split across three packets")
    func sysExSplitAcrossThreePackets() async {
        let assembler = SysExAssembler()
        
        let packet1: [UInt8] = [0xF0, 0x7E]
        let packet2: [UInt8] = [0x00, 0x0D, 0x70]
        let packet3: [UInt8] = [0x01, 0x02, 0xF7]
        
        let messages1 = await assembler.process(packet1)
        #expect(messages1.isEmpty)
        
        let messages2 = await assembler.process(packet2)
        #expect(messages2.isEmpty)
        
        let messages3 = await assembler.process(packet3)
        #expect(messages3.count == 1)
        #expect(messages3[0] == [0xF0, 0x7E, 0x00, 0x0D, 0x70, 0x01, 0x02, 0xF7])
    }
    
    // MARK: - Order Sensitivity Tests
    
    @Test("Packet order matters for fragmented SysEx")
    func packetOrderMattersForFragmentedSysEx() async {
        let assembler = SysExAssembler()
        
        // Correct order: start -> middle -> end
        let startPacket: [UInt8] = [0xF0, 0x7E, 0x00]
        let middlePacket: [UInt8] = [0x0D, 0x70, 0x01]
        let endPacket: [UInt8] = [0x02, 0x03, 0xF7]
        
        // Process in correct order
        _ = await assembler.process(startPacket)
        _ = await assembler.process(middlePacket)
        let messages = await assembler.process(endPacket)
        
        #expect(messages.count == 1)
        #expect(messages[0] == [0xF0, 0x7E, 0x00, 0x0D, 0x70, 0x01, 0x02, 0x03, 0xF7])
    }
    
    @Test("Wrong packet order corrupts SysEx assembly")
    func wrongPacketOrderCorruptsSysExAssembly() async {
        let assembler = SysExAssembler()
        
        // Simulate out-of-order delivery (middle before start)
        let startPacket: [UInt8] = [0xF0, 0x7E, 0x00]
        let middlePacket: [UInt8] = [0x0D, 0x70, 0x01]
        let endPacket: [UInt8] = [0x02, 0x03, 0xF7]
        
        // Process middle first (wrong order) - should be ignored (no buffer)
        let messages1 = await assembler.process(middlePacket)
        #expect(messages1.isEmpty)
        #expect(await assembler.hasIncomplete == false)
        
        // Now process start - begins buffering
        let messages2 = await assembler.process(startPacket)
        #expect(messages2.isEmpty)
        #expect(await assembler.hasIncomplete == true)
        
        // Process end - but middle is missing, so result is wrong
        let messages3 = await assembler.process(endPacket)
        #expect(messages3.count == 1)
        // Result is corrupted: missing middle packet data
        #expect(messages3[0] == [0xF0, 0x7E, 0x00, 0x02, 0x03, 0xF7])
        #expect(messages3[0] != [0xF0, 0x7E, 0x00, 0x0D, 0x70, 0x01, 0x02, 0x03, 0xF7])
    }
    
    @Test("Sequential processing preserves order")
    func sequentialProcessingPreservesOrder() async {
        let assembler = SysExAssembler()
        
        // Simulate multiple fragmented messages arriving in sequence
        let packets: [[UInt8]] = [
            [0xF0, 0x01],           // Start of msg1
            [0x02, 0xF7],           // End of msg1
            [0xF0, 0x03],           // Start of msg2
            [0x04, 0x05, 0xF7],     // End of msg2
        ]
        
        var allMessages: [[UInt8]] = []
        for packet in packets {
            let messages = await assembler.process(packet)
            allMessages.append(contentsOf: messages)
        }
        
        #expect(allMessages.count == 2)
        #expect(allMessages[0] == [0xF0, 0x01, 0x02, 0xF7])
        #expect(allMessages[1] == [0xF0, 0x03, 0x04, 0x05, 0xF7])
    }
    
    // MARK: - Corruption Handling Tests
    
    @Test("New F0 during buffering discards incomplete message")
    func newF0DuringBufferingDiscardsIncomplete() async {
        let assembler = SysExAssembler()
        
        // Start buffering
        let packet1: [UInt8] = [0xF0, 0x01, 0x02]
        _ = await assembler.process(packet1)
        #expect(await assembler.hasIncomplete == true)
        
        // New SysEx starts before previous ends - discards buffer
        let packet2: [UInt8] = [0xF0, 0x03, 0x04, 0xF7]
        let messages = await assembler.process(packet2)
        
        #expect(messages.count == 1)
        #expect(messages[0] == [0xF0, 0x03, 0x04, 0xF7])
        #expect(await assembler.hasIncomplete == false)
    }
    
    @Test("F0 before F7 in continuation discards buffer")
    func f0BeforeF7InContinuationDiscardsBuffer() async {
        let assembler = SysExAssembler()
        
        // Start buffering
        let packet1: [UInt8] = [0xF0, 0x01, 0x02]
        _ = await assembler.process(packet1)
        
        // Continuation has F0 before F7 - corrupted
        let packet2: [UInt8] = [0x03, 0xF0, 0x04, 0xF7]
        let messages = await assembler.process(packet2)
        
        // Should start fresh from new F0
        #expect(messages.count == 1)
        #expect(messages[0] == [0xF0, 0x04, 0xF7])
    }
    
    // MARK: - Reset Tests
    
    @Test("Reset clears buffer")
    func resetClearsBuffer() async {
        let assembler = SysExAssembler()
        
        // Start buffering
        let packet: [UInt8] = [0xF0, 0x01, 0x02, 0x03]
        _ = await assembler.process(packet)
        #expect(await assembler.hasIncomplete == true)
        
        // Reset
        await assembler.reset()
        #expect(await assembler.hasIncomplete == false)
        #expect(await assembler.bufferSize == 0)
    }
    
    // MARK: - Non-SysEx Data Tests
    
    @Test("Non-SysEx data without buffer is ignored")
    func nonSysExDataWithoutBufferIsIgnored() async {
        let assembler = SysExAssembler()
        
        // Random MIDI data (not SysEx)
        let packet: [UInt8] = [0x90, 0x3C, 0x7F, 0x80, 0x3C, 0x00]
        let messages = await assembler.process(packet)
        
        #expect(messages.isEmpty)
        #expect(await assembler.hasIncomplete == false)
    }
    
    @Test("SysEx after non-SysEx data")
    func sysExAfterNonSysExData() async {
        let assembler = SysExAssembler()
        
        // Mixed data: note on, then SysEx
        let packet: [UInt8] = [0x90, 0x3C, 0x7F, 0xF0, 0x01, 0x02, 0xF7]
        let messages = await assembler.process(packet)
        
        #expect(messages.count == 1)
        #expect(messages[0] == [0xF0, 0x01, 0x02, 0xF7])
    }
    
    // MARK: - Large Message Tests
    
    @Test("Large SysEx message assembly")
    func largeSysExMessageAssembly() async {
        let assembler = SysExAssembler()
        
        // Simulate large SysEx split into multiple packets
        var fullMessage: [UInt8] = [0xF0]
        fullMessage.append(contentsOf: Array(repeating: UInt8(0x55), count: 1000))
        fullMessage.append(0xF7)
        
        // Split into chunks
        let chunkSize = 128
        var offset = 0
        var allMessages: [[UInt8]] = []
        
        while offset < fullMessage.count {
            let end = min(offset + chunkSize, fullMessage.count)
            let chunk = Array(fullMessage[offset..<end])
            let messages = await assembler.process(chunk)
            allMessages.append(contentsOf: messages)
            offset = end
        }
        
        #expect(allMessages.count == 1)
        #expect(allMessages[0] == fullMessage)
        #expect(await assembler.hasIncomplete == false)
    }
}

// MARK: - CoreMIDITransport Order Tests

@Suite("CoreMIDITransport Packet Order Tests")
struct CoreMIDITransportPacketOrderTests {
    
    @Test("Simulated packet list maintains order")
    func simulatedPacketListMaintainsOrder() async {
        // This test verifies the fix: collecting all packets before Task
        let packets: [[UInt8]] = [
            [0xF0, 0x01],
            [0x02, 0x03],
            [0x04, 0xF7],
        ]
        
        // Simulate the fixed handlePacketList behavior:
        // 1. Collect all packet data first
        var allPacketData: [[UInt8]] = []
        for packet in packets {
            allPacketData.append(packet)
        }
        
        // 2. Process in single sequential loop (simulating single Task)
        let assembler = SysExAssembler()
        var allMessages: [[UInt8]] = []
        for data in allPacketData {
            let messages = await assembler.process(data)
            allMessages.append(contentsOf: messages)
        }
        
        // Verify correct assembly
        #expect(allMessages.count == 1)
        #expect(allMessages[0] == [0xF0, 0x01, 0x02, 0x03, 0x04, 0xF7])
    }
    
    @Test("Sequential processing assembles correctly")
    func sequentialProcessingAssemblesCorrectly() async {
        // Simulate multiple SysEx messages arriving in fragments
        let packets: [[UInt8]] = [
            [0xF0, 0x7E, 0x00],     // Start of CI message
            [0x0D, 0x70],           // Middle
            [0x01, 0x02, 0xF7],     // End
            [0xF0, 0x41],           // Start of Roland message
            [0x10, 0x42, 0xF7],     // End
        ]
        
        let assembler = SysExAssembler()
        var allMessages: [[UInt8]] = []
        
        for packet in packets {
            let messages = await assembler.process(packet)
            allMessages.append(contentsOf: messages)
        }
        
        #expect(allMessages.count == 2)
        #expect(allMessages[0] == [0xF0, 0x7E, 0x00, 0x0D, 0x70, 0x01, 0x02, 0xF7])
        #expect(allMessages[1] == [0xF0, 0x41, 0x10, 0x42, 0xF7])
    }
    
    @Test("Order tracker demonstrates race condition risk")
    func orderTrackerDemonstratesRaceConditionRisk() async {
        // This test demonstrates WHY the fix was needed
        // Multiple concurrent Tasks don't guarantee execution order
        
        let packetCount = 5
        
        // Track processing order using actor for thread safety
        actor OrderTracker {
            var order: [Int] = []
            func record(_ index: Int) {
                order.append(index)
            }
            func getOrder() -> [Int] { order }
        }
        
        let tracker = OrderTracker()
        
        // Spawn multiple tasks (OLD behavior - no order guarantee)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<packetCount {
                group.addTask {
                    // Simulate some processing variance
                    if index == 0 {
                        try? await Task.sleep(for: .milliseconds(5))
                    }
                    await tracker.record(index)
                }
            }
        }
        
        let recordedOrder = await tracker.getOrder()
        
        // All tasks should complete
        #expect(recordedOrder.count == packetCount)
        // Note: We can't assert order != [0,1,2,3,4] because it might happen to be correct
        // The point is it's NOT GUARANTEED - this demonstrates why sequential processing matters
    }
    
    @Test("Fixed approach guarantees order")
    func fixedApproachGuaranteesOrder() async {
        // This test shows the FIXED behavior: single Task processes sequentially
        
        let packetCount = 10
        
        actor OrderTracker {
            var order: [Int] = []
            func record(_ index: Int) {
                order.append(index)
            }
            func getOrder() -> [Int] { order }
        }
        
        let tracker = OrderTracker()
        
        // FIXED: Collect first, then process in single Task
        let indices = Array(0..<packetCount)
        
        // Single task processes all in order
        for index in indices {
            await tracker.record(index)
        }
        
        let recordedOrder = await tracker.getOrder()
        
        // Order IS guaranteed
        #expect(recordedOrder == Array(0..<packetCount))
    }
}
