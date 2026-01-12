//
//  MIDI2Kit.swift
//  MIDI2Kit
//
//  A comprehensive Swift library for MIDI 2.0, MIDI-CI, and Property Exchange
//

/// # MIDI2Kit
///
/// A modern Swift library for MIDI 2.0, MIDI-CI (Capability Inquiry), and Property Exchange.
///
/// ## Overview
///
/// MIDI2Kit provides a complete implementation of the MIDI 2.0 specification, including:
///
/// - **MIDI2Core**: Foundation types (MUID, DeviceIdentity, UMP messages, Mcoded7 encoding)
/// - **MIDI2CI**: Capability Inquiry protocol (Discovery, Protocol Negotiation, Profiles)
/// - **MIDI2PE**: Property Exchange (Get/Set resources, Subscriptions, Pagination)
/// - **MIDI2Transport**: CoreMIDI integration with connection management
///
/// ## Quick Start
///
/// ```swift
/// import MIDI2Kit
///
/// // Create transport and connect
/// let transport = try CoreMIDITransport(clientName: "MyApp")
/// try await transport.connectToAllSources()
///
/// // Start device discovery
/// let ciManager = CIManager(transport: transport)
/// try await ciManager.start()
///
/// // Listen for devices
/// for await event in ciManager.events {
///     switch event {
///     case .deviceDiscovered(let device):
///         print("Found: \(device.displayName)")
///     case .deviceLost(let muid):
///         print("Lost: \(muid)")
///     default:
///         break
///     }
/// }
/// ```
///
/// ## Architecture
///
/// MIDI2Kit is designed with Swift 6 concurrency in mind:
/// - All manager types are `actor`s for thread safety
/// - Data types are `Sendable` for safe cross-context use
/// - Async/await APIs throughout
///
/// ## Module Structure
///
/// | Module | Purpose |
/// |--------|---------|
/// | `MIDI2Core` | Foundation types, UMP messages, constants |
/// | `MIDI2CI` | Device discovery, capability inquiry |
/// | `MIDI2PE` | Property Exchange requests/subscriptions |
/// | `MIDI2Transport` | CoreMIDI abstraction layer |
///
/// ## Requirements
///
/// - iOS 17.0+ / macOS 14.0+
/// - Swift 6.0+
/// - Xcode 16.0+
///
/// ## Topics
///
/// ### Getting Started
/// - ``CoreMIDITransport``
/// - ``CIManager``
/// - ``PEManager``
///
/// ### Device Discovery
/// - ``DiscoveredDevice``
/// - ``CIManagerEvent``
/// - ``MUID``
///
/// ### Property Exchange
/// - ``PEDeviceHandle``
/// - ``PERequest``
/// - ``PEResponse``
///
/// ### UMP Messages
/// - ``UMP``
/// - ``UMPMessage``
/// - ``UMPMIDI2ChannelVoice``
/// - ``UMPMIDI1ChannelVoice``

@_exported import MIDI2Core
@_exported import MIDI2CI
@_exported import MIDI2PE
@_exported import MIDI2Transport
