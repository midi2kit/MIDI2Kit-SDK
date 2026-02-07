//
//  CIMessageBuilder+Reply.swift
//  MIDI2Kit
//
//  Builds MIDI-CI PE Reply messages for Responder implementation
//

import Foundation
import MIDI2Core

// MARK: - PE Reply Builders

extension CIMessageBuilder {

    // MARK: - PE GET Reply (0x35)

    /// Build PE GET Reply message
    ///
    /// MIDI-CI PE Reply format:
    /// - requestID (1 byte, 7-bit)
    /// - headerLength (2 bytes, 14-bit)
    /// - numChunks (2 bytes, 14-bit)
    /// - thisChunk (2 bytes, 14-bit)
    /// - dataLength (2 bytes, 14-bit)
    /// - headerData (headerLength bytes)
    /// - propertyData (dataLength bytes)
    public static func peGetReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        headerData: Data,
        propertyData: Data,
        numChunks: Int = 1,
        thisChunk: Int = 1
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            CIMessageType.peGetReply.rawValue,
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)

        // Request ID
        message.append(requestID & 0x7F)

        // Header size (14-bit)
        let headerSize = headerData.count
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))

        // Header data (MUST come before chunks per MIDI-CI PE spec)
        message.append(contentsOf: headerData)

        // Number of chunks (14-bit)
        message.append(UInt8(numChunks & 0x7F))
        message.append(UInt8((numChunks >> 7) & 0x7F))

        // This chunk (14-bit)
        message.append(UInt8(thisChunk & 0x7F))
        message.append(UInt8((thisChunk >> 7) & 0x7F))

        // Property data size (14-bit)
        let dataSize = propertyData.count
        message.append(UInt8(dataSize & 0x7F))
        message.append(UInt8((dataSize >> 7) & 0x7F))

        // Property data
        message.append(contentsOf: propertyData)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }

    // MARK: - PE SET Reply (0x37)

    /// Build PE SET Reply message
    ///
    /// SET Reply uses same format as GET Reply but typically has no property data
    public static func peSetReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        headerData: Data,
        numChunks: Int = 1,
        thisChunk: Int = 1
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            CIMessageType.peSetReply.rawValue,
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)

        // Request ID
        message.append(requestID & 0x7F)

        // Header size (14-bit)
        let headerSize = headerData.count
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))

        // Header data (MUST come before chunks per MIDI-CI PE spec)
        message.append(contentsOf: headerData)

        // Number of chunks (14-bit)
        message.append(UInt8(numChunks & 0x7F))
        message.append(UInt8((numChunks >> 7) & 0x7F))

        // This chunk (14-bit)
        message.append(UInt8(thisChunk & 0x7F))
        message.append(UInt8((thisChunk >> 7) & 0x7F))

        // Property data size (14-bit) - 0 for SET reply
        message.append(0)
        message.append(0)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }

    // MARK: - PE Capability Reply (0x31)

    /// Build PE Capability Reply message
    public static func peCapabilityReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        numSimultaneousRequests: UInt8 = 1,
        majorVersion: UInt8 = 0,
        minorVersion: UInt8 = 2
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            CIMessageType.peCapabilityReply.rawValue,
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)
        message.append(numSimultaneousRequests)
        message.append(majorVersion)
        message.append(minorVersion)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }

    // MARK: - PE Subscribe Reply (0x39)

    /// Build PE Subscribe Reply message
    public static func peSubscribeReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        headerData: Data
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            CIMessageType.peSubscribeReply.rawValue,
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)

        // Request ID
        message.append(requestID & 0x7F)

        // Header size (14-bit)
        let headerSize = headerData.count
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))

        // Header data (MUST come before chunks per MIDI-CI PE spec)
        message.append(contentsOf: headerData)

        // Number of chunks (14-bit) = 1
        message.append(1)
        message.append(0)

        // This chunk (14-bit) = 1
        message.append(1)
        message.append(0)

        // Property data size (14-bit) = 0
        message.append(0)
        message.append(0)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }

    // MARK: - PE Notify (via 0x38 Subscription with command:notify)

    /// Build PE Notify message (for subscription notifications)
    /// Uses sub-ID2 0x38 (Subscription) with "command":"notify" header per MIDI-CI PE v1.1.
    /// KORG KeyStage does not recognize 0x3F (PE Notify, CI v1.2+).
    public static func peNotify(
        sourceMUID: MUID,
        destinationMUID: MUID,
        requestID: UInt8,
        headerData: Data,
        propertyData: Data,
        numChunks: Int = 1,
        thisChunk: Int = 1
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            CIMessageType.peSubscribe.rawValue,  // 0x38: KORG KeyStage requires Subscription msg for notify
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)

        // Request ID
        message.append(requestID & 0x7F)

        // Header size (14-bit)
        let headerSize = headerData.count
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))

        // Header data (MUST come before chunks per MIDI-CI PE spec)
        message.append(contentsOf: headerData)

        // Number of chunks (14-bit)
        message.append(UInt8(numChunks & 0x7F))
        message.append(UInt8((numChunks >> 7) & 0x7F))

        // This chunk (14-bit)
        message.append(UInt8(thisChunk & 0x7F))
        message.append(UInt8((thisChunk >> 7) & 0x7F))

        // Property data size (14-bit)
        let dataSize = propertyData.count
        message.append(UInt8(dataSize & 0x7F))
        message.append(UInt8((dataSize >> 7) & 0x7F))

        // Property data
        message.append(contentsOf: propertyData)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }

    // MARK: - Response Header Builders

    /// Build JSON header for successful PE response
    public static func successResponseHeader(status: Int = 200) -> Data {
        let json = "{\"status\":\(status)}"
        return Data(json.utf8)
    }

    /// Build JSON header for failed PE response
    public static func errorResponseHeader(status: Int, message: String? = nil) -> Data {
        if let message = message {
            // Use JSONSerialization for safe escaping of all special characters
            let json: [String: Any] = ["status": status, "message": message]
            if let data = try? JSONSerialization.data(withJSONObject: json, options: []) {
                return data
            }
        }
        // Fallback to status-only response
        return Data("{\"status\":\(status)}".utf8)
    }

    /// Build JSON header for subscribe response
    public static func subscribeResponseHeader(status: Int = 200, subscribeId: String) -> Data {
        let json = "{\"status\":\(status),\"subscribeId\":\"\(subscribeId)\"}"
        return Data(json.utf8)
    }

    /// Build JSON header for notify message
    /// Per MIDI-CI PE spec, Notify header includes "command":"notify"
    public static func notifyHeader(subscribeId: String, resource: String? = nil) -> Data {
        if let resource = resource {
            let json = "{\"subscribeId\":\"\(subscribeId)\",\"resource\":\"\(resource)\",\"command\":\"notify\"}"
            return Data(json.utf8)
        } else {
            let json = "{\"subscribeId\":\"\(subscribeId)\",\"command\":\"notify\"}"
            return Data(json.utf8)
        }
    }
}
