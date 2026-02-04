//
//  ProcessInquiry.swift
//  MIDI2Kit
//
//  MIDI-CI Process Inquiry Messages
//
//  Process Inquiry allows devices to report their current MIDI message processing
//  capabilities, including supported message types, controllers, and note ranges.
//
//  Reference: MIDI-CI Specification, Section 8 (Process Inquiry)
//

import Foundation
import MIDI2Core

// MARK: - Process Inquiry Message Types

/// MIDI-CI Process Inquiry message types
public enum ProcessInquiryMessageType: UInt8, Sendable {
    /// Process Inquiry Capabilities Inquiry (0x40)
    case capabilitiesInquiry = 0x40

    /// Process Inquiry Capabilities Reply (0x41)
    case capabilitiesReply = 0x41

    /// MIDI Message Report Inquiry (0x42)
    case midiMessageReportInquiry = 0x42

    /// MIDI Message Report Reply (0x43)
    case midiMessageReportReply = 0x43

    /// End of MIDI Message Report (0x44)
    case endOfMidiMessageReport = 0x44
}

// MARK: - Process Inquiry Capabilities

/// Supported Process Inquiry features
public struct ProcessInquiryCapabilities: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Device supports MIDI Message Report
    public static let midiMessageReport = ProcessInquiryCapabilities(rawValue: 1 << 0)

    /// Device supports getting default MIDI message report
    public static let defaultReport = ProcessInquiryCapabilities(rawValue: 1 << 1)
}

// MARK: - MIDI Message Type Flags

/// Flags indicating which MIDI message types to report
public struct MIDIMessageTypeFlags: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Report all message types
    public static let all: MIDIMessageTypeFlags = [
        .noteOff, .noteOn, .polyPressure, .controlChange,
        .programChange, .channelPressure, .pitchBend
    ]

    /// Note Off messages
    public static let noteOff = MIDIMessageTypeFlags(rawValue: 1 << 0)

    /// Note On messages
    public static let noteOn = MIDIMessageTypeFlags(rawValue: 1 << 1)

    /// Poly Pressure (Aftertouch) messages
    public static let polyPressure = MIDIMessageTypeFlags(rawValue: 1 << 2)

    /// Control Change messages
    public static let controlChange = MIDIMessageTypeFlags(rawValue: 1 << 3)

    /// Program Change messages
    public static let programChange = MIDIMessageTypeFlags(rawValue: 1 << 4)

    /// Channel Pressure (Aftertouch) messages
    public static let channelPressure = MIDIMessageTypeFlags(rawValue: 1 << 5)

    /// Pitch Bend messages
    public static let pitchBend = MIDIMessageTypeFlags(rawValue: 1 << 6)

    /// Registered Controllers (RPN) - bit in system byte
    public static let registeredController = MIDIMessageTypeFlags(rawValue: 1 << 0)

    /// Assignable Controllers (NRPN) - bit in system byte
    public static let assignableController = MIDIMessageTypeFlags(rawValue: 1 << 1)
}

// MARK: - MIDI Message Report Request

/// Request parameters for MIDI Message Report
public struct MIDIMessageReportRequest: Sendable {
    /// Request MIDI 1.0 protocol messages
    public let requestMIDI1: Bool

    /// Request MIDI 2.0 protocol messages
    public let requestMIDI2: Bool

    /// Message types to report
    public let messageTypes: MIDIMessageTypeFlags

    /// Request channel controller report (CC, RPN, NRPN)
    public let requestControllerReport: Bool

    /// Request Note Data report
    public let requestNoteDataReport: Bool

    public init(
        requestMIDI1: Bool = true,
        requestMIDI2: Bool = true,
        messageTypes: MIDIMessageTypeFlags = .all,
        requestControllerReport: Bool = true,
        requestNoteDataReport: Bool = true
    ) {
        self.requestMIDI1 = requestMIDI1
        self.requestMIDI2 = requestMIDI2
        self.messageTypes = messageTypes
        self.requestControllerReport = requestControllerReport
        self.requestNoteDataReport = requestNoteDataReport
    }
}

