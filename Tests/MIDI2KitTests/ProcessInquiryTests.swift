//
//  ProcessInquiryTests.swift
//  MIDI2KitTests
//
//  Tests for MIDI-CI Process Inquiry messages
//

import Testing
import Foundation
@testable import MIDI2Core
@testable import MIDI2CI

@Suite("Process Inquiry Tests")
struct ProcessInquiryTests {

    // MARK: - Message Builder Tests

    @Test("Build Process Inquiry Capabilities Inquiry")
    func buildCapabilitiesInquiry() {
        let sourceMUID = MUID(rawValue: 0x01234567)!
        let destMUID = MUID(rawValue: 0x07654321)!

        let message = CIMessageBuilder.processInquiryCapabilitiesInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID
        )

        // Verify SysEx framing
        #expect(message.first == 0xF0)
        #expect(message.last == 0xF7)

        // Verify MIDI-CI header
        #expect(message[1] == 0x7E)  // Universal SysEx Non-Realtime
        #expect(message[3] == 0x0D)  // MIDI-CI Sub-ID
        #expect(message[4] == 0x40)  // Process Inquiry Capabilities Inquiry
    }

    @Test("Build Process Inquiry Capabilities Reply")
    func buildCapabilitiesReply() {
        let sourceMUID = MUID(rawValue: 0x01234567)!
        let destMUID = MUID(rawValue: 0x07654321)!
        let capabilities: ProcessInquiryCapabilities = [.midiMessageReport, .defaultReport]

        let message = CIMessageBuilder.processInquiryCapabilitiesReply(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            capabilities: capabilities
        )

        #expect(message.first == 0xF0)
        #expect(message.last == 0xF7)
        #expect(message[4] == 0x41)  // Process Inquiry Capabilities Reply

        // Capabilities should be in payload
        #expect(message.contains(capabilities.rawValue))
    }

    @Test("Build MIDI Message Report Inquiry")
    func buildMidiMessageReportInquiry() {
        let sourceMUID = MUID(rawValue: 0x01234567)!
        let destMUID = MUID(rawValue: 0x07654321)!

        let request = MIDIMessageReportRequest(
            requestMIDI1: true,
            requestMIDI2: true,
            messageTypes: .all,
            requestControllerReport: true,
            requestNoteDataReport: true
        )

        let message = CIMessageBuilder.midiMessageReportInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            request: request
        )

        #expect(message.first == 0xF0)
        #expect(message.last == 0xF7)
        #expect(message[4] == 0x42)  // MIDI Message Report Inquiry
    }

    @Test("Build MIDI Message Report Reply")
    func buildMidiMessageReportReply() {
        let sourceMUID = MUID(rawValue: 0x01234567)!
        let destMUID = MUID(rawValue: 0x07654321)!

        let report = MIDIMessageReport(
            controllers: [1, 7, 10, 64],
            noteRange: 21...108,  // Piano range
            supportedTypes: [.noteOn, .noteOff, .controlChange]
        )

        let message = CIMessageBuilder.midiMessageReportReply(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            report: report
        )

        #expect(message.first == 0xF0)
        #expect(message.last == 0xF7)
        #expect(message[4] == 0x43)  // MIDI Message Report Reply
    }

    @Test("Build End of MIDI Message Report")
    func buildEndOfMidiMessageReport() {
        let sourceMUID = MUID(rawValue: 0x01234567)!
        let destMUID = MUID(rawValue: 0x07654321)!

        let message = CIMessageBuilder.endOfMidiMessageReport(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID
        )

        #expect(message.first == 0xF0)
        #expect(message.last == 0xF7)
        #expect(message[4] == 0x44)  // End of MIDI Message Report
    }

    // MARK: - Message Parser Tests

    @Test("Parse Process Inquiry Capabilities Reply")
    func parseCapabilitiesReply() {
        let sourceMUID = MUID(rawValue: 0x01234567)!
        let destMUID = MUID(rawValue: 0x07654321)!
        let capabilities: ProcessInquiryCapabilities = [.midiMessageReport]

        let message = CIMessageBuilder.processInquiryCapabilitiesReply(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            capabilities: capabilities
        )

        let parsed = CIMessageParser.parseFullProcessInquiryCapabilitiesReply(message)

        #expect(parsed != nil)
        #expect(parsed?.sourceMUID == sourceMUID)
        #expect(parsed?.destinationMUID == destMUID)
        #expect(parsed?.capabilities.contains(ProcessInquiryCapabilities.midiMessageReport) == true)
    }

    // MARK: - Capabilities Tests

    @Test("ProcessInquiryCapabilities OptionSet")
    func capabilitiesOptionSet() {
        var caps: ProcessInquiryCapabilities = []
        #expect(caps.isEmpty)

        caps.insert(.midiMessageReport)
        #expect(caps.contains(.midiMessageReport))
        #expect(!caps.contains(.defaultReport))

        caps.insert(.defaultReport)
        #expect(caps.contains(.defaultReport))

        #expect(caps.rawValue == 0x03)
    }

    @Test("MIDIMessageTypeFlags OptionSet")
    func messageTypeFlagsOptionSet() {
        let allFlags = MIDIMessageTypeFlags.all
        #expect(allFlags.contains(.noteOn))
        #expect(allFlags.contains(.noteOff))
        #expect(allFlags.contains(.controlChange))
        #expect(allFlags.contains(.pitchBend))

        let noteFlags: MIDIMessageTypeFlags = [.noteOn, .noteOff]
        #expect(noteFlags.contains(.noteOn))
        #expect(noteFlags.contains(.noteOff))
        #expect(!noteFlags.contains(.controlChange))
    }

    // MARK: - Request Tests

    @Test("MIDIMessageReportRequest defaults")
    func requestDefaults() {
        let request = MIDIMessageReportRequest()

        #expect(request.requestMIDI1 == true)
        #expect(request.requestMIDI2 == true)
        #expect(request.messageTypes == .all)
        #expect(request.requestControllerReport == true)
        #expect(request.requestNoteDataReport == true)
    }

    @Test("MIDIMessageReportRequest custom")
    func requestCustom() {
        let request = MIDIMessageReportRequest(
            requestMIDI1: true,
            requestMIDI2: false,
            messageTypes: [.noteOn, .noteOff],
            requestControllerReport: false,
            requestNoteDataReport: true
        )

        #expect(request.requestMIDI1 == true)
        #expect(request.requestMIDI2 == false)
        #expect(request.messageTypes.contains(.noteOn))
        #expect(!request.messageTypes.contains(.controlChange))
    }

    // MARK: - Report Tests

    @Test("MIDIMessageReport creation")
    func reportCreation() {
        let report = MIDIMessageReport(
            controllers: [1, 7, 10],
            noteRange: 36...96,
            supportedTypes: [.noteOn, .noteOff, .controlChange]
        )

        #expect(report.controllers.count == 3)
        #expect(report.noteRange == 36...96)
        #expect(report.supportedTypes.contains(.noteOn))
    }

    @Test("MIDIMessageReport empty")
    func reportEmpty() {
        let report = MIDIMessageReport()

        #expect(report.controllers.isEmpty)
        #expect(report.noteRange == nil)
        #expect(report.supportedTypes.isEmpty)
    }

    // MARK: - Capabilities Reply Payload Tests

    @Test("Parse Capabilities Reply payload")
    func parseCapabilitiesPayload() {
        let payload: [UInt8] = [0x03]  // Both capabilities

        let parsed = CIMessageParser.parseProcessInquiryCapabilitiesReply(payload)

        #expect(parsed != nil)
        #expect(parsed?.capabilities.contains(.midiMessageReport) == true)
        #expect(parsed?.capabilities.contains(.defaultReport) == true)
    }

    @Test("Parse Capabilities Reply payload empty fails")
    func parseCapabilitiesPayloadEmpty() {
        let payload: [UInt8] = []

        let parsed = CIMessageParser.parseProcessInquiryCapabilitiesReply(payload)
        #expect(parsed == nil)
    }

    // MARK: - Message Report Reply Payload Tests

    @Test("Parse Message Report Reply payload")
    func parseMessageReportPayload() {
        let payload: [UInt8] = [0x00, 0x00, 0x7F, 0x01]

        let parsed = CIMessageParser.parseMIDIMessageReportReply(payload)

        #expect(parsed != nil)
        #expect(parsed?.channelFlags == .all)
        #expect(parsed?.hasNoteData == true)
    }

    @Test("Parse Message Report Reply payload short fails")
    func parseMessageReportPayloadShort() {
        let payload: [UInt8] = [0x00, 0x00]

        let parsed = CIMessageParser.parseMIDIMessageReportReply(payload)
        #expect(parsed == nil)
    }

    // MARK: - Round-Trip Tests

    @Test("Capabilities Inquiry round-trip")
    func capabilitiesInquiryRoundTrip() {
        let sourceMUID = MUID(rawValue: 0x01234567)!
        let destMUID = MUID(rawValue: 0x07654321)!

        let message = CIMessageBuilder.processInquiryCapabilitiesInquiry(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID
        )

        let parsed = CIMessageParser.parse(message)

        #expect(parsed != nil)
        #expect(parsed?.sourceMUID == sourceMUID)
        #expect(parsed?.destinationMUID == destMUID)
    }

    @Test("Capabilities Reply round-trip")
    func capabilitiesReplyRoundTrip() {
        let sourceMUID = MUID(rawValue: 0x01234567)!
        let destMUID = MUID(rawValue: 0x07654321)!
        let caps: ProcessInquiryCapabilities = [.midiMessageReport, .defaultReport]

        let message = CIMessageBuilder.processInquiryCapabilitiesReply(
            sourceMUID: sourceMUID,
            destinationMUID: destMUID,
            capabilities: caps
        )

        let parsed = CIMessageParser.parseFullProcessInquiryCapabilitiesReply(message)

        #expect(parsed != nil)
        #expect(parsed?.sourceMUID == sourceMUID)
        #expect(parsed?.destinationMUID == destMUID)
        #expect(parsed?.capabilities == caps)
    }
}
