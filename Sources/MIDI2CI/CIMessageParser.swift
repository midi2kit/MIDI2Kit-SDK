//
//  CIMessageParser.swift
//  MIDI2Kit
//
//  Parses MIDI-CI SysEx messages
//

import Foundation
import MIDI2Core

/// Parses MIDI-CI SysEx messages
public enum CIMessageParser {
    
    /// Parsed MIDI-CI message
    public struct ParsedMessage: Sendable {
        public let messageType: CIMessageType
        public let ciVersion: UInt8
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let payload: [UInt8]
    }
    
    // MARK: - Main Parser
    
    /// Parse a complete MIDI-CI SysEx message
    /// - Parameter data: Complete SysEx bytes including F0 and F7
    /// - Returns: Parsed message, or nil if invalid
    public static func parse(_ data: [UInt8]) -> ParsedMessage? {
        // Minimum CI message: F0 7E xx 0D type ver srcMUID(4) dstMUID(4) F7 = 17 bytes
        guard data.count >= 17 else { return nil }
        
        // Validate SysEx framing
        guard data.first == MIDICIConstants.sysExStart,
              data.last == MIDICIConstants.sysExEnd else { return nil }
        
        // Validate Universal SysEx Non-Realtime
        guard data[1] == MIDICIConstants.sysExNonRealtime else { return nil }
        
        // Validate MIDI-CI Sub-ID
        guard data[3] == MIDICIConstants.ciSubID1 else { return nil }
        
        // Parse message type
        guard let messageType = CIMessageType(rawValue: data[4]) else { return nil }
        
        let ciVersion = data[5]
        
        // Parse MUIDs
        guard let sourceMUID = MUID(from: data, offset: 6),
              let destinationMUID = MUID(from: data, offset: 10) else { return nil }
        
        // Payload starts after destination MUID, ends before F7
        let payloadStart = 14
        let payloadEnd = data.count - 1
        let payload = payloadStart < payloadEnd ? Array(data[payloadStart..<payloadEnd]) : []
        
        return ParsedMessage(
            messageType: messageType,
            ciVersion: ciVersion,
            sourceMUID: sourceMUID,
            destinationMUID: destinationMUID,
            payload: payload
        )
    }
    
    // MARK: - Discovery Reply Parser
    
    /// Discovery Reply payload structure
    public struct DiscoveryReplyPayload: Sendable {
        public let identity: DeviceIdentity
        public let categorySupport: CategorySupport
        public let maxSysExSize: UInt32
        public let initiatorOutputPath: UInt8
        public let functionBlock: UInt8
    }
    
    /// Parse Discovery Reply payload
    /// - Parameter payload: Payload bytes (after destination MUID)
    /// - Returns: Parsed discovery reply, or nil if invalid
    public static func parseDiscoveryReply(_ payload: [UInt8]) -> DiscoveryReplyPayload? {
        // Minimum: identity(11) + category(1) + maxSysEx(4) = 16 bytes
        guard payload.count >= 16 else { return nil }
        
        guard let identity = DeviceIdentity(from: payload, offset: 0) else { return nil }
        
        let categorySupport = CategorySupport(rawValue: payload[11])
        
        // Max SysEx size (4 x 7-bit bytes)
        let maxSysExSize = UInt32(payload[12])
            | (UInt32(payload[13]) << 7)
            | (UInt32(payload[14]) << 14)
            | (UInt32(payload[15]) << 21)
        
        // Optional fields (CI 1.2+)
        let initiatorOutputPath = payload.count > 16 ? payload[16] : 0
        let functionBlock = payload.count > 17 ? payload[17] : 0
        
        return DiscoveryReplyPayload(
            identity: identity,
            categorySupport: categorySupport,
            maxSysExSize: maxSysExSize,
            initiatorOutputPath: initiatorOutputPath,
            functionBlock: functionBlock
        )
    }
    
    // MARK: - PE Capability Reply Parser
    
    /// PE Capability Reply payload structure
    public struct PECapabilityReplyPayload: Sendable {
        public let numSimultaneousRequests: UInt8
        public let majorVersion: UInt8
        public let minorVersion: UInt8
    }
    