// MARK: - Process Inquiry Capabilities Reply

/// Response to Process Inquiry Capabilities Inquiry
public struct ProcessInquiryCapabilitiesReply: Sendable {
    /// Supported features
    public let capabilities: ProcessInquiryCapabilities

    public init(capabilities: ProcessInquiryCapabilities) {
        self.capabilities = capabilities
    }
}

// MARK: - MIDI Message Report

/// MIDI Message Report data
public struct MIDIMessageReport: Sendable {
    /// Controller list (CC numbers, RPN/NRPN addresses)
    public let controllers: [UInt8]

    /// Note range (lowest and highest notes)
    public let noteRange: ClosedRange<UInt8>?

    /// Supported message types
    public let supportedTypes: MIDIMessageTypeFlags

    public init(
        controllers: [UInt8] = [],
        noteRange: ClosedRange<UInt8>? = nil,
        supportedTypes: MIDIMessageTypeFlags = []
    ) {
        self.controllers = controllers
        self.noteRange = noteRange
        self.supportedTypes = supportedTypes
    }
}

// MARK: - CIMessageBuilder Extension

extension CIMessageBuilder {

    // MARK: - Process Inquiry Capabilities

    /// Build Process Inquiry Capabilities Inquiry message
    /// - Parameters:
    ///   - sourceMUID: Sender's MUID
    ///   - destinationMUID: Target device's MUID
    /// - Returns: Complete SysEx message bytes
    public static func processInquiryCapabilitiesInquiry(
        sourceMUID: MUID,
        destinationMUID: MUID
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            ProcessInquiryMessageType.capabilitiesInquiry.rawValue,
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }

    /// Build Process Inquiry Capabilities Reply message
    /// - Parameters:
    ///   - sourceMUID: Sender's MUID
    ///   - destinationMUID: Target device's MUID
    ///   - capabilities: Supported capabilities
    /// - Returns: Complete SysEx message bytes
    public static func processInquiryCapabilitiesReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        capabilities: ProcessInquiryCapabilities
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            ProcessInquiryMessageType.capabilitiesReply.rawValue,
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)
        message.append(capabilities.rawValue)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }

    // MARK: - MIDI Message Report

    /// Build MIDI Message Report Inquiry message
    /// - Parameters:
    ///   - sourceMUID: Sender's MUID
    ///   - destinationMUID: Target device's MUID
    ///   - request: Report request parameters
    /// - Returns: Complete SysEx message bytes
    public static func midiMessageReportInquiry(
        sourceMUID: MUID,
        destinationMUID: MUID,
        request: MIDIMessageReportRequest = MIDIMessageReportRequest()
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            ProcessInquiryMessageType.midiMessageReportInquiry.rawValue,
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)

        // Data format byte
        var dataFormat: UInt8 = 0
        if request.requestMIDI1 { dataFormat |= 0x01 }
        if request.requestMIDI2 { dataFormat |= 0x02 }
        message.append(dataFormat)

        // System message flags
        var systemFlags: UInt8 = 0
        if request.messageTypes.contains(.registeredController) { systemFlags |= 0x01 }
        if request.messageTypes.contains(.assignableController) { systemFlags |= 0x02 }
        message.append(systemFlags)

        // Reserved byte
        message.append(0x00)

        // Channel controller flags
        message.append(request.messageTypes.rawValue)

        // Note data flag
        message.append(request.requestNoteDataReport ? 0x01 : 0x00)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }

    /// Build MIDI Message Report Reply message
    /// - Parameters:
    ///   - sourceMUID: Sender's MUID
    ///   - destinationMUID: Target device's MUID
    ///   - report: Report data
    /// - Returns: Complete SysEx message bytes
    public static func midiMessageReportReply(
        sourceMUID: MUID,
        destinationMUID: MUID,
        report: MIDIMessageReport
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            ProcessInquiryMessageType.midiMessageReportReply.rawValue,
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)

        // System message flags
        message.append(0x00)

        // Reserved
        message.append(0x00)

        // Channel controller flags
        message.append(report.supportedTypes.rawValue)

        // Note data presence
        message.append(report.noteRange != nil ? 0x01 : 0x00)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }

    /// Build End of MIDI Message Report message
    /// - Parameters:
    ///   - sourceMUID: Sender's MUID
    ///   - destinationMUID: Target device's MUID
    /// - Returns: Complete SysEx message bytes
    public static func endOfMidiMessageReport(
        sourceMUID: MUID,
        destinationMUID: MUID
    ) -> [UInt8] {
        var message: [UInt8] = [
            MIDICIConstants.sysExStart,
            MIDICIConstants.sysExNonRealtime,
            0x7F,
            MIDICIConstants.ciSubID1,
            ProcessInquiryMessageType.endOfMidiMessageReport.rawValue,
            MIDICIConstants.ciVersion1_1
        ]

        message.append(contentsOf: sourceMUID.bytes)
        message.append(contentsOf: destinationMUID.bytes)

        message.append(MIDICIConstants.sysExEnd)
        return message
    }
}

