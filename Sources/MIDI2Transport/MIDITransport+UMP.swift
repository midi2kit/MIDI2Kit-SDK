//
//  MIDITransport+UMP.swift
//  MIDI2Kit
//
//  Transport extension for sending type-safe UMP messages
//

import Foundation
import MIDI2Core

// MARK: - MIDITransport UMP Extension

extension MIDITransport {
    
    /// Send a UMP message to a destination
    ///
    /// ## Example
    ///
    /// ```swift
    /// // MIDI 2.0 Note On (high resolution velocity)
    /// try await transport.send(
    ///     UMP.noteOn(channel: 0, note: 60, velocity: 0x8000),
    ///     to: destination
    /// )
    ///
    /// // MIDI 1.0 Control Change
    /// try await transport.send(
    ///     UMP.midi1.volume(channel: 0, value: 100),
    ///     to: destination
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - message: UMP message to send
    ///   - destination: Target MIDI destination
    public func send(_ message: some UMPMessage, to destination: MIDIDestinationID) async throws {
        try await send(message.toBytes(), to: destination)
    }
    
    /// Send multiple UMP messages to a destination
    ///
    /// - Parameters:
    ///   - messages: Array of UMP messages
    ///   - destination: Target MIDI destination
    public func send(_ messages: [any UMPMessage], to destination: MIDIDestinationID) async throws {
        for message in messages {
            try await send(message.toBytes(), to: destination)
        }
    }
}

// MARK: - Convenience Methods

extension MIDITransport {
    
    /// Send a MIDI 2.0 Note On
    public func sendNoteOn(
        group: UMPGroup = 0,
        channel: UMPChannel,
        note: UInt8,
        velocity: UInt16,
        to destination: MIDIDestinationID
    ) async throws {
        try await send(UMP.noteOn(group: group, channel: channel, note: note, velocity: velocity), to: destination)
    }
    
    /// Send a MIDI 2.0 Note Off
    public func sendNoteOff(
        group: UMPGroup = 0,
        channel: UMPChannel,
        note: UInt8,
        velocity: UInt16 = 0,
        to destination: MIDIDestinationID
    ) async throws {
        try await send(UMP.noteOff(group: group, channel: channel, note: note, velocity: velocity), to: destination)
    }
    
    /// Send a MIDI 2.0 Control Change (32-bit resolution)
    public func sendControlChange(
        group: UMPGroup = 0,
        channel: UMPChannel,
        controller: UInt8,
        value: UInt32,
        to destination: MIDIDestinationID
    ) async throws {
        try await send(UMP.controlChange(group: group, channel: channel, controller: controller, value: value), to: destination)
    }
    
    /// Send a MIDI 2.0 Program Change
    public func sendProgramChange(
        group: UMPGroup = 0,
        channel: UMPChannel,
        program: UInt8,
        bankMSB: UInt8? = nil,
        bankLSB: UInt8? = nil,
        to destination: MIDIDestinationID
    ) async throws {
        try await send(UMP.programChange(group: group, channel: channel, program: program, bankMSB: bankMSB, bankLSB: bankLSB), to: destination)
    }
    
    /// Send a MIDI 2.0 Pitch Bend (32-bit resolution)
    public func sendPitchBend(
        group: UMPGroup = 0,
        channel: UMPChannel,
        value: UInt32,
        to destination: MIDIDestinationID
    ) async throws {
        try await send(UMP.pitchBend(group: group, channel: channel, value: value), to: destination)
    }
    
    /// Send All Notes Off on a channel
    public func sendAllNotesOff(
        group: UMPGroup = 0,
        channel: UMPChannel,
        to destination: MIDIDestinationID
    ) async throws {
        try await send(UMP.midi1.allNotesOff(group: group, channel: channel), to: destination)
    }
    
    /// Send All Sound Off on a channel
    public func sendAllSoundOff(
        group: UMPGroup = 0,
        channel: UMPChannel,
        to destination: MIDIDestinationID
    ) async throws {
        try await send(UMP.midi1.allSoundOff(group: group, channel: channel), to: destination)
    }
}
