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
