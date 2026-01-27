//
//  CIMessageBuilder.swift
//  MIDI2Kit
//
//  Builds MIDI-CI SysEx messages
//

import Foundation
import MIDI2Core

/// Builds MIDI-CI SysEx messages
public enum CIMessageBuilder {
    
    // MARK: - Discovery
    
    /// Build Discovery Inquiry message (broadcast)
    /// - Parameters:
    ///   - sourceMUID: Sender's MUID
    ///   - deviceIdentity: Sender's device identity
    ///   - categorySupport: Supported CI categories
    ///   - maxSysExSize: Maximum SysEx size (0 = unlimited)
    ///   - initiatorOutputPath: Output path ID (CI 1.2+)
    /// - Returns: Complete SysEx message bytes
    public static func discoveryInquiry(
        sourceMUID: MUID,
        deviceIdentity: DeviceIdentity = .init(
            manufacturerID: .standard(0x7D),  // Educational/Development
            familyID: 0x0000,
            modelID: 0x0000,
            versionID: 0x00000100
        ),
        categorySupport: CategorySupport = .propertyExchange,
        maxSysExSize: UInt32 = 0,
        initiatorOutputPath: UInt8 = 0
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,  // Device ID (broadcast)
            MIDICIConstants.ciSubID1,
            CIMessageType.discoveryInquiry.rawValue,
            MIDICIConstants.ciVersion1_1  // Use CI 1.1 for KORG Module Pro compatibility
        ]
        
        // Source MUID
        message.append(contentsOf: sourceMUID.bytes)
        
        // Destination MUID (broadcast)
        message.append(contentsOf: MUID.broadcast.bytes)
        
        // Device Identity
        message.append(contentsOf: deviceIdentity.bytes)
        
        // Category Support
        message.append(categorySupport.rawValue)
        
        // Max SysEx Size (4 bytes, LSB first)
        message.append(UInt8(maxSysExSize & 0x7F))
        message.append(UInt8((maxSysExSize >> 7) & 0x7F))
        message.append(UInt8((maxSysExSize >> 14) & 0x7F))
        message.append(UInt8((maxSysExSize >> 21) & 0x7F))
        
        // Initiator Output Path ID (CI 1.2+)
        message.append(initiatorOutputPath)
        
