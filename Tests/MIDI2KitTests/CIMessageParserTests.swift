//
//  CIMessageParserTests.swift
//  MIDI2KitTests
//
//  Tests for CIMessageParser, especially boundary conditions
//

import Testing
import Foundation
@testable import MIDI2CI
@testable import MIDI2Core

@Suite("CIMessageParser Tests")
struct CIMessageParserTests {
    
    // MARK: - parseNAK Tests
    
    @Test("parseNAK with minimum payload (3 bytes)")
    func parseNAKMinimum() {
        // Minimum valid: originalTransaction, statusCode, statusData
        let payload: [UInt8] = [0x10, 0x01, 0x02]
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result != nil)
        #expect(result?.originalTransaction == 0x10)
        #expect(result?.statusCode == 0x01)
        #expect(result?.statusData == 0x02)
        #expect(result?.nakDetails.isEmpty == true)
        #expect(result?.messageText == nil)
    }
    
    @Test("parseNAK with insufficient payload (2 bytes)")
    func parseNAKTooShort() {
        let payload: [UInt8] = [0x10, 0x01]
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result == nil)
    }
    
    @Test("parseNAK with empty payload")
    func parseNAKEmpty() {
        let payload: [UInt8] = []
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result == nil)
    }
    
    @Test("parseNAK with partial NAK details (7 bytes)")
    func parseNAKPartialDetails() {
        // 7 bytes: base(3) + partial details(4) - not enough for full details
        let payload: [UInt8] = [0x10, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD]
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result != nil)
        #expect(result?.originalTransaction == 0x10)
        #expect(result?.nakDetails.isEmpty == true)  // Need 8 bytes for details
        #expect(result?.messageText == nil)
    }
    
    @Test("parseNAK with full NAK details (8 bytes)")
    func parseNAKFullDetails() {
        // 8 bytes: base(3) + details(5)
        let payload: [UInt8] = [0x10, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result != nil)
        #expect(result?.nakDetails == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE])
        #expect(result?.messageText == nil)
    }
    
    @Test("parseNAK with 9 bytes (details but no message length)")
    func parseNAK9Bytes() {
        // 9 bytes: base(3) + details(5) + partial messageLength(1)
        // This was the crashing case before the fix
        let payload: [UInt8] = [0x10, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x05]
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result != nil)
        #expect(result?.nakDetails == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE])
        #expect(result?.messageText == nil)  // Not enough for message length
    }
    
    @Test("parseNAK with message length but no message (10 bytes)")
    func parseNAKMessageLengthOnly() {
        // 10 bytes: base(3) + details(5) + messageLength(2)
        // Message length says 5 bytes but no actual message
        let payload: [UInt8] = [0x10, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x05, 0x00]
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result != nil)
        #expect(result?.nakDetails == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE])
        #expect(result?.messageText == nil)  // Length says 5, but no bytes available
    }
    
    @Test("parseNAK with zero-length message")
    func parseNAKZeroLengthMessage() {
        // Message length = 0
        let payload: [UInt8] = [0x10, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x00, 0x00]
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result != nil)
        #expect(result?.messageText == "")  // Empty string, not nil
    }
    
    @Test("parseNAK with short message")
    func parseNAKWithMessage() {
        // "Error" = 5 bytes
        let message = "Error"
        let messageBytes = Array(message.utf8)
        var payload: [UInt8] = [0x10, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        payload.append(UInt8(messageBytes.count & 0x7F))  // Low 7 bits
        payload.append(UInt8((messageBytes.count >> 7) & 0x7F))  // High 7 bits
        payload.append(contentsOf: messageBytes)
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result != nil)
        #expect(result?.messageText == "Error")
    }
    
    @Test("parseNAK with long message (14-bit length)")
    func parseNAKLongMessage() {
        // 200 byte message (requires both bytes of 14-bit length)
        let message = String(repeating: "X", count: 200)
        let messageBytes = Array(message.utf8)
        var payload: [UInt8] = [0x10, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        payload.append(UInt8(messageBytes.count & 0x7F))  // Low 7 bits = 72
        payload.append(UInt8((messageBytes.count >> 7) & 0x7F))  // High 7 bits = 1
        payload.append(contentsOf: messageBytes)
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result != nil)
        #expect(result?.messageText == message)
        #expect(result?.messageText?.count == 200)
    }
    
    @Test("parseNAK with truncated message")
    func parseNAKTruncatedMessage() {
        // Says 10 bytes but only has 3
        var payload: [UInt8] = [0x10, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        payload.append(10)  // Length low = 10
        payload.append(0)   // Length high = 0
        payload.append(contentsOf: [0x41, 0x42, 0x43])  // Only "ABC" (3 bytes)
        
        let result = CIMessageParser.parseNAK(payload)
        
        #expect(result != nil)
        #expect(result?.messageText == nil)  // Not enough bytes for declared length
    }
    
    // MARK: - parseDiscoveryReply Tests
    
    @Test("parseDiscoveryReply minimum payload")
    func parseDiscoveryReplyMinimum() {
        // identity(11) + category(1) + maxSysEx(4) = 16 bytes
        var payload: [UInt8] = []
        // Manufacturer ID (3 bytes) - KORG
        payload.append(contentsOf: [0x42, 0x00, 0x00])
        // Family (2 bytes)
        payload.append(contentsOf: [0x01, 0x00])
        // Model (2 bytes)
        payload.append(contentsOf: [0x02, 0x00])
        // Version (4 bytes)
        payload.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
        // Category support
        payload.append(CategorySupport.propertyExchange.rawValue)
        // Max SysEx (4 x 7-bit) = 512
        payload.append(contentsOf: [0x00, 0x04, 0x00, 0x00])
        
        let result = CIMessageParser.parseDiscoveryReply(payload)
        
        #expect(result != nil)
        #expect(result?.identity.manufacturerID == .korg)
        #expect(result?.categorySupport == .propertyExchange)
        #expect(result?.maxSysExSize == 512)
        #expect(result?.initiatorOutputPath == 0)
        #expect(result?.functionBlock == 0)
    }
    
    @Test("parseDiscoveryReply with optional fields")
    func parseDiscoveryReplyWithOptional() {
        var payload: [UInt8] = []
        // Identity (11 bytes)
        payload.append(contentsOf: [0x42, 0x00, 0x00])  // KORG
        payload.append(contentsOf: [0x01, 0x00])        // Family
        payload.append(contentsOf: [0x02, 0x00])        // Model
        payload.append(contentsOf: [0x01, 0x00, 0x00, 0x00])  // Version
        // Category
        payload.append(CategorySupport.propertyExchange.rawValue)
        // Max SysEx
        payload.append(contentsOf: [0x00, 0x04, 0x00, 0x00])
        // Optional: initiatorOutputPath
        payload.append(0x03)
        // Optional: functionBlock
        payload.append(0x7F)
        
        let result = CIMessageParser.parseDiscoveryReply(payload)
        
        #expect(result != nil)
        #expect(result?.initiatorOutputPath == 0x03)
        #expect(result?.functionBlock == 0x7F)
    }
    
    @Test("parseDiscoveryReply too short")
    func parseDiscoveryReplyTooShort() {
        let payload: [UInt8] = [0x42, 0x00, 0x00, 0x01, 0x00]  // Only 5 bytes
        
        let result = CIMessageParser.parseDiscoveryReply(payload)
        
        #expect(result == nil)
    }
    
    // MARK: - parsePEReply Tests
    
    @Test("parsePEReply minimum valid")
    func parsePEReplyMinimum() {
        // requestID(1) + headerSize(2) + numChunks(2) + thisChunk(2) + dataSize(2) = 9
        let payload: [UInt8] = [
            0x42,        // requestID
            0x00, 0x00,  // headerSize = 0
            0x01, 0x00,  // numChunks = 1
            0x01, 0x00,  // thisChunk = 1
            0x00, 0x00   // dataSize = 0
        ]
        
        let result = CIMessageParser.parsePEReply(payload)
        
        #expect(result != nil)
        #expect(result?.requestID == 0x42)
        #expect(result?.numChunks == 1)
        #expect(result?.thisChunk == 1)
        #expect(result?.headerData.isEmpty == true)
        #expect(result?.propertyData.isEmpty == true)
    }
    
    @Test("parsePEReply with header and data")
    func parsePEReplyWithData() {
        let header = "{\"status\":200}"
        let body = "[1,2,3]"
        
        var payload: [UInt8] = [0x01]  // requestID
        // headerSize (14-bit)
        payload.append(UInt8(header.count & 0x7F))
        payload.append(UInt8((header.count >> 7) & 0x7F))
        // numChunks
        payload.append(contentsOf: [0x01, 0x00])
        // thisChunk
        payload.append(contentsOf: [0x01, 0x00])
        // dataSize
        payload.append(UInt8(body.count & 0x7F))
        payload.append(UInt8((body.count >> 7) & 0x7F))
        // header
        payload.append(contentsOf: Array(header.utf8))
        // body
        payload.append(contentsOf: Array(body.utf8))
        
        let result = CIMessageParser.parsePEReply(payload)
        
        #expect(result != nil)
        #expect(String(data: result!.headerData, encoding: .utf8) == header)
        #expect(String(data: result!.propertyData, encoding: .utf8) == body)
    }
    
    @Test("parsePEReply too short")
    func parsePEReplyTooShort() {
        let payload: [UInt8] = [0x01, 0x00, 0x00, 0x01]  // Only 4 bytes
        
        let result = CIMessageParser.parsePEReply(payload)
        
        #expect(result == nil)
    }
    
    @Test("parsePEReply with truncated header")
    func parsePEReplyTruncatedHeader() {
        // Says header is 10 bytes but only provides 3
        let payload: [UInt8] = [
            0x01,        // requestID
            0x0A, 0x00,  // headerSize = 10
            0x01, 0x00,  // numChunks
            0x01, 0x00,  // thisChunk
            0x00, 0x00,  // dataSize = 0
            0x41, 0x42, 0x43  // Only 3 bytes of header
        ]
        
        let result = CIMessageParser.parsePEReply(payload)
        
        #expect(result == nil)
    }
    
    // MARK: - parseInvalidateMUID Tests
    
    @Test("parseInvalidateMUID valid")
    func parseInvalidateMUIDValid() {
        // MUID = 0x01234567 (little-endian, 7-bit per byte)
        let payload: [UInt8] = [0x67, 0x0A, 0x11, 0x00]
        
        let result = CIMessageParser.parseInvalidateMUID(payload)
        
        #expect(result != nil)
    }
    
    @Test("parseInvalidateMUID too short")
    func parseInvalidateMUIDTooShort() {
        let payload: [UInt8] = [0x67, 0x0A, 0x11]  // Only 3 bytes
        
        let result = CIMessageParser.parseInvalidateMUID(payload)
        
        #expect(result == nil)
    }
    
    @Test("parseInvalidateMUID broadcast")
    func parseInvalidateMUIDBroadcast() {
        // Broadcast MUID = 0x0FFFFFFF
        let payload: [UInt8] = [0x7F, 0x7F, 0x7F, 0x7F]
        
        let result = CIMessageParser.parseInvalidateMUID(payload)
        
        #expect(result != nil)
        #expect(result?.targetMUID.isBroadcast == true)
    }
    
    // MARK: - parsePECapabilityReply Tests
    
    @Test("parsePECapabilityReply valid")
    func parsePECapabilityReplyValid() {
        let payload: [UInt8] = [0x04, 0x01, 0x02]  // 4 simultaneous, version 1.2
        
        let result = CIMessageParser.parsePECapabilityReply(payload)
        
        #expect(result != nil)
        #expect(result?.numSimultaneousRequests == 4)
        #expect(result?.majorVersion == 1)
        #expect(result?.minorVersion == 2)
    }
    
    @Test("parsePECapabilityReply too short")
    func parsePECapabilityReplyTooShort() {
        let payload: [UInt8] = [0x04, 0x01]  // Only 2 bytes
        
        let result = CIMessageParser.parsePECapabilityReply(payload)
        
        #expect(result == nil)
    }
    
    // MARK: - parseSubscribeReply Tests
    
    @Test("parseSubscribeReply with subscribeId")
    func parseSubscribeReplyWithSubscribeId() {
        // Build payload manually
        // Header: {"status":200,"subscribeId":"abc123"}
        let headerData = Data("{\"status\":200,\"subscribeId\":\"abc123\"}".utf8)
        let headerSize = headerData.count
        
        var payload: [UInt8] = [
            0x05,  // Request ID
        ]
        // Header size (14-bit)
        payload.append(UInt8(headerSize & 0x7F))
        payload.append(UInt8((headerSize >> 7) & 0x7F))
        // Num chunks
        payload.append(0x01)
        payload.append(0x00)
        // This chunk
        payload.append(0x01)
        payload.append(0x00)
        // Property data size (0)
        payload.append(0x00)
        payload.append(0x00)
        // Header data
        payload.append(contentsOf: headerData)
        
        let result = CIMessageParser.parseSubscribeReply(payload)
        
        #expect(result != nil)
        #expect(result?.requestID == 0x05)
        #expect(result?.status == 200)
        #expect(result?.subscribeId == "abc123")
    }
    
    @Test("parseSubscribeReply without subscribeId")
    func parseSubscribeReplyWithoutSubscribeId() {
        // Header: {"status":400}
        let headerData = Data("{\"status\":400}".utf8)
        let headerSize = headerData.count
        
        var payload: [UInt8] = [0x03]  // Request ID
        payload.append(UInt8(headerSize & 0x7F))
        payload.append(UInt8((headerSize >> 7) & 0x7F))
        payload.append(0x01)
        payload.append(0x00)
        payload.append(0x01)
        payload.append(0x00)
        payload.append(0x00)
        payload.append(0x00)
        payload.append(contentsOf: headerData)
        
        let result = CIMessageParser.parseSubscribeReply(payload)
        
        #expect(result != nil)
        #expect(result?.requestID == 0x03)
        #expect(result?.status == 400)
        #expect(result?.subscribeId == nil)
    }
    
    // MARK: - parseNotify Tests
    
    @Test("parseNotify with subscribeId and resource")
    func parseNotifyWithSubscribeIdAndResource() {
        // Header: {"subscribeId":"sub-xyz","resource":"ProgramList"}
        let headerData = Data("{\"subscribeId\":\"sub-xyz\",\"resource\":\"ProgramList\"}".utf8)
        let headerSize = headerData.count
        
        let propertyData = Data("{\"changed\":true}".utf8)
        let dataSize = propertyData.count
        
        var payload: [UInt8] = [0x00]  // Request ID (typically 0 for notify)
        // Header size
        payload.append(UInt8(headerSize & 0x7F))
        payload.append(UInt8((headerSize >> 7) & 0x7F))
        // Num chunks
        payload.append(0x01)
        payload.append(0x00)
        // This chunk
        payload.append(0x01)
        payload.append(0x00)
        // Property data size
        payload.append(UInt8(dataSize & 0x7F))
        payload.append(UInt8((dataSize >> 7) & 0x7F))
        // Header data
        payload.append(contentsOf: headerData)
        // Property data
        payload.append(contentsOf: propertyData)
        
        let result = CIMessageParser.parseNotify(payload)
        
        #expect(result != nil)
        #expect(result?.requestID == 0x00)
        #expect(result?.subscribeId == "sub-xyz")
        #expect(result?.resource == "ProgramList")
        #expect(result?.numChunks == 1)
        #expect(result?.thisChunk == 1)
        #expect(result?.propertyData == propertyData)
    }
    
    // MARK: - parseFullSubscribeReply Tests
    
    @Test("parseFullSubscribeReply complete message")
    func parseFullSubscribeReplyCompleteMessage() {
        // Build complete SysEx message
        let sourceMUID = MUID(rawValue: 0x05060708)!
        let destMUID = MUID(rawValue: 0x01020304)!
        let headerData = Data("{\"status\":200,\"subscribeId\":\"full-test\"}".utf8)
        let headerSize = headerData.count
        
        var message: [UInt8] = [
            0xF0,  // SysEx Start
            0x7E,  // Non-Realtime
            0x7F,  // Device ID
            0x0D,  // CI Sub-ID
            0x39,  // PE Subscribe Reply
            0x02   // CI Version 1.2
        ]
        
        // Source MUID
        message.append(contentsOf: sourceMUID.bytes)
        // Destination MUID
        message.append(contentsOf: destMUID.bytes)
        // Request ID
        message.append(0x07)
        // Header size
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))
        // Num chunks
        message.append(0x01)
        message.append(0x00)
        // This chunk
        message.append(0x01)
        message.append(0x00)
        // Property data size
        message.append(0x00)
        message.append(0x00)
        // Header data
        message.append(contentsOf: headerData)
        // SysEx End
        message.append(0xF7)
        
        let result = CIMessageParser.parseFullSubscribeReply(message)
        
        #expect(result != nil)
        #expect(result?.sourceMUID == sourceMUID)
        #expect(result?.destinationMUID == destMUID)
        #expect(result?.requestID == 0x07)
        #expect(result?.status == 200)
        #expect(result?.subscribeId == "full-test")
    }
    
    @Test("parseFullSubscribeReply wrong message type returns nil")
    func parseFullSubscribeReplyWrongMessageType() {
        // Build message with wrong type (PE Get Reply instead of Subscribe Reply)
        let sourceMUID = MUID(rawValue: 0x05060708)!
        let destMUID = MUID(rawValue: 0x01020304)!
        let headerData = Data("{\"status\":200}".utf8)
        let headerSize = headerData.count
        
        var message: [UInt8] = [
            0xF0, 0x7E, 0x7F, 0x0D,
            0x35,  // PE Get Reply (wrong type)
            0x02
        ]
        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destMUID.bytes)
        message.append(0x01)  // Request ID
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))
        message.append(0x01)
        message.append(0x00)
        message.append(0x01)
        message.append(0x00)
        message.append(0x00)
        message.append(0x00)
        message.append(contentsOf: headerData)
        message.append(0xF7)
        
        let result = CIMessageParser.parseFullSubscribeReply(message)
        
        #expect(result == nil)
    }
    
    // MARK: - parseFullNotify Tests
    
    @Test("parseFullNotify complete message")
    func parseFullNotifyCompleteMessage() {
        let sourceMUID = MUID(rawValue: 0x05060708)!
        let destMUID = MUID(rawValue: 0x01020304)!
        let headerData = Data("{\"subscribeId\":\"notify-123\",\"resource\":\"SomeResource\"}".utf8)
        let headerSize = headerData.count
        let propertyData = Data("{\"data\":42}".utf8)
        let dataSize = propertyData.count
        
        var message: [UInt8] = [
            0xF0, 0x7E, 0x7F, 0x0D,
            0x3F,  // PE Notify
            0x02
        ]
        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destMUID.bytes)
        message.append(0x00)  // Request ID
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))
        message.append(0x01)
        message.append(0x00)
        message.append(0x01)
        message.append(0x00)
        message.append(UInt8(dataSize & 0x7F))
        message.append(UInt8((dataSize >> 7) & 0x7F))
        message.append(contentsOf: headerData)
        message.append(contentsOf: propertyData)
        message.append(0xF7)
        
        let result = CIMessageParser.parseFullNotify(message)
        
        #expect(result != nil)
        #expect(result?.sourceMUID == sourceMUID)
        #expect(result?.destinationMUID == destMUID)
        #expect(result?.subscribeId == "notify-123")
        #expect(result?.resource == "SomeResource")
        #expect(result?.propertyData == propertyData)
    }

    // MARK: - PE Format Tests (Phase 1-3)

    @Test("PE Get Inquiry does not contain chunk fields")
    func testPEGetInquiryDoesNotContainChunkFields() {
        // PE Get Inquiry format:
        // F0 7E 7F 0D 34 [ciVer] [srcMUID:4] [dstMUID:4]
        // [requestID] [headerSize:2] [headerData...] F7
        //
        // Important: NO numChunks/thisChunk/dataSize fields

        let sourceMUID = MUID(rawValue: 0x01020304)!
        let destMUID = MUID(rawValue: 0x05060708)!
        let headerData = Data("{\"resource\":\"DeviceInfo\"}".utf8)
        let requestID: UInt8 = 0x42

        let message = CIMessageBuilder.peGetInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            requestID: requestID,
            headerData: headerData
        )

        // Expected structure:
        // 0: F0 (SysEx start)
        // 1: 7E (Non-realtime)
        // 2: 7F (Device ID)
        // 3: 0D (CI Sub-ID)
        // 4: 34 (PE Get Inquiry)
        // 5: 01 (CI Version)
        // 6-9: sourceMUID (4 bytes)
        // 10-13: destMUID (4 bytes)
        // 14: requestID
        // 15-16: headerSize (2 bytes, 14-bit)
        // 17+: headerData
        // last: F7 (SysEx end)

        #expect(message[4] == 0x34)  // PE Get Inquiry
        #expect(message[14] == requestID)

        // Header size (14-bit encoding)
        let headerSize = Int(message[15]) | (Int(message[16]) << 7)
        #expect(headerSize == headerData.count)

        // Header data starts immediately after headerSize (no chunk fields)
        let headerStart = 17
        let extractedHeaderData = Data(message[headerStart..<headerStart + headerSize])
        #expect(extractedHeaderData == headerData)

        // Verify message ends correctly
        #expect(message.last == 0xF7)

        // Total length should be: 6 (header) + 4 (srcMUID) + 4 (dstMUID) + 1 (requestID) + 2 (headerSize) + headerData.count + 1 (F7)
        let expectedLength = 6 + 4 + 4 + 1 + 2 + headerData.count + 1
        #expect(message.count == expectedLength)
    }

    @Test("PE Get Reply contains chunk fields")
    func testPEGetReplyContainsChunkFields() {
        // PE Get Reply format:
        // F0 7E 7F 0D 35 [ciVer] [srcMUID:4] [dstMUID:4]
        // [requestID] [headerSize:2] [numChunks:2] [thisChunk:2] [dataSize:2]
        // [headerData...] [propertyData...] F7

        let sourceMUID = MUID(rawValue: 0x01020304)!
        let destMUID = MUID(rawValue: 0x05060708)!
        let headerData = Data("{\"status\":200}".utf8)
        let propertyData = Data("{\"manufacturerId\":66}".utf8)
        let requestID: UInt8 = 0x42

        // Build message manually to ensure correct format
        var message: [UInt8] = [
            0xF0, 0x7E, 0x7F, 0x0D,
            0x35,  // PE Get Reply
            0x01   // CI Version
        ]
        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destMUID.bytes)
        message.append(requestID)

        // Header size (14-bit)
        message.append(UInt8(headerData.count & 0x7F))
        message.append(UInt8((headerData.count >> 7) & 0x7F))

        // Chunk fields (these MUST be present in Reply)
        message.append(0x01)  // numChunks low
        message.append(0x00)  // numChunks high
        message.append(0x01)  // thisChunk low
        message.append(0x00)  // thisChunk high

        // Data size (14-bit)
        message.append(UInt8(propertyData.count & 0x7F))
        message.append(UInt8((propertyData.count >> 7) & 0x7F))

        // Header data
        message.append(contentsOf: headerData)

        // Property data
        message.append(contentsOf: propertyData)

        message.append(0xF7)

        // Parse the message
        let result = CIMessageParser.parsePEReply(Array(message[14..<message.count-1]))

        #expect(result != nil)
        #expect(result?.requestID == requestID)
        #expect(result?.numChunks == 1)
        #expect(result?.thisChunk == 1)
        #expect(result?.headerData == headerData)
        #expect(result?.propertyData == propertyData)
    }

    @Test("PE Inquiry vs Reply: headerData start position differs")
    func testHeaderDataStartPositionDiffers() {
        let headerData = Data("TEST".utf8)
        let sourceMUID = MUID(rawValue: 0x01234567)!  // Valid MUID (28-bit max: 0x0FFFFFFF)
        let destMUID = MUID.broadcast
        let requestID: UInt8 = 0x10

        // Inquiry: headerData starts at position 17 (after requestID + headerSize)
        let inquiryMessage = CIMessageBuilder.peGetInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            requestID: requestID,
            headerData: headerData
        )

        // Position breakdown for Inquiry:
        // 0-5: SysEx header (F0 7E 7F 0D 34 01)
        // 6-9: sourceMUID
        // 10-13: destMUID
        // 14: requestID
        // 15-16: headerSize
        // 17+: headerData <-- Immediately after headerSize

        let inquiryHeaderStart = 17
        let extractedInquiryHeader = Data(inquiryMessage[inquiryHeaderStart..<inquiryHeaderStart + headerData.count])
        #expect(extractedInquiryHeader == headerData)

        // Reply: headerData starts at position 23 (after chunk fields)
        var replyPayload: [UInt8] = [requestID]
        replyPayload.append(UInt8(headerData.count & 0x7F))
        replyPayload.append(UInt8((headerData.count >> 7) & 0x7F))
        replyPayload.append(contentsOf: [0x01, 0x00, 0x01, 0x00])  // numChunks, thisChunk
        replyPayload.append(contentsOf: [0x00, 0x00])  // dataSize = 0
        replyPayload.append(contentsOf: headerData)

        // Parse Reply
        let replyResult = CIMessageParser.parsePEReply(replyPayload)
        #expect(replyResult != nil)
        #expect(replyResult?.headerData == headerData)

        // Verify: Inquiry has headerData 6 bytes earlier than Reply
        // (due to missing numChunks, thisChunk, dataSize fields)
    }

    @Test("14-bit encoding for large header and data sizes")
    func test14BitEncodingLargeSizes() {
        // Test values that require both bytes of 14-bit encoding
        // 128 = 0x80 = 0b10000000 = 0x00 (low 7 bits) + 0x01 (high 7 bits)
        // 200 = 0xC8 = 0b11001000 = 0x48 (low 7 bits) + 0x01 (high 7 bits)
        // 16383 = 0x3FFF = max 14-bit = 0x7F (low) + 0x7F (high)

        let testCases: [(size: Int, expectedLow: UInt8, expectedHigh: UInt8)] = [
            (128, 0x00, 0x01),     // 0x00 | (0x01 << 7) = 128
            (200, 0x48, 0x01),     // 0x48 | (0x01 << 7) = 72 + 128 = 200
            (1000, 0x68, 0x07),    // 0x68 | (0x07 << 7) = 104 + 896 = 1000
            (16383, 0x7F, 0x7F)    // Max 14-bit
        ]

        for (size, expectedLow, expectedHigh) in testCases {
            // Create headerData of specified size
            let headerData = Data(repeating: 0x41, count: size)
            let propertyData = Data(repeating: 0x42, count: size)

            // Build PE Reply with large header and data
            var payload: [UInt8] = [0x01]  // requestID

            // Header size (14-bit)
            payload.append(UInt8(size & 0x7F))
            payload.append(UInt8((size >> 7) & 0x7F))

            #expect(payload[1] == expectedLow, "HeaderSize low byte mismatch for size \(size)")
            #expect(payload[2] == expectedHigh, "HeaderSize high byte mismatch for size \(size)")

            // Chunk fields
            payload.append(contentsOf: [0x01, 0x00, 0x01, 0x00])

            // Data size (14-bit)
            payload.append(UInt8(size & 0x7F))
            payload.append(UInt8((size >> 7) & 0x7F))

            #expect(payload[7] == expectedLow, "DataSize low byte mismatch for size \(size)")
            #expect(payload[8] == expectedHigh, "DataSize high byte mismatch for size \(size)")

            // Append header and property data
            payload.append(contentsOf: headerData)
            payload.append(contentsOf: propertyData)

            // Parse and verify
            let result = CIMessageParser.parsePEReply(payload)
            #expect(result != nil, "Parse failed for size \(size)")
            #expect(result?.headerData.count == size, "HeaderData size mismatch for \(size)")
            #expect(result?.propertyData.count == size, "PropertyData size mismatch for \(size)")
        }
    }
}
