//
//  MIDI2Core.swift
//  MIDI2Kit
//
//  Core types and utilities for MIDI 2.0
//

/// # MIDI2Core
///
/// Foundation types used throughout MIDI2Kit.
///
/// ## Overview
///
/// MIDI2Core provides the fundamental types and utilities for working with MIDI 2.0:
///
/// - **MUID**: 28-bit MIDI Unique Identifier for device identification
/// - **DeviceIdentity**: Manufacturer, family, model, and version information
/// - **UMP Messages**: Type-safe Universal MIDI Packet construction
/// - **Mcoded7**: 8-bit to 7-bit encoding for SysEx transmission
/// - **Logging**: Configurable logging system for debugging
///
/// ## MUID (MIDI Unique Identifier)
///
/// ```swift
/// // Generate random MUID
/// let muid = MUID.random()
///
/// // Special MUIDs
/// let broadcast = MUID.broadcast  // 0x0FFFFFFF - targets all devices
/// let reserved = MUID.reserved    // 0x00000000 - invalid
///
/// // Convert to/from bytes for SysEx
/// let bytes = muid.bytes  // [UInt8] - 4 bytes, 7-bit each
/// let restored = MUID(bytes: (bytes[0], bytes[1], bytes[2], bytes[3]))
/// ```
///
/// ## UMP Messages
///
/// ```swift
/// // MIDI 2.0 high-resolution messages
/// let noteOn = UMP.noteOn(channel: 0, note: 60, velocity: 0x8000)
/// let cc = UMP.controlChange(channel: 0, controller: 74, value: 0x80000000)
///
/// // MIDI 1.0 compatible messages
/// let noteOn1 = UMP.midi1.noteOn(channel: 0, note: 60, velocity: 100)
/// let volume = UMP.midi1.volume(channel: 0, value: 100)
///
/// // Send via transport
/// try await transport.send(noteOn, to: destination)
/// ```
///
/// ## Mcoded7 Encoding
///
/// ```swift
/// // Encode 8-bit data for SysEx transmission
/// let encoded = Mcoded7.encode(binaryData)
///
/// // Decode received data
/// if let decoded = Mcoded7.decode(sysexData) {
///     // Process original binary data
/// }
/// ```
///
/// ## Logging
///
/// ```swift
/// // Development: verbose logging
/// let logger = StdoutMIDI2Logger(minLevel: .debug)
///
/// // Production: Apple's os.log
/// let logger = OSLogMIDI2Logger(
///     subsystem: "com.myapp.midi",
///     minLevel: .warning
/// )
///
/// // Use with managers
/// let transactionManager = PETransactionManager(logger: logger)
/// ```
///
/// ## Topics
///
/// ### Identifiers
/// - ``MUID``
/// - ``ManufacturerID``
/// - ``DeviceIdentity``
///
/// ### UMP Messages
/// - ``UMP``
/// - ``UMPMessage``
/// - ``UMPMessageType``
/// - ``UMPMIDI2ChannelVoice``
/// - ``UMPMIDI1ChannelVoice``
/// - ``UMPSystemRealTime``
/// - ``UMPSystemCommon``
///
/// ### Encoding
/// - ``Mcoded7``
///
/// ### Protocol Constants
/// - ``MIDICIConstants``
/// - ``CIMessageType``
/// - ``CategorySupport``
///
/// ### Logging
/// - ``MIDI2Logger``
/// - ``MIDI2LogLevel``
/// - ``StdoutMIDI2Logger``
/// - ``OSLogMIDI2Logger``

// Re-export all public types
// Each file in this module defines public types directly
