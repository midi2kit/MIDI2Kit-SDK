//
//  VirtualEndpointCapable.swift
//  MIDI2Kit
//
//  Virtual MIDI endpoint support for inter-app communication
//

import Foundation

/// Represents a published virtual MIDI device (source + destination pair)
///
/// Other apps see `sourceID` as a MIDI source they can read from,
/// and `destinationID` as a MIDI destination they can send to.
///
/// ```
/// Your App                    Other Apps (DAW, etc.)
/// ┌──────────┐               ┌──────────┐
/// │ Virtual   │──sourceID───▶│ receives │
/// │ Device    │              │          │
/// │           │◀──destID─────│  sends   │
/// └──────────┘               └──────────┘
/// ```
public struct VirtualDevice: Sendable, Hashable {
    /// Display name of this virtual device
    public let name: String

    /// Other apps send MIDI data to this destination.
    /// Your app receives from the `received` stream.
    public let destinationID: MIDIDestinationID

    /// Other apps receive MIDI data from this source.
    /// Your app sends via `sendFromVirtualSource(_:source:)`.
    public let sourceID: MIDISourceID

    public init(name: String, destinationID: MIDIDestinationID, sourceID: MIDISourceID) {
        self.name = name
        self.destinationID = destinationID
        self.sourceID = sourceID
    }
}

/// Protocol for transports that can create virtual MIDI endpoints
///
/// Virtual endpoints allow your app to appear as a MIDI device to other apps.
/// This is essential for:
/// - PE Responder mode (answering Property Exchange queries from DAWs)
/// - Inter-app MIDI communication
/// - MIDI routing between apps
///
/// ## Design
///
/// This is a **separate protocol** from `MIDITransport` to maintain
/// backwards compatibility. Not all transports need virtual endpoint support
/// (e.g., `LoopbackTransport` is purely for testing).
///
/// ## Usage
///
/// ```swift
/// let transport = try CoreMIDITransport()
/// let device = try await transport.publishVirtualDevice(name: "My App")
///
/// // Other apps can now see "My App" as a MIDI device
///
/// // Send data to other apps
/// try await transport.sendFromVirtualSource([0x90, 60, 127], source: device.sourceID)
///
/// // Receive data from other apps via the standard received stream
/// for await data in transport.received {
///     // data from both physical and virtual sources
/// }
///
/// // Cleanup
/// try await transport.unpublishVirtualDevice(device)
/// ```
public protocol VirtualEndpointCapable: MIDITransport {
    /// Create a virtual destination that other apps can send MIDI data to.
    ///
    /// Data received on this destination is delivered through the transport's
    /// `received` stream, just like physical MIDI data.
    ///
    /// - Parameter name: Display name visible to other apps
    /// - Returns: The created destination's ID
    /// - Throws: `MIDITransportError.virtualEndpointCreationFailed` if CoreMIDI API fails
    func createVirtualDestination(name: String) async throws -> MIDIDestinationID

    /// Create a virtual source that other apps can receive MIDI data from.
    ///
    /// Use `sendFromVirtualSource(_:source:)` to emit data from this source.
    ///
    /// - Parameter name: Display name visible to other apps
    /// - Returns: The created source's ID
    /// - Throws: `MIDITransportError.virtualEndpointCreationFailed` if CoreMIDI API fails
    func createVirtualSource(name: String) async throws -> MIDISourceID

    /// Remove a previously created virtual destination.
    ///
    /// - Parameter id: The destination to remove
    /// - Throws: `MIDITransportError.virtualEndpointNotFound` if the ID was not created by this transport
    func removeVirtualDestination(_ id: MIDIDestinationID) async throws

    /// Remove a previously created virtual source.
    ///
    /// - Parameter id: The source to remove
    /// - Throws: `MIDITransportError.virtualEndpointNotFound` if the ID was not created by this transport
    func removeVirtualSource(_ id: MIDISourceID) async throws

    /// Send data from a virtual source to all connected apps.
    ///
    /// This uses `MIDIReceived()` (not `MIDISend()`) because the data originates
    /// from a virtual source endpoint, not from an output port.
    ///
    /// - Parameters:
    ///   - data: MIDI bytes to send
    ///   - source: The virtual source to send from (must have been created by this transport)
    /// - Throws: `MIDITransportError.virtualEndpointNotFound` if the source was not created by this transport
    func sendFromVirtualSource(_ data: [UInt8], source: MIDISourceID) async throws
}

// MARK: - Convenience API

public extension VirtualEndpointCapable {
    /// Publish a virtual device with both a source and a destination.
    ///
    /// This creates a paired source+destination that appears as a single device
    /// to other apps. If creating the source fails after the destination was
    /// already created, the destination is automatically cleaned up.
    ///
    /// - Parameter name: Display name visible to other apps
    /// - Returns: A `VirtualDevice` containing both endpoint IDs
    /// - Throws: `MIDITransportError.virtualEndpointCreationFailed` if creation fails
    func publishVirtualDevice(name: String) async throws -> VirtualDevice {
        let destinationID = try await createVirtualDestination(name: name)

        do {
            let sourceID = try await createVirtualSource(name: name)
            return VirtualDevice(name: name, destinationID: destinationID, sourceID: sourceID)
        } catch {
            // Rollback: remove the destination that was already created
            try? await removeVirtualDestination(destinationID)
            throw error
        }
    }

    /// Unpublish a virtual device, removing both its source and destination.
    ///
    /// This is the inverse of `publishVirtualDevice(name:)`. Both endpoints
    /// are removed regardless of individual failures.
    ///
    /// - Parameter device: The virtual device to remove
    /// - Throws: The first error encountered during removal
    func unpublishVirtualDevice(_ device: VirtualDevice) async throws {
        var firstError: Error?

        do {
            try await removeVirtualDestination(device.destinationID)
        } catch {
            firstError = error
        }

        do {
            try await removeVirtualSource(device.sourceID)
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        if let error = firstError {
            throw error
        }
    }
}