    /// Parse PE Capability Reply payload
    public static func parsePECapabilityReply(_ payload: [UInt8]) -> PECapabilityReplyPayload? {
        guard payload.count >= 3 else { return nil }
        
        return PECapabilityReplyPayload(
            numSimultaneousRequests: payload[0],
            majorVersion: payload[1],
            minorVersion: payload[2]
        )
    }
    
    // MARK: - PE Get/Set Reply Parser
    
    /// PE Reply payload structure
    public struct PEReplyPayload: Sendable {
        public let requestID: UInt8
        public let headerData: Data
        public let propertyData: Data
        public let numChunks: Int
        public let thisChunk: Int
    }
    
    /// Parse PE Get Reply or Set Reply payload
    /// - Parameter payload: Payload bytes
    /// - Parameter ciVersion: CI version (1 for 1.1, 2 for 1.2+)
    /// - Returns: Parsed PE reply, or nil if invalid
    /// 
    /// MIDI-CI 1.2 PE Reply format (M2-105-UM Section 6.4.2):
    /// - requestID (1 byte)
    /// - headerLength (2 bytes, 14-bit encoded)
    /// - numChunks (2 bytes, 14-bit encoded)
    /// - thisChunk (2 bytes, 14-bit encoded)
    /// - dataLength (2 bytes, 14-bit encoded)
    /// - headerData (headerLength bytes)
    /// - propertyData (dataLength bytes)
    ///
    /// MIDI-CI 1.1 PE Reply format:
    /// - requestID (1 byte)
    /// - headerLength (2 bytes, 14-bit encoded)
    /// - dataLength (2 bytes, 14-bit encoded)
    /// - headerData (headerLength bytes)
    /// - propertyData (dataLength bytes)
    /// Note: No numChunks/thisChunk fields in CI 1.1
    ///
    /// Note: Some devices (e.g., KORG) report ciVersion=0x01 but use a simplified format
    /// without numChunks/thisChunk/dataLength fields. We detect this by checking if the
    /// byte after headerSize looks like JSON (starts with '{').
    public static func parsePEReply(_ payload: [UInt8], ciVersion: UInt8 = 2) -> PEReplyPayload? {
        // Try CI 1.2 format first (most devices use this)
        if let result = parsePEReplyCI12(payload) {
            return result
        }
        
        // Try CI 1.1 format (with dataLength field)
        if let result = parsePEReplyCI11(payload) {
            return result
        }
        
        // Fallback: KORG-style format (no numChunks/thisChunk/dataLength fields)
        // Format: requestID(1) + headerSize(2) + headerData(headerSize) + propertyData(rest)
        return parsePEReplyKORG(payload)
    }
    
    /// Parse PE Reply in CI 1.2 format (with numChunks/thisChunk fields)
    private static func parsePEReplyCI12(_ payload: [UInt8]) -> PEReplyPayload? {
        // Minimum: requestID(1) + headerSize(2) + numChunks(2) + thisChunk(2) + dataSize(2) = 9 bytes
        guard payload.count >= 9 else { return nil }
        
        let requestID = payload[0] & 0x7F
        
        // Header size (14-bit)
        let headerSize = Int(payload[1]) | (Int(payload[2]) << 7)
        
        // Number of chunks (14-bit)
        let numChunks = Int(payload[3]) | (Int(payload[4]) << 7)
        
        // This chunk (14-bit)
        let thisChunk = Int(payload[5]) | (Int(payload[6]) << 7)
        
        // Property data size (14-bit)
        let dataSize = Int(payload[7]) | (Int(payload[8]) << 7)
        
        // Sanity check: numChunks and thisChunk should be reasonable
        guard numChunks >= 1 && numChunks <= 0x3FFF else { return nil }
        guard thisChunk >= 1 && thisChunk <= numChunks else { return nil }
        
        // Extract header data (comes after the size fields)
        let headerStart = 9
        let headerEnd = headerStart + headerSize
        let dataStart = headerEnd
        let dataEnd = dataStart + dataSize
        guard payload.count >= dataEnd else { return nil }
        let headerData = Data(payload[headerStart..<headerEnd])
        let propertyData = Data(payload[dataStart..<dataEnd])
        
        return PEReplyPayload(
            requestID: requestID,
            headerData: headerData,
            propertyData: propertyData,
            numChunks: numChunks,
            thisChunk: thisChunk
        )
    }
    
