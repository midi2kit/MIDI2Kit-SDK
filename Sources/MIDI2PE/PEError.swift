//
//  PEError.swift
//  MIDI2Kit
//
//  Property Exchange error types
//

import Foundation
import MIDI2Core

// Forward declaration for validation error (defined in Validation/PEPayloadValidator.swift)
// Note: PEPayloadValidationError is defined in MIDI2PE/Validation/PEPayloadValidator.swift

// MARK: - PE Error

/// Property Exchange errors
public enum PEError: Error, Sendable {
    /// Transaction timed out
    case timeout(resource: String)

    /// Transaction was cancelled
    case cancelled

    /// Request ID exhausted (all 128 in use)
    case requestIDExhausted

    /// Device returned error status
    case deviceError(status: Int, message: String?)

    /// Device not found
    case deviceNotFound(MUID)

    /// Invalid response format
    case invalidResponse(String)

    /// Transport error
    case transportError(Error)

    /// Not connected to any destination
    case noDestination

    /// Request validation failed
    case validationFailed(PERequestError)

    /// Device returned NAK (Negative Acknowledge)
    ///
    /// Contains detailed information about why the request was rejected.
    /// Check `details.isTransient` to determine if retry might succeed.
    case nak(PENAKDetails)

    /// Payload validation failed before sending SET request
    ///
    /// This error is thrown when payload validation is enabled and the
    /// payload fails validation before being sent to the device.
    /// This prevents sending invalid data to MIDI devices.
    case payloadValidationFailed(PEPayloadValidationError)
}

// MARK: - PEError Description

extension PEError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .timeout(let resource):
            return "Timeout waiting for response: \(resource)"
        case .cancelled:
            return "Request was cancelled"
        case .requestIDExhausted:
            return "All 128 request IDs are in use"
        case .deviceError(let status, let message):
            if let msg = message {
                return "Device error (\(status)): \(msg)"
            }
            return "Device error: status \(status)"
        case .deviceNotFound(let muid):
            return "Device not found: \(muid)"
        case .invalidResponse(let reason):
            return "Invalid response: \(reason)"
        case .transportError(let error):
            return "Transport error: \(error)"
        case .noDestination:
            return "No destination configured"
        case .validationFailed(let error):
            return "Validation failed: \(error)"
        case .nak(let details):
            return details.description
        case .payloadValidationFailed(let error):
            return "Payload validation failed: \(error)"
        }
    }
}

extension PEError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

// MARK: - PEError Classification

extension PEError {
    /// Whether this error is potentially recoverable by retrying
    ///
    /// Returns `true` for:
    /// - Timeouts (network/device may have been temporarily unavailable)
    /// - Transient NAKs (device busy, too many requests)
    /// - Transport errors (temporary network issues)
    ///
    /// Returns `false` for:
    /// - Cancelled requests (intentional)
    /// - Request ID exhaustion (need to wait for completions)
    /// - Permanent NAKs (resource not found, permission denied)
    /// - Validation errors (request itself is invalid)
    /// - Device not found (need discovery first)
    public var isRetryable: Bool {
        switch self {
        case .timeout:
            return true
        case .nak(let details):
            return details.isTransient
        case .transportError:
            return true
        case .cancelled, .requestIDExhausted, .validationFailed, .deviceNotFound, .noDestination, .payloadValidationFailed:
            return false
        case .deviceError(let status, _):
            // 5xx errors are typically server-side and may be transient
            // 4xx errors are client errors and won't be fixed by retry
            return status >= 500
        case .invalidResponse:
            // Parse errors might succeed on retry if data was corrupted
            return true
        }
    }

    /// Whether this is a client-side error (invalid request, validation failure)
    public var isClientError: Bool {
        switch self {
        case .validationFailed, .noDestination, .deviceNotFound, .payloadValidationFailed:
            return true
        case .deviceError(let status, _):
            return status >= 400 && status < 500
        case .nak(let details):
            // Permission denied indicates the request itself is not allowed
            return details.detailCode == .permissionDenied
        default:
            return false
        }
    }

    /// Whether this is a device-side error (device rejected the request)
    public var isDeviceError: Bool {
        switch self {
        case .deviceError, .nak:
            return true
        default:
            return false
        }
    }

    /// Whether this is a transport/communication error
    public var isTransportError: Bool {
        switch self {
        case .timeout, .transportError:
            return true
        default:
            return false
        }
    }

    /// Suggested delay before retry (if retryable)
    ///
    /// Returns appropriate backoff based on error type:
    /// - NAK busy/tooManyRequests: 500ms (device asked us to slow down)
    /// - Timeout: 100ms (quick retry, issue may have been transient)
    /// - Transport error: 200ms (allow connection to recover)
    /// - Other retryable: 100ms
    public var suggestedRetryDelay: Duration? {
        guard isRetryable else { return nil }

        switch self {
        case .nak(let details) where details.detailCode == .busy:
            return .milliseconds(500)
        case .nak(let details) where details.detailCode == .tooManyRequests:
            return .milliseconds(1000)
        case .timeout:
            return .milliseconds(100)
        case .transportError:
            return .milliseconds(200)
        default:
            return .milliseconds(100)
        }
    }
}

// MARK: - Retry Helper

/// Execute an async operation with automatic retry on retryable errors
///
/// ## Example
/// ```swift
/// let response = try await withPERetry(maxAttempts: 3) {
///     try await peManager.get("DeviceInfo", from: device)
/// }
/// ```
///
/// - Parameters:
///   - maxAttempts: Maximum number of attempts (default: 3)
///   - operation: The async throwing operation to execute
/// - Returns: The result of a successful operation
/// - Throws: The last error if all attempts fail
public func withPERetry<T>(
    maxAttempts: Int = 3,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch let error as PEError {
            lastError = error

            // Don't retry if error is not retryable or we're out of attempts
            guard error.isRetryable, attempt < maxAttempts else {
                throw error
            }

            // Wait before retry using suggested delay
            if let delay = error.suggestedRetryDelay {
                try? await Task.sleep(for: delay)
            }
        } catch {
            // Non-PEError - don't retry
            throw error
        }
    }

    throw lastError ?? PEError.cancelled
}
