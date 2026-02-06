//
//  MIDITransportType.swift
//  MIDI2Kit
//
//  Transport type detection for MIDI connections
//

import Foundation

// MARK: - MIDITransportType

/// Transport type for a MIDI connection
///
/// Used to automatically adjust timeouts and behavior based on the
/// physical transport layer. BLE MIDI connections typically need
/// longer timeouts due to the wireless nature of the connection.
public enum MIDITransportType: String, Sendable, CaseIterable {
    /// USB MIDI connection
    case usb

    /// Bluetooth Low Energy MIDI connection
    case ble

    /// Network MIDI (RTP-MIDI, etc.)
    case network

    /// Virtual MIDI port (software-to-software)
    case virtual

    /// Unknown transport type
    case unknown
}

#if canImport(CoreMIDI)
import CoreMIDI
import MIDI2Core

// MARK: - Transport Type Detection

extension MIDITransportType {

    /// Detect transport type for a CoreMIDI endpoint
    ///
    /// Uses a combination of driver owner name and endpoint name heuristics:
    /// 1. Check `kMIDIPropertyDriverOwner` for known driver names
    /// 2. Check endpoint display name for known patterns
    ///
    /// - Parameter endpoint: CoreMIDI endpoint reference
    /// - Returns: Detected transport type
    public static func detect(for endpoint: MIDIEndpointRef) -> MIDITransportType {
        // Check driver owner
        if let driverOwner = getStringProperty(endpoint, kMIDIPropertyDriverOwner) {
            let lower = driverOwner.lowercased()

            if lower.contains("bluetooth") || lower.contains("ble") {
                return .ble
            }
            if lower.contains("usb") {
                return .usb
            }
            if lower.contains("network") || lower.contains("session") || lower.contains("rtp") {
                return .network
            }
            if lower.contains("iac") || lower.contains("virtual") {
                return .virtual
            }
        }

        // Check endpoint name
        if let name = getStringProperty(endpoint, kMIDIPropertyDisplayName)
            ?? getStringProperty(endpoint, kMIDIPropertyName) {
            let lower = name.lowercased()

            if lower.contains("bluetooth") || lower.contains("ble") {
                return .ble
            }
            // KORG Module Pro via BLE typically shows as "Session 1" or similar
            if lower.contains("session") {
                return .ble
            }
            if lower.contains("network") {
                return .network
            }
            if lower.contains("iac") {
                return .virtual
            }
        }

        return .unknown
    }

    /// Get a string property from a CoreMIDI object
    private static func getStringProperty(_ endpoint: MIDIEndpointRef, _ property: CFString) -> String? {
        var unmanagedString: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, property, &unmanagedString)
        guard status == noErr, let cfString = unmanagedString?.takeRetainedValue() else {
            return nil
        }
        return cfString as String
    }
}
#endif
