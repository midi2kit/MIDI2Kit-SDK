//
//  MIDI2ClientEvent.swift
//  MIDI2Kit
//
//  High-level client events for MIDI 2.0 device discovery and communication
//

import Foundation
import MIDI2Core
import MIDI2CI
import MIDI2PE

// MARK: - MIDI2ClientEvent

/// Events emitted by MIDI2Client
///
/// These events provide a unified view of MIDI-CI device lifecycle
/// and Property Exchange notifications.
///
/// ## Example
///
/// ```swift
/// for await event in client.makeEventStream() {
///     switch event {
///     case .deviceDiscovered(let device):
///         print("Found: \(device.displayName)")
///     case .deviceLost(let muid):
///         print("Lost: \(muid)")
///     case .notification(let notification):
///         print("PE notification: \(notification.resource)")
///     default:
///         break
///     }
/// }
/// ```
public enum MIDI2ClientEvent: Sendable {
    
    // MARK: - Device Lifecycle
    
    /// A new MIDI-CI device was discovered
    case deviceDiscovered(MIDI2Device)
    
    /// A device was lost (timeout or explicit invalidation)
    case deviceLost(MUID)
    
    /// A device's information was updated
    case deviceUpdated(MIDI2Device)
    
    // MARK: - Discovery State
    
    /// Discovery process has started
    case discoveryStarted
    
    /// Discovery process has stopped
    case discoveryStopped
    
    // MARK: - Property Exchange
    
    /// Property Exchange notification received
    case notification(PENotification)
    
    // MARK: - Client State
    
    /// Client has started
    case started
    
    /// Client has stopped
    case stopped
    
    /// An error occurred
    case error(MIDI2Error)
}

// MARK: - CustomStringConvertible

extension MIDI2ClientEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .deviceDiscovered(let device):
            return "deviceDiscovered(\(device.displayName))"
        case .deviceLost(let muid):
            return "deviceLost(\(muid))"
        case .deviceUpdated(let device):
            return "deviceUpdated(\(device.displayName))"
        case .discoveryStarted:
            return "discoveryStarted"
        case .discoveryStopped:
            return "discoveryStopped"
        case .notification(let notification):
            return "notification(\(notification.resource))"
        case .started:
            return "started"
        case .stopped:
            return "stopped"
        case .error(let error):
            return "error(\(error))"
        }
    }
}

// MARK: - Type-Safe Event Extraction

extension MIDI2ClientEvent {

    /// Extract discovered device if this is a `.deviceDiscovered` event
    public var discoveredDevice: MIDI2Device? {
        if case .deviceDiscovered(let device) = self { return device }
        return nil
    }

    /// Extract lost device MUID if this is a `.deviceLost` event
    public var lostDeviceMUID: MUID? {
        if case .deviceLost(let muid) = self { return muid }
        return nil
    }

    /// Extract updated device if this is a `.deviceUpdated` event
    public var updatedDevice: MIDI2Device? {
        if case .deviceUpdated(let device) = self { return device }
        return nil
    }

    /// Extract notification if this is a `.notification` event
    public var peNotification: PENotification? {
        if case .notification(let notification) = self { return notification }
        return nil
    }

    /// Extract error if this is an `.error` event
    public var clientError: MIDI2Error? {
        if case .error(let error) = self { return error }
        return nil
    }

    /// Check if this is a device lifecycle event
    public var isDeviceLifecycleEvent: Bool {
        switch self {
        case .deviceDiscovered, .deviceLost, .deviceUpdated:
            return true
        default:
            return false
        }
    }

    /// Check if this is a client state event
    public var isClientStateEvent: Bool {
        switch self {
        case .started, .stopped, .discoveryStarted, .discoveryStopped:
            return true
        default:
            return false
        }
    }
}

// MARK: - AsyncStream Filtering Extensions

extension AsyncStream where Element == MIDI2ClientEvent {

    /// Filter to only device discovered events
    ///
    /// ## Example
    ///
    /// ```swift
    /// for await device in client.makeEventStream().deviceDiscovered() {
    ///     print("Found: \(device.displayName)")
    /// }
    /// ```
    public func deviceDiscovered() -> AsyncCompactMapSequence<Self, MIDI2Device> {
        compactMap(\.discoveredDevice)
    }

    /// Filter to only device lost events
    public func deviceLost() -> AsyncCompactMapSequence<Self, MUID> {
        compactMap(\.lostDeviceMUID)
    }

    /// Filter to only device updated events
    public func deviceUpdated() -> AsyncCompactMapSequence<Self, MIDI2Device> {
        compactMap(\.updatedDevice)
    }

    /// Filter to only PE notification events
    public func notifications() -> AsyncCompactMapSequence<Self, PENotification> {
        compactMap(\.peNotification)
    }

    /// Filter to only error events
    public func errors() -> AsyncCompactMapSequence<Self, MIDI2Error> {
        compactMap(\.clientError)
    }

    /// Filter to device lifecycle events only
    public func deviceLifecycle() -> AsyncFilterSequence<Self> {
        filter(\.isDeviceLifecycleEvent)
    }

    /// Filter to client state events only
    public func clientState() -> AsyncFilterSequence<Self> {
        filter(\.isClientStateEvent)
    }
}
