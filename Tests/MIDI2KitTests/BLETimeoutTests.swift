//
//  BLETimeoutTests.swift
//  MIDI2Kit
//
//  Tests for BLE MIDI timeout optimization and MIDITransportType
//

import Testing
import Foundation
@testable import MIDI2Transport
@testable import MIDI2Kit

// MARK: - MIDITransportType Tests

@Suite("MIDITransportType Tests")
struct MIDITransportTypeTests {

    @Test("All cases are defined")
    func allCases() {
        let cases = MIDITransportType.allCases
        #expect(cases.count == 5)
        #expect(cases.contains(.usb))
        #expect(cases.contains(.ble))
        #expect(cases.contains(.network))
        #expect(cases.contains(.virtual))
        #expect(cases.contains(.unknown))
    }

    @Test("Raw values are correct")
    func rawValues() {
        #expect(MIDITransportType.usb.rawValue == "usb")
        #expect(MIDITransportType.ble.rawValue == "ble")
        #expect(MIDITransportType.network.rawValue == "network")
        #expect(MIDITransportType.virtual.rawValue == "virtual")
        #expect(MIDITransportType.unknown.rawValue == "unknown")
    }

    @Test("MIDITransportType is Sendable")
    func sendable() {
        let type: MIDITransportType = .ble
        let _: any Sendable = type
        #expect(type == .ble)
    }
}

// MARK: - MIDI2ClientConfiguration BLE Settings Tests

@Suite("MIDI2ClientConfiguration BLE Settings Tests")
struct MIDI2ClientConfigurationBLETests {

    @Test("Default configuration has BLE timeout enabled")
    func defaultBLESettings() {
        let config = MIDI2ClientConfiguration()
        #expect(config.autoAdjustBLETimeout == true)
        #expect(config.blePETimeout == .seconds(15))
    }

    @Test("BLE timeout can be customized")
    func customBLESettings() {
        var config = MIDI2ClientConfiguration()
        config.autoAdjustBLETimeout = false
        config.blePETimeout = .seconds(20)

        #expect(config.autoAdjustBLETimeout == false)
        #expect(config.blePETimeout == .seconds(20))
    }

    @Test("Explorer preset has BLE timeout enabled")
    func explorerPreset() {
        let config = MIDI2ClientConfiguration(preset: .explorer)
        #expect(config.autoAdjustBLETimeout == true)
        #expect(config.blePETimeout == .seconds(15))
    }

    @Test("Minimal preset has BLE timeout enabled")
    func minimalPreset() {
        let config = MIDI2ClientConfiguration(preset: .minimal)
        #expect(config.autoAdjustBLETimeout == true)
    }
}
