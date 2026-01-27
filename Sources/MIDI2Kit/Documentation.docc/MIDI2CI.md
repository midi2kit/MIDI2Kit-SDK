# MIDI2CI

MIDI-CI device discovery and capability inquiry.

## Overview

MIDI2CI implements the MIDI Capability Inquiry protocol for device discovery and capability negotiation. The main entry point is ``CIManager``, which handles:

- Automatic device discovery via periodic Discovery Inquiry broadcasts
- Device lifecycle management (discovery, timeout, invalidation)
- Capability negotiation and feature detection

## Topics

### Device Discovery

- ``CIManager``
- ``CIManagerConfiguration``
- ``CIManagerEvent``

### Discovered Devices

- ``DiscoveredDevice``
- ``CategorySupport``

### Messages

- ``CIMessageBuilder``
- ``CIMessageParser``