// MARK: - CIMessageParser Extension

extension CIMessageParser {

    /// Process Inquiry Capabilities Reply payload
    public struct ProcessInquiryCapabilitiesPayload: Sendable {
        public let capabilities: ProcessInquiryCapabilities
    }

    /// Parse Process Inquiry Capabilities Reply payload
    public static func parseProcessInquiryCapabilitiesReply(_ payload: [UInt8]) -> ProcessInquiryCapabilitiesPayload? {
        guard payload.count >= 1 else { return nil }
        return ProcessInquiryCapabilitiesPayload(
            capabilities: ProcessInquiryCapabilities(rawValue: payload[0])
        )
    }

    /// MIDI Message Report Reply payload
    public struct MIDIMessageReportPayload: Sendable {
        public let systemFlags: UInt8
        public let channelFlags: MIDIMessageTypeFlags
        public let hasNoteData: Bool
    }

    /// Parse MIDI Message Report Reply payload
    public static func parseMIDIMessageReportReply(_ payload: [UInt8]) -> MIDIMessageReportPayload? {
        guard payload.count >= 4 else { return nil }

        return MIDIMessageReportPayload(
            systemFlags: payload[0],
            channelFlags: MIDIMessageTypeFlags(rawValue: payload[2]),
            hasNoteData: payload[3] != 0
        )
    }

    /// Full Process Inquiry Capabilities Reply structure
    public struct FullProcessInquiryCapabilitiesReply: Sendable {
        public let sourceMUID: MUID
        public let destinationMUID: MUID
        public let capabilities: ProcessInquiryCapabilities
    }

    /// Parse complete Process Inquiry Capabilities Reply SysEx message
    public static func parseFullProcessInquiryCapabilitiesReply(_ data: [UInt8]) -> FullProcessInquiryCapabilitiesReply? {
        guard let parsed = parse(data) else { return nil }

        // Verify message type (use existing enum case)
        guard parsed.messageType == .processInquiryCapabilityReply else { return nil }

        guard let payload = parseProcessInquiryCapabilitiesReply(parsed.payload) else { return nil }

        return FullProcessInquiryCapabilitiesReply(
            sourceMUID: parsed.sourceMUID,
            destinationMUID: parsed.destinationMUID,
            capabilities: payload.capabilities
        )
    }
}

// Note: Process Inquiry message types are already defined in CIMessageType enum:
// - .processInquiryCapability (0x40)
// - .processInquiryCapabilityReply (0x41)
// - .midiMessageReportInquiry (0x42)
// - .midiMessageReportReply (0x43)
// - .midiMessageReportEnd (0x44)