    /// Parse PE Reply in CI 1.1 format (no numChunks/thisChunk fields, but has dataLength)
    private static func parsePEReplyCI11(_ payload: [UInt8]) -> PEReplyPayload? {
        // Minimum: requestID(1) + headerSize(2) + dataSize(2) = 5 bytes
        guard payload.count >= 5 else { return nil }
        
        let requestID = payload[0] & 0x7F
        let headerSize = Int(payload[1]) | (Int(payload[2]) << 7)
        let dataSize = Int(payload[3]) | (Int(payload[4]) << 7)
        
        // Sanity check: sizes should be reasonable
        guard headerSize >= 0 && headerSize <= 0x3FFF else { return nil }
        guard dataSize >= 0 && dataSize <= 0x3FFF else { return nil }
        
        let headerStart = 5
        let headerEnd = headerStart + headerSize
        let dataStart = headerEnd
        let dataEnd = dataStart + dataSize
        guard payload.count >= dataEnd else { return nil }
        let headerData = Data(payload[headerStart..<headerEnd])
        let propertyData = Data(payload[dataStart..<dataEnd])
        
        return PEReplyPayload(
            requestID: requestID,
            headerData: headerData,
            propertyData: propertyData,
            numChunks: 1,
            thisChunk: 1
        )
    }
    
    /// Parse PE Reply in KORG-style format
    /// KORG format: requestID(1) + headerSize(2) + headerData(headerSize) + numChunks(2) + thisChunk(2) + dataSize(2) + propertyData(dataSize)
    /// Note: chunk fields come AFTER headerData, unlike standard CI 1.2 format
    private static func parsePEReplyKORG(_ payload: [UInt8]) -> PEReplyPayload? {
        // Minimum: requestID(1) + headerSize(2) + at least 1 byte header = 4 bytes
        guard payload.count >= 4 else { return nil }
        
        let requestID = payload[0] & 0x7F
        let headerSize = Int(payload[1]) | (Int(payload[2]) << 7)
        
        // Sanity check: headerSize should be reasonable
        guard headerSize >= 0 && headerSize <= 0x3FFF else { return nil }
        
        let headerStart = 3
        let headerEnd = headerStart + headerSize
        
        // Validate: headerData should fit and look like JSON (starts with '{')
        guard headerEnd <= payload.count else { return nil }
        guard payload.count > 3 && payload[3] == 0x7B else { return nil } // 0x7B = '{'
        
        let headerData = Data(payload[headerStart..<headerEnd])
        
        // Check if there's chunk fields after header
        // Chunk fields: numChunks(2) + thisChunk(2) + dataSize(2) = 6 bytes
        let chunkFieldsStart = headerEnd
        if chunkFieldsStart + 6 <= payload.count {
            // Read chunk fields
            let numChunks = Int(payload[chunkFieldsStart]) | (Int(payload[chunkFieldsStart + 1]) << 7)
            let thisChunk = Int(payload[chunkFieldsStart + 2]) | (Int(payload[chunkFieldsStart + 3]) << 7)
            let dataSize = Int(payload[chunkFieldsStart + 4]) | (Int(payload[chunkFieldsStart + 5]) << 7)
            
            // Validate chunk fields
            if numChunks >= 1 && numChunks <= 0x3FFF &&
               thisChunk >= 1 && thisChunk <= numChunks &&
               dataSize >= 0 && dataSize <= 0x3FFF {
                
                let dataStart = chunkFieldsStart + 6
                let dataEnd = dataStart + dataSize
                
                if dataEnd <= payload.count {
                    let propertyData = Data(payload[dataStart..<dataEnd])
                    return PEReplyPayload(
                        requestID: requestID,
                        headerData: headerData,
                        propertyData: propertyData,
                        numChunks: numChunks,
                        thisChunk: thisChunk
                    )
                }
            }
        }
        
        // Fallback: no chunk fields, property data is everything after header
        let propertyData: Data
        if headerEnd < payload.count {
            propertyData = Data(payload[headerEnd...])
        } else {
            propertyData = Data()
        }
        
        return PEReplyPayload(
            requestID: requestID,
            headerData: headerData,
            propertyData: propertyData,
            numChunks: 1,
            thisChunk: 1
        )
    }
    
