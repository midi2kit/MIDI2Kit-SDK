# MIDI2Core

Foundation types and utilities for MIDI 2.0.

## Overview

MIDI2Core provides the fundamental types used throughout MIDI2Kit:

- UMP message types and status codes
- MUID for device identification
- DeviceIdentity for manufacturer/model info
- Value scaling utilities for MIDI 1.0 ↔ 2.0 conversion
- Mcoded7 encoding for 8-bit data over 7-bit MIDI

## Topics

### UMP Types

- ``UMPMessageType``
- ``MIDI2ChannelVoiceStatus``
- ``UMPGroup``
- ``MIDIChannel``

### Identification

- ``MUID``
- ``DeviceIdentity``
- ``ManufacturerID``

### Value Conversion

- ``UMPValueScaling``

### Encoding

- ``Mcoded7``