        message.append(MIDICIConstants.sysExEnd)
        return message
    }
    
    /// Build Discovery Reply message
    public static func discoveryReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        deviceIdentity: DeviceIdentity,
        categorySupport: CategorySupport,
        maxSysExSize: UInt32 = 0,
        initiatorOutputPath: UInt8 = 0,
        functionBlock: UInt8 = 0
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            CIMessageType.discoveryReply.rawValue,
            MIDICIConstants.ciVersion1_1  // Use CI 1.1 for KORG Module Pro compatibility
        ]
        
        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)
        message.append(contentsOf: deviceIdentity.bytes)
        message.append(categorySupport.rawValue)
        
        // Max SysEx Size
        message.append(UInt8(maxSysExSize & 0x7F))
        message.append(UInt8((maxSysExSize >> 7) & 0x7F))
        message.append(UInt8((maxSysExSize >> 14) & 0x7F))
        message.append(UInt8((maxSysExSize >> 21) & 0x7F))
        
        // Output Path ID
        message.append(initiatorOutputPath)
        
        // Function Block (CI 1.2+)
        message.append(functionBlock)
        
        message.append(MIDICIConstants.sysExEnd)
        return message
    }
    
    /// Build Invalidate MUID message
    public static func invalidateMUID(
        sourceMUID: MUID,
        targetMUID: MUID
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            CIMessageType.invalidateMUID.rawValue,
            MIDICIConstants.ciVersion1_1  // Use CI 1.1 for KORG Module Pro compatibility
        ]
        
        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: MUID.broadcast.bytes)
        message.append(contentsOf: targetMUID.bytes)
        
        message.append(MIDICIConstants.sysExEnd)
        return message
    }
    
    // MARK: - Property Exchange
    
    /// Build PE Capability Inquiry message
    public static func peCapabilityInquiry(
        sourceMUID: MUID,
        destinationMUID: MUID,
        numSimultaneousRequests: UInt8 = 1,
        majorVersion: UInt8 = 0,
        minorVersion: UInt8 = 2  // PE Version 0.2 for KORG compatibility
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            CIMessageType.peCapabilityInquiry.rawValue,
            MIDICIConstants.ciVersion1_1  // Use CI 1.1 for KORG Module Pro compatibility
        ]
        
        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)
        message.append(numSimultaneousRequests)
        message.append(majorVersion)
        message.append(minorVersion)
        
        message.append(MIDICIConstants.sysExEnd)
        return message
    }
    
    /// Build PE Get Inquiry message
    /// 
    /// MIDI-CI 1.1/1.2 PE Get Inquiry format (M2-105-UM Section 6.4.1):
    /// - requestID (1 byte, 7-bit)
    /// - headerLength (2 bytes, 14-bit)
    /// - headerData (variable)
    /// 
    /// Note: Unlike PE Reply, PE Get Inquiry does NOT include numChunks/thisChunk/dataSize
    public static func peGetInquiry(
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
            CIMessageType.peGetInquiry.rawValue,
            MIDICIConstants.ciVersion1_1  // Use CI 1.1 for KORG Module Pro compatibility
        ]
        
        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)
        
        // Request ID (7-bit)
        message.append(requestID & 0x7F)
        
        // Header size (14-bit, LSB first)
        let headerSize = headerData.count
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))
        
        // Header data (immediately after headerSize - no numChunks/thisChunk in inquiry)
        message.append(contentsOf: headerData)
        
        message.append(MIDICIConstants.sysExEnd)
        return message
    }
    
    /// Build PE Set Inquiry message
    public static func peSetInquiry(
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
            CIMessageType.peSetInquiry.rawValue,
            MIDICIConstants.ciVersion1_1  // Use CI 1.1 for KORG Module Pro compatibility
        ]
        
        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)
        
        // Request ID
        message.append(requestID & 0x7F)
        
        // Header size
        let headerSize = headerData.count
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))
        
        // Number of chunks
        message.append(UInt8(numChunks & 0x7F))
        message.append(UInt8((numChunks >> 7) & 0x7F))
        
        // This chunk
        message.append(UInt8(thisChunk & 0x7F))
        message.append(UInt8((thisChunk >> 7) & 0x7F))
        
        // Property data size
        let dataSize = propertyData.count
        message.append(UInt8(dataSize & 0x7F))
        message.append(UInt8((dataSize >> 7) & 0x7F))
        
        // Header data
        message.append(contentsOf: headerData)
        
        // Property data
        message.append(contentsOf: propertyData)
        
        message.append(MIDICIConstants.sysExEnd)
        return message
    }
    
    // MARK: - Header Builders
    
    /// Build JSON header for resource request
    public static func resourceRequestHeader(resource: String) -> Data {
        let json = "{\"resource\":\"\(resource)\"}"
        return Data(json.utf8)
    }
    
    /// Build JSON header for channel-specific resource
    public static func channelResourceHeader(resource: String, channel: Int) -> Data {
        let json = "{\"resource\":\"\(resource)\",\"resId\":\"\(channel)\"}"
        return Data(json.utf8)
    }
    
    /// Build JSON header for paginated request
    public static func paginatedRequestHeader(
        resource: String,
        offset: Int,
        limit: Int
    ) -> Data {
        let json = "{\"resource\":\"\(resource)\",\"offset\":\(offset),\"limit\":\(limit)}"
        return Data(json.utf8)
    }
    
    // MARK: - Property Exchange Subscribe
    
    /// Build PE Subscribe Inquiry message
    /// 
    /// MIDI-CI 1.1/1.2 PE Subscribe format (M2-105-UM Section 6.5):
    /// - requestID (1 byte, 7-bit)
    /// - headerLength (2 bytes, 14-bit)
    /// - headerData (variable)
    /// 
    /// Note: Like PE Get Inquiry, Subscribe does NOT include numChunks/thisChunk/dataSize
    public static func peSubscribeInquiry(
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
            CIMessageType.peSubscribe.rawValue,
            MIDICIConstants.ciVersion1_1  // Use CI 1.1 for KORG Module Pro compatibility
        ]
        
        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)
        
        // Request ID (7-bit)
        message.append(requestID & 0x7F)
        
        // Header size (14-bit, LSB first)
        let headerSize = headerData.count
        message.append(UInt8(headerSize & 0x7F))
        message.append(UInt8((headerSize >> 7) & 0x7F))
        
        // Header data (immediately after headerSize)
        message.append(contentsOf: headerData)
        
        message.append(MIDICIConstants.sysExEnd)
        return message
    }
    
    /// Build JSON header for subscribe start
    public static func subscribeStartHeader(resource: String) -> Data {
        let json = "{\"resource\":\"\(resource)\",\"command\":\"start\"}"
        return Data(json.utf8)
    }
    
    /// Build JSON header for subscribe end (unsubscribe)
    public static func subscribeEndHeader(resource: String, subscribeId: String) -> Data {
        let json = "{\"resource\":\"\(resource)\",\"command\":\"end\",\"subscribeId\":\"\(subscribeId)\"}"
        return Data(json.utf8)
    }
}