    // MARK: - Invalidate MUID Parser
    
    /// Invalidate MUID payload structure
    public struct InvalidateMUIDPayload: Sendable {
        public let targetMUID: MUID
    }
    
    /// Parse Invalidate MUID payload
    public static func parseInvalidateMUID(_ payload: [UInt8]) -> InvalidateMUIDPayload? {
        guard payload.count >= 4 else { return nil }
        guard let targetMUID = MUID(from: payload, offset: 0) else { return nil }
        return InvalidateMUIDPayload(targetMUID: targetMUID)
    }
    
    // MARK: - NAK Parser
    
    /// NAK payload structure
    public struct NAKPayload: Sendable {
        public let originalTransaction: UInt8
        public let statusCode: UInt8
        public let statusData: UInt8
        public let nakDetails: [UInt8]
        public let messageText: String?
    }
    
    /// Parse NAK payload
    public static func parseNAK(_ payload: [UInt8]) -> NAKPayload? {
        guard payload.count >= 3 else { return nil }
        
        let originalTransaction = payload[0]
        let statusCode = payload[1]
        let statusData = payload[2]
        
        var nakDetails: [UInt8] = []
        var messageText: String? = nil
        
        // NAK details require at least 8 bytes (3 base + 5 details)
        if payload.count >= 8 {
            nakDetails = Array(payload[3..<8])
        }
        
        // Message length field requires at least 10 bytes
        if payload.count >= 10 {
            let messageLength = Int(payload[8]) | (Int(payload[9]) << 7)
            if payload.count >= 10 + messageLength {
                let messageBytes = payload[10..<(10 + messageLength)]
                messageText = String(bytes: messageBytes, encoding: .utf8)
            }
        }
        
        return NAKPayload(
            originalTransaction: originalTransaction,
            statusCode: statusCode,
            statusData: statusData,
            nakDetails: nakDetails,
            messageText: messageText
        )
    }
    
    // MARK: - Full PE Reply Parser
    
    /// Full PE Reply structure (including MUIDs)
    public struct FullPEReply: Sendable {
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let requestID: UInt8
        public let headerData: Data
        public let propertyData: Data
        public let numChunks: Int
        public let thisChunk: Int
    }
    
    /// Parse complete PE Reply SysEx message
    /// - Parameter data: Complete SysEx bytes including F0 and F7
    /// - Returns: Full PE reply, or nil if invalid or not a PE reply
    public static func parseFullPEReply(_ data: [UInt8]) -> FullPEReply? {
        guard let parsed = parse(data) else { return nil }
        
        // Check message type (Get Reply or Set Reply)
        guard parsed.messageType == .peGetReply || parsed.messageType == .peSetReply else {
            return nil
        }
        
        // Parse payload with CI version
        guard let payload = parsePEReply(parsed.payload, ciVersion: parsed.ciVersion) else { return nil }
        
        return FullPEReply(
            sourceMUID: parsed.sourceMUID,
            destinationMUID: parsed.destinationMUID,
            requestID: payload.requestID,
            headerData: payload.headerData,
            propertyData: payload.propertyData,
            numChunks: payload.numChunks,
            thisChunk: payload.thisChunk
        )
    }
    
    // MARK: - PE Subscribe Reply Parser
    
    /// Subscribe Reply payload structure
    public struct SubscribeReplyPayload: Sendable {
        public let requestID: UInt8
        public let headerData: Data
        public let status: Int?
        public let subscribeId: String?
    }
    
    /// Parse PE Subscribe Reply payload
    public static func parseSubscribeReply(_ payload: [UInt8]) -> SubscribeReplyPayload? {
        // Same format as PE Reply
        guard let peReply = parsePEReply(payload) else { return nil }
        
        // Parse header JSON for status and subscribeId
        var status: Int? = nil
        var subscribeId: String? = nil
        
        if !peReply.headerData.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: peReply.headerData) as? [String: Any] {
            status = json["status"] as? Int
            subscribeId = json["subscribeId"] as? String
        }
        
