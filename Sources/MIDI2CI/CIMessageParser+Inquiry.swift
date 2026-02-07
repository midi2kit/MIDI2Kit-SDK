//
//  CIMessageParser+Inquiry.swift
//  MIDI2Kit
//
//  Parses MIDI-CI PE Inquiry messages for Responder implementation
//

import Foundation
import MIDI2Core

// MARK: - PE Inquiry Parsing

extension CIMessageParser {

    // MARK: - PE GET Inquiry (0x34)

    /// PE GET Inquiry payload structure
    public struct PEGetInquiryPayload: Sendable {
        public let requestID: UInt8
        public let headerData: Data
    }

    /// Parse PE GET Inquiry payload
    ///
    /// MIDI-CI PE GET Inquiry format (M2-105-UM Section 6.4.1):
    /// - requestID (1 byte, 7-bit)
    /// - headerLength (2 bytes, 14-bit)
    /// - headerData (headerLength bytes)
    ///
    /// - Parameter payload: Payload bytes (after destination MUID)
    /// - Returns: Parsed PE GET Inquiry, or nil if invalid
    public static func parsePEGetInquiry(_ payload: [UInt8]) -> PEGetInquiryPayload? {
        // Minimum: requestID(1) + headerLength(2) = 3 bytes
        guard payload.count >= 3 else { return nil }

        let requestID = payload[0] & 0x7F
        let headerLength = Int(payload[1]) | (Int(payload[2]) << 7)

        // Validate header fits
        let headerStart = 3
        let headerEnd = headerStart + headerLength
        guard headerEnd <= payload.count else { return nil }

        let headerData = Data(payload[headerStart..<headerEnd])

        return PEGetInquiryPayload(
            requestID: requestID,
            headerData: headerData
        )
    }

    /// Full PE GET Inquiry structure (including MUIDs)
    public struct FullPEGetInquiry: Sendable {
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let requestID: UInt8
        public let headerData: Data
        public let resource: String?
        public let resId: String?
        public let offset: Int?
        public let limit: Int?
    }

    /// Parse complete PE GET Inquiry SysEx message
    public static func parseFullPEGetInquiry(_ data: [UInt8]) -> FullPEGetInquiry? {
        guard let parsed = parse(data) else { return nil }
        guard parsed.messageType == .peGetInquiry else { return nil }
        guard let payload = parsePEGetInquiry(parsed.payload) else { return nil }

        // Parse header JSON for resource and other fields
        var resource: String? = nil
        var resId: String? = nil
        var offset: Int? = nil
        var limit: Int? = nil

        if !payload.headerData.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: payload.headerData) as? [String: Any] {
            resource = json["resource"] as? String
            resId = json["resId"] as? String
            offset = json["offset"] as? Int
            limit = json["limit"] as? Int
        }

