# ``MIDI2Core``

Foundation types for MIDI 2.0: identifiers, encoding, UMP messages, and diagnostics.

@Metadata {
    @DisplayName("MIDI2Core")
}

## Overview

MIDI2Core provides the shared data types and utilities used across all MIDI2Kit modules. It has no external dependencies and is the foundation of the module hierarchy.

All types conform to `Sendable` for Swift 6 strict concurrency safety.

### Key Capabilities

- **Identifiers**: ``MUID`` (28-bit MIDI Unique Identifier), ``ManufacturerID``, ``DeviceIdentity``
- **Encoding**: ``Mcoded7`` for 8-bit to 7-bit SysEx encoding
- **UMP**: ``UMPBuilder``, ``UMPParser``, ``UMPTranslator`` for MIDI 2.0 Universal MIDI Packet operations
- **Constants**: ``CIMessageType``, ``CategorySupport``, status codes
- **Diagnostics**: ``MIDITracer`` for real-time message tracing
- **Logging**: ``MIDI2Logger`` protocol with built-in implementations

## Topics

### Identifiers

- ``MUID``
- ``ManufacturerID``
- ``DeviceIdentity``

### Encoding

- ``Mcoded7``
- ``ZlibMcoded7``

### UMP (Universal MIDI Packet)

- <doc:UMPConversion>
- ``UMPBuilder``
- ``UMPParser``
- ``UMPTranslator``
- ``UMPSysEx7Assembler``
- ``UMPValueScaling``

### UMP Message Types

- ``UMPMessage``
- ``UMPMessageType``
- ``UMPMIDI2ChannelVoice``
- ``UMPMIDI1ChannelVoice``
- ``UMPFlexData``
- ``UMPSystemRealTime``
- ``UMPSystemCommon``
- ``UMPUtility``
- ``UMP``

### UMP Parsed Messages

- ``ParsedUMPMessage``
- ``ParsedMIDI2ChannelVoice``
- ``ParsedMIDI1ChannelVoice``

### UMP Supporting Types

- ``UMPGroup``
- ``MIDIChannel``
- ``UMPChannel``
- ``MIDI2ChannelVoiceStatus``
- ``MIDI1ChannelVoiceStatus``
- ``SysEx7Status``
- ``PitchBendValue``
- ``ProgramBank``
- ``ControllerAddress``
- ``RegisteredController``
- ``NoteAttributeType``

### Flex Data

- ``FlexDataFormat``
- ``FlexDataTempo``
- ``FlexDataTimeSignature``
- ``FlexDataKeySignature``
- ``FlexDataChordName``
- ``FlexDataChordType``
- ``FlexDataChordAlteration``

### Constants

- ``CIMessageType``
- ``CategorySupport``
- ``MIDICIConstants``
- ``MIDIDirection``

### Diagnostics

- ``MIDITracer``
- ``MIDITraceEntry``

### Logging

- ``MIDI2Logger``
- ``MIDI2LogLevel``
- ``NullMIDI2Logger``
- ``StdoutMIDI2Logger``
- ``OSLogMIDI2Logger``
- ``FileMIDI2Logger``
- ``CompositeMIDI2Logger``

### JSON Utilities

- ``AnyCodableValue``
- ``RobustJSONDecoder``
