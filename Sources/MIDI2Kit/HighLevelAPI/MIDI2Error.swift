//
//  MIDI2Error.swift
//  MIDI2Kit
//
//  High-level error types for MIDI2Client
//

import Foundation
import MIDI2Core
import MIDI2PE

// MARK: - MIDI2Error

/// Errors from MIDI2Client operations
///
/// These errors wrap lower-level PE and transport errors into
/// user-friendly categories with recovery suggestions.
public enum MIDI2Error: Error, Sendable {
    
    /// Device did not respond within the timeout period
    ///
    /// This typically indicates:
    /// - Device is offline or disconnected
    /// - Wrong destination port being used
    /// - Device is busy and cannot respond
    case deviceNotResponding(muid: MUID, timeout: Duration)
    
    /// The requested property/resource is not supported by the device
    ///
    /// Check `ResourceList` to see available resources.
    case propertyNotSupported(resource: String)
    
    /// Communication with the device failed
    ///
    /// The underlying error contains more details.
    case communicationFailed(underlying: Error)
    
    /// Device was not found in the discovered devices list
    ///
    /// The device may have been lost or the MUID may be incorrect.
    case deviceNotFound(muid: MUID)
    
    /// Client is not running
    ///
    /// Call `start()` before performing operations.
    case clientNotRunning
    
    /// Operation was cancelled
    ///
    /// The operation was cancelled, typically due to `stop()` being called.
    case cancelled
    
    /// Transport initialization failed
    case transportError(Error)
    
    /// Invalid configuration
    case invalidConfiguration(String)
}

// MARK: - CustomStringConvertible

extension MIDI2Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .deviceNotResponding(let muid, let timeout):
            return "Device \(muid) did not respond within \(timeout)"
        case .propertyNotSupported(let resource):
            return "Property '\(resource)' is not supported by the device"
        case .communicationFailed(let underlying):
            return "Communication failed: \(underlying)"
        case .deviceNotFound(let muid):
            return "Device \(muid) not found"
        case .clientNotRunning:
            return "Client is not running. Call start() first."
        case .cancelled:
            return "Operation was cancelled"
        case .transportError(let error):
            return "Transport error: \(error)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}

// MARK: - LocalizedError

extension MIDI2Error: LocalizedError {
    public var errorDescription: String? {
        description
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .deviceNotResponding:
            return "Check that the device is connected and powered on. Try increasing the timeout or verifying the MIDI connection."
        case .propertyNotSupported:
            return "Use getResourceList() to see which properties are available on this device."
        case .communicationFailed:
            return "Check the MIDI connection and try again. The device may need to be reconnected."
        case .deviceNotFound:
            return "Wait for device discovery or check that the device is connected."
        case .clientNotRunning:
            return "Call start() on the MIDI2Client before performing this operation."
        case .cancelled:
            return "The operation was cancelled. Retry if needed."
        case .transportError:
            return "Check that no other application is using the MIDI ports."
        case .invalidConfiguration:
            return "Review the configuration parameters."
        }
    }
}

// MARK: - PEError Conversion

extension MIDI2Error {
    /// Create from a PEError
    public init(from peError: PEError, muid: MUID? = nil) {
        switch peError {
        case .timeout(let resource):
            if let muid {
                self = .deviceNotResponding(muid: muid, timeout: .seconds(5))
            } else {
                self = .communicationFailed(underlying: peError)
            }
        case .cancelled:
            self = .cancelled
        case .deviceNotFound(let foundMUID):
            self = .deviceNotFound(muid: foundMUID)
        case .deviceError(let status, _) where status == 404:
            self = .propertyNotSupported(resource: "unknown")
        default:
            self = .communicationFailed(underlying: peError)
        }
    }
}