        return FullPEGetInquiry(
            sourceMUID: parsed.sourceMUID,
            destinationMUID: parsed.destinationMUID,
            requestID: payload.requestID,
            headerData: payload.headerData,
            resource: resource,
            resId: resId,
            offset: offset,
            limit: limit
        )
    }

    // MARK: - PE SET Inquiry (0x36)

    /// PE SET Inquiry payload structure
    public struct PESetInquiryPayload: Sendable {
        public let requestID: UInt8
        public let headerData: Data
        public let propertyData: Data
        public let numChunks: Int
        public let thisChunk: Int
    }

    /// Parse PE SET Inquiry payload
    ///
    /// MIDI-CI PE SET Inquiry format (M2-105-UM):
    /// - requestID (1 byte, 7-bit)
    /// - headerLength (2 bytes, 14-bit)
    /// - headerData (headerLength bytes)
    /// - numChunks (2 bytes, 14-bit)
    /// - thisChunk (2 bytes, 14-bit)
    /// - dataLength (2 bytes, 14-bit)
    /// - propertyData (dataLength bytes)
    ///
    /// - Parameter payload: Payload bytes (after destination MUID)
    /// - Returns: Parsed PE SET Inquiry, or nil if invalid
    public static func parsePESetInquiry(_ payload: [UInt8]) -> PESetInquiryPayload? {
        // Minimum: requestID(1) + headerLength(2) = 3 bytes
        guard payload.count >= 3 else { return nil }

        let requestID = payload[0] & 0x7F
        let headerLength = Int(payload[1]) | (Int(payload[2]) << 7)

        // Header data comes immediately after headerLength
        let headerStart = 3
        let headerEnd = headerStart + headerLength
        guard headerEnd <= payload.count else { return nil }

        let headerData = Data(payload[headerStart..<headerEnd])

        // Chunk fields come after headerData
        // Need at least numChunks(2) + thisChunk(2) + dataLength(2) = 6 bytes
        let chunkFieldsStart = headerEnd
        guard chunkFieldsStart + 6 <= payload.count else { return nil }

        let numChunks = Int(payload[chunkFieldsStart]) | (Int(payload[chunkFieldsStart + 1]) << 7)
        let thisChunk = Int(payload[chunkFieldsStart + 2]) | (Int(payload[chunkFieldsStart + 3]) << 7)
        let dataLength = Int(payload[chunkFieldsStart + 4]) | (Int(payload[chunkFieldsStart + 5]) << 7)

        // Validate chunks
        guard numChunks >= 1, thisChunk >= 1, thisChunk <= numChunks else { return nil }

        // Validate property data fits
        let dataStart = chunkFieldsStart + 6
        let dataEnd = dataStart + dataLength
        guard dataEnd <= payload.count else { return nil }

        let propertyData = Data(payload[dataStart..<dataEnd])

        return PESetInquiryPayload(
            requestID: requestID,
            headerData: headerData,
            propertyData: propertyData,
            numChunks: numChunks,
            thisChunk: thisChunk
        )
    }

    /// Full PE SET Inquiry structure (including MUIDs)
    public struct FullPESetInquiry: Sendable {
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let requestID: UInt8
        public let headerData: Data
        public let propertyData: Data
        public let numChunks: Int
        public let thisChunk: Int
        public let resource: String?
        public let resId: String?
    }

    /// Parse complete PE SET Inquiry SysEx message
    public static func parseFullPESetInquiry(_ data: [UInt8]) -> FullPESetInquiry? {
        guard let parsed = parse(data) else { return nil }
        guard parsed.messageType == .peSetInquiry else { return nil }
        guard let payload = parsePESetInquiry(parsed.payload) else { return nil }

        // Parse header JSON for resource and other fields
        var resource: String? = nil
        var resId: String? = nil

        if !payload.headerData.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: payload.headerData) as? [String: Any] {
            resource = json["resource"] as? String
            resId = json["resId"] as? String
        }

        return FullPESetInquiry(
            sourceMUID: parsed.sourceMUID,
            destinationMUID: parsed.destinationMUID,
            requestID: payload.requestID,
            headerData: payload.headerData,
            propertyData: payload.propertyData,
            numChunks: payload.numChunks,
            thisChunk: payload.thisChunk,
            resource: resource,
            resId: resId
        )
    }

    // MARK: - PE Subscribe Inquiry (0x38)

    /// PE Subscribe Inquiry payload structure
    public struct PESubscribeInquiryPayload: Sendable {
        public let requestID: UInt8
        public let headerData: Data
        public let command: String?
        public let resource: String?
        public let subscribeId: String?
    }

    /// Parse PE Subscribe Inquiry payload
    ///
    /// Same format as PE GET Inquiry:
    /// - requestID (1 byte, 7-bit)
    /// - headerLength (2 bytes, 14-bit)
    /// - headerData (headerLength bytes)
    ///
    /// Header JSON contains:
    /// - resource: Resource name
    /// - command: "start" or "end"
    /// - subscribeId: (for "end" command)
    ///
    /// - Parameter payload: Payload bytes (after destination MUID)
    /// - Returns: Parsed PE Subscribe Inquiry, or nil if invalid
    public static func parsePESubscribeInquiry(_ payload: [UInt8]) -> PESubscribeInquiryPayload? {
        // Same format as GET Inquiry
        guard let getPayload = parsePEGetInquiry(payload) else { return nil }

        // Parse header JSON
        var command: String? = nil
        var resource: String? = nil
        var subscribeId: String? = nil

        if !getPayload.headerData.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: getPayload.headerData) as? [String: Any] {
            command = json["command"] as? String
            resource = json["resource"] as? String
            subscribeId = json["subscribeId"] as? String
        }

        return PESubscribeInquiryPayload(
            requestID: getPayload.requestID,
            headerData: getPayload.headerData,
            command: command,
            resource: resource,
            subscribeId: subscribeId
        )
    }

    /// Full PE Subscribe Inquiry structure (including MUIDs)
    public struct FullPESubscribeInquiry: Sendable {
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let requestID: UInt8
        public let headerData: Data
        public let command: String?
        public let resource: String?
        public let subscribeId: String?
    }

    /// Parse complete PE Subscribe Inquiry SysEx message
    public static func parseFullPESubscribeInquiry(_ data: [UInt8]) -> FullPESubscribeInquiry? {
        guard let parsed = parse(data) else { return nil }
        guard parsed.messageType == .peSubscribe else { return nil }
        guard let payload = parsePESubscribeInquiry(parsed.payload) else { return nil }

        return FullPESubscribeInquiry(
            sourceMUID: parsed.sourceMUID,
            destinationMUID: parsed.destinationMUID,
            requestID: payload.requestID,
            headerData: payload.headerData,
            command: payload.command,
            resource: payload.resource,
            subscribeId: payload.subscribeId
        )
    }

    // MARK: - PE Capability Inquiry (0x30)

    /// PE Capability Inquiry payload structure
    public struct PECapabilityInquiryPayload: Sendable {
        public let numSimultaneousRequests: UInt8
        public let majorVersion: UInt8
        public let minorVersion: UInt8
    }

    /// Parse PE Capability Inquiry payload
    public static func parsePECapabilityInquiry(_ payload: [UInt8]) -> PECapabilityInquiryPayload? {
        guard payload.count >= 3 else { return nil }

        return PECapabilityInquiryPayload(
            numSimultaneousRequests: payload[0],
            majorVersion: payload[1],
            minorVersion: payload[2]
        )
    }

    /// Full PE Capability Inquiry structure (including MUIDs)
    public struct FullPECapabilityInquiry: Sendable {
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let numSimultaneousRequests: UInt8
        public let majorVersion: UInt8
        public let minorVersion: UInt8
    }

    /// Parse complete PE Capability Inquiry SysEx message
    public static func parseFullPECapabilityInquiry(_ data: [UInt8]) -> FullPECapabilityInquiry? {
        guard let parsed = parse(data) else { return nil }
        guard parsed.messageType == .peCapabilityInquiry else { return nil }
        guard let payload = parsePECapabilityInquiry(parsed.payload) else { return nil }

        return FullPECapabilityInquiry(
            sourceMUID: parsed.sourceMUID,
            destinationMUID: parsed.destinationMUID,
            numSimultaneousRequests: payload.numSimultaneousRequests,
            majorVersion: payload.majorVersion,
            minorVersion: payload.minorVersion
        )
    }

    // MARK: - Discovery Inquiry (0x70)

    /// Full Discovery Inquiry structure
    public struct FullDiscoveryInquiry: Sendable {
        public let sourceMUID: MUID
        public let identity: DeviceIdentity
        public let categorySupport: CategorySupport
        public let maxSysExSize: UInt32
        public let initiatorOutputPath: UInt8
    }

    /// Parse complete Discovery Inquiry SysEx message
    public static func parseFullDiscoveryInquiry(_ data: [UInt8]) -> FullDiscoveryInquiry? {
        guard let parsed = parse(data) else { return nil }
        guard parsed.messageType == .discoveryInquiry else { return nil }

        // Payload: identity(11) + categorySupport(1) + maxSysExSize(4) + outputPath(1) = 17 bytes
        guard parsed.payload.count >= 11 else { return nil }

        guard let identity = DeviceIdentity(from: parsed.payload, offset: 0) else { return nil }

        let categorySupport: CategorySupport
        if parsed.payload.count > 11 {
            categorySupport = CategorySupport(rawValue: parsed.payload[11])
        } else {
            categorySupport = .propertyExchange
        }

        let maxSysExSize: UInt32
        if parsed.payload.count >= 16 {
            maxSysExSize = UInt32(parsed.payload[12])
                | (UInt32(parsed.payload[13]) << 7)
                | (UInt32(parsed.payload[14]) << 14)
                | (UInt32(parsed.payload[15]) << 21)
        } else {
            maxSysExSize = 0
        }

        let initiatorOutputPath = parsed.payload.count > 16 ? parsed.payload[16] : 0

        return FullDiscoveryInquiry(
            sourceMUID: parsed.sourceMUID,
            identity: identity,
            categorySupport: categorySupport,
            maxSysExSize: maxSysExSize,
            initiatorOutputPath: initiatorOutputPath
        )
    }
}
