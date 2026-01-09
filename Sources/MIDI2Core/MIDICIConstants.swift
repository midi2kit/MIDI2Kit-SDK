//
//  MIDICIConstants.swift
//  MIDI2Kit
//
//  MIDI-CI Protocol Constants
//

import Foundation

/// MIDI-CI Protocol Constants
public enum MIDICIConstants {
    
    // MARK: - SysEx Framing
    
    /// Universal SysEx Non-Realtime ID
    public static let sysExNonRealtime: UInt8 = 0x7E
    
    /// Universal SysEx Realtime ID
    public static let sysExRealtime: UInt8 = 0x7F
    
    /// MIDI-CI Sub-ID #1
    public static let ciSubID1: UInt8 = 0x0D
    
    /// SysEx Start
    public static let sysExStart: UInt8 = 0xF0
    
    /// SysEx End
    public static let sysExEnd: UInt8 = 0xF7
    
    // MARK: - CI Message Version
    
    /// MIDI-CI version 1.1
    public static let ciVersion1_1: UInt8 = 0x01
    
    /// MIDI-CI version 1.2
    public static let ciVersion1_2: UInt8 = 0x02
    
    // MARK: - Category Support Bits
    
    /// Protocol Negotiation supported
    public static let categoryProtocolNegotiation: UInt8 = 0b0000_0010
    
    /// Profile Configuration supported
    public static let categoryProfileConfiguration: UInt8 = 0b0000_0100
    
    /// Property Exchange supported
    public static let categoryPropertyExchange: UInt8 = 0b0000_1000
    
    /// Process Inquiry supported
    public static let categoryProcessInquiry: UInt8 = 0b0001_0000
    
    // MARK: - Default Values
    
    /// Default maximum SysEx size (no limit)
    public static let maxSysExSizeUnlimited: UInt32 = 0x0000_0000
    
    /// Typical maximum SysEx size for constrained devices
    public static let maxSysExSize4K: UInt32 = 4096
}

/// MIDI-CI Message Types
public enum CIMessageType: UInt8, Sendable, CaseIterable {
    
    // MARK: - Management Messages
    
    /// Discovery Inquiry (broadcast)
    case discoveryInquiry = 0x70
    
    /// Discovery Reply
    case discoveryReply = 0x71
    
    /// Endpoint Information Inquiry
    case endpointInfoInquiry = 0x72
    
    /// Endpoint Information Reply
    case endpointInfoReply = 0x73
    
    /// Invalidate MUID
    case invalidateMUID = 0x7E
    
    /// NAK (Negative Acknowledgement)
    case nak = 0x7F
    
    /// ACK (Acknowledgement) - CI 1.2+
    case ack = 0x7D
    
    // MARK: - Protocol Negotiation (0x1x)
    
    /// Protocol Negotiation Inquiry
    case protocolInquiry = 0x10
    
    /// Protocol Negotiation Reply
    case protocolReply = 0x11
    
    /// Set New Protocol
    case setProtocol = 0x12
    
    /// Test New Protocol - Initiator to Responder
    case testNewProtocolI2R = 0x13
    
    /// Test New Protocol - Responder to Initiator
    case testNewProtocolR2I = 0x14
    
    /// Confirm New Protocol Established
    case confirmProtocol = 0x15
    
    // MARK: - Profile Configuration (0x2x)
    
    /// Profile Inquiry
    case profileInquiry = 0x20
    
    /// Profile Inquiry Reply
    case profileReply = 0x21
    
    /// Set Profile On
    case setProfileOn = 0x22
    
    /// Set Profile Off
    case setProfileOff = 0x23
    
    /// Profile Enabled Report
    case profileEnabledReport = 0x24
    
    /// Profile Disabled Report
    case profileDisabledReport = 0x25
    
    /// Profile Added Report
    case profileAddedReport = 0x26
    
    /// Profile Removed Report
    case profileRemovedReport = 0x27
    
    /// Profile Details Inquiry
    case profileDetailsInquiry = 0x28
    
    /// Profile Details Reply
    case profileDetailsReply = 0x29
    
    /// Profile Specific Data
    case profileSpecificData = 0x2F
    
    // MARK: - Property Exchange (0x3x)
    
    /// PE Capability Inquiry
    case peCapabilityInquiry = 0x30
    
    /// PE Capability Reply
    case peCapabilityReply = 0x31
    
    /// PE Get Inquiry (request property)
    case peGetInquiry = 0x34
    
    /// PE Get Reply (property data)
    case peGetReply = 0x35
    
    /// PE Set Inquiry (set property)
    case peSetInquiry = 0x36
    
    /// PE Set Reply (confirmation)
    case peSetReply = 0x37
    
    /// PE Subscribe Inquiry
    case peSubscribe = 0x38
    
    /// PE Subscribe Reply
    case peSubscribeReply = 0x39
    
    /// PE Notify (subscription notification)
    case peNotify = 0x3F
    
    // MARK: - Process Inquiry (0x4x)
    
    /// Process Inquiry Capability Inquiry
    case processInquiryCapability = 0x40
    
    /// Process Inquiry Capability Reply
    case processInquiryCapabilityReply = 0x41
    
    /// MIDI Message Report Inquiry
    case midiMessageReportInquiry = 0x42
    
    /// MIDI Message Report Reply
    case midiMessageReportReply = 0x43
    
    /// End of MIDI Message Report
    case midiMessageReportEnd = 0x44
}

/// Category support flags for MIDI-CI devices
public struct CategorySupport: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    /// Protocol Negotiation supported
    public static let protocolNegotiation = CategorySupport(rawValue: 0b0000_0010)
    
    /// Profile Configuration supported
    public static let profileConfiguration = CategorySupport(rawValue: 0b0000_0100)
    
    /// Property Exchange supported
    public static let propertyExchange = CategorySupport(rawValue: 0b0000_1000)
    
    /// Process Inquiry supported
    public static let processInquiry = CategorySupport(rawValue: 0b0001_0000)
    
    /// All categories supported
    public static let all: CategorySupport = [
        .protocolNegotiation,
        .profileConfiguration,
        .propertyExchange,
        .processInquiry
    ]
}

extension CategorySupport: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        if contains(.protocolNegotiation) { parts.append("Protocol") }
        if contains(.profileConfiguration) { parts.append("Profile") }
        if contains(.propertyExchange) { parts.append("PE") }
        if contains(.processInquiry) { parts.append("Process") }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }
}