        return SubscribeReplyPayload(
            requestID: peReply.requestID,
            headerData: peReply.headerData,
            status: status,
            subscribeId: subscribeId
        )
    }
    
    // MARK: - PE Notify Parser
    
    /// Notify payload structure
    public struct NotifyPayload: Sendable {
        public let requestID: UInt8
        public let headerData: Data
        public let propertyData: Data
        public let numChunks: Int
        public let thisChunk: Int
        public let subscribeId: String?
        public let resource: String?
    }
    
    /// Parse PE Notify payload
    public static func parseNotify(_ payload: [UInt8]) -> NotifyPayload? {
        // Same format as PE Reply
        guard let peReply = parsePEReply(payload) else { return nil }
        
        // Parse header JSON for subscribeId and resource
        var subscribeId: String? = nil
        var resource: String? = nil
        
        if !peReply.headerData.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: peReply.headerData) as? [String: Any] {
            subscribeId = json["subscribeId"] as? String
            resource = json["resource"] as? String
        }
        
        return NotifyPayload(
            requestID: peReply.requestID,
            headerData: peReply.headerData,
            propertyData: peReply.propertyData,
            numChunks: peReply.numChunks,
            thisChunk: peReply.thisChunk,
            subscribeId: subscribeId,
            resource: resource
        )
    }
    
    /// Full Notify structure (including MUIDs)
    public struct FullNotify: Sendable {
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let requestID: UInt8
        public let headerData: Data
        public let propertyData: Data
        public let numChunks: Int
        public let thisChunk: Int
        public let subscribeId: String?
        public let resource: String?
    }
    
    /// Parse complete PE Notify SysEx message
    public static func parseFullNotify(_ data: [UInt8]) -> FullNotify? {
        guard let parsed = parse(data) else { return nil }
        guard parsed.messageType == .peNotify else { return nil }
        guard let payload = parseNotify(parsed.payload) else { return nil }
        
        return FullNotify(
            sourceMUID: parsed.sourceMUID,
            destinationMUID: parsed.destinationMUID,
            requestID: payload.requestID,
            headerData: payload.headerData,
            propertyData: payload.propertyData,
            numChunks: payload.numChunks,
            thisChunk: payload.thisChunk,
            subscribeId: payload.subscribeId,
            resource: payload.resource
        )
    }
    
    /// Full Subscribe Reply structure
    public struct FullSubscribeReply: Sendable {
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let requestID: UInt8
        public let headerData: Data
        public let status: Int?
        public let subscribeId: String?
    }
    
    /// Parse complete PE Subscribe Reply SysEx message
    public static func parseFullSubscribeReply(_ data: [UInt8]) -> FullSubscribeReply? {
        guard let parsed = parse(data) else { return nil }
        guard parsed.messageType == .peSubscribeReply else { return nil }
        guard let payload = parseSubscribeReply(parsed.payload) else { return nil }
        
        return FullSubscribeReply(
            sourceMUID: parsed.sourceMUID,
            destinationMUID: parsed.destinationMUID,
            requestID: payload.requestID,
            headerData: payload.headerData,
            status: payload.status,
            subscribeId: payload.subscribeId
        )
    }
}

// MARK: - Full NAK Parser

extension CIMessageParser {
    
    /// Full NAK structure (including MUIDs)
    public struct FullNAK: Sendable {
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let originalTransaction: UInt8
        public let statusCode: UInt8
        public let statusData: UInt8
        public let nakDetails: [UInt8]
        public let messageText: String?
    }
    
    /// Parse complete NAK SysEx message
    /// - Parameter data: Complete SysEx bytes including F0 and F7
    /// - Returns: Full NAK, or nil if invalid or not a NAK
    public static func parseFullNAK(_ data: [UInt8]) -> FullNAK? {
        guard let parsed = parse(data) else { return nil }
        guard parsed.messageType == .nak else { return nil }
        guard let payload = parseNAK(parsed.payload) else { return nil }
        
        return FullNAK(
            sourceMUID: parsed.sourceMUID,
            destinationMUID: parsed.destinationMUID,
            originalTransaction: payload.originalTransaction,
            statusCode: payload.statusCode,
            statusData: payload.statusData,
            nakDetails: payload.nakDetails,
            messageText: payload.messageText
        )
    }
}

// MARK: - Convenience Extensions

extension CIMessageParser.ParsedMessage: CustomStringConvertible {
    public var description: String {
        "CI[\(messageType)] src:\(sourceMUID) dst:\(destinationMUID) payload:\(payload.count)bytes"
    }
}
