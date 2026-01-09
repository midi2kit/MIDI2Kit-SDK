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
    /// - Returns: Parsed PE reply, or nil if invalid
    public static func parsePEReply(_ payload: [UInt8]) -> PEReplyPayload? {
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
        
        // Extract header data
        let headerStart = 9
        let headerEnd = headerStart + headerSize
        guard payload.count >= headerEnd else { return nil }
        let headerData = Data(payload[headerStart..<headerEnd])
        
        // Extract property data
        let dataStart = headerEnd
        let dataEnd = dataStart + dataSize
        guard payload.count >= dataEnd else { return nil }
        let propertyData = Data(payload[dataStart..<dataEnd])
        
        return PEReplyPayload(
            requestID: requestID,
            headerData: headerData,
            propertyData: propertyData,
            numChunks: numChunks,
            thisChunk: thisChunk
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
}

// MARK: - Convenience Extensions

extension CIMessageParser.ParsedMessage: CustomStringConvertible {
    public var description: String {
        "CI[\(messageType)] src:\(sourceMUID) dst:\(destinationMUID) payload:\(payload.count)bytes"
    }
}
