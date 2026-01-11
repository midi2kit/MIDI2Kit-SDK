//
//  PEBatchRequest.swift
//  MIDI2Kit
//
//  Batch request types for parallel PE operations
//

import Foundation
import MIDI2Core

// MARK: - Batch Result

/// Result of a single request within a batch operation
public enum PEBatchResult: Sendable {
    /// Request succeeded
    case success(PEResponse)
    
    /// Request failed
    case failure(Error)
    
    /// Get response if successful
    public var response: PEResponse? {
        if case .success(let response) = self {
            return response
        }
        return nil
    }
    
    /// Get error if failed
    public var error: Error? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
    
    /// Whether this result is successful
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - Batch Response

/// Response from a batch GET operation
public struct PEBatchResponse: Sendable {
    /// Results keyed by resource name
    public let results: [String: PEBatchResult]
    
    /// All successful responses
    public var successes: [String: PEResponse] {
        results.compactMapValues { $0.response }
    }
    
    /// All failures
    public var failures: [String: Error] {
        results.compactMapValues { $0.error }
    }
    
    /// Whether all requests succeeded
    public var allSucceeded: Bool {
        failures.isEmpty
    }
    
    /// Number of successful requests
    public var successCount: Int {
        successes.count
    }
    
    /// Number of failed requests
    public var failureCount: Int {
        failures.count
    }
    
    /// Get result for a specific resource
    public subscript(resource: String) -> PEBatchResult? {
        results[resource]
    }
}

// MARK: - Batch Options

/// Options for batch requests
public struct PEBatchOptions: Sendable {
    /// Maximum concurrent requests (default: 4)
    public var maxConcurrency: Int
    
    /// Whether to continue on individual failures (default: true)
    public var continueOnFailure: Bool
    
    /// Timeout per request (default: 5 seconds)
    public var timeout: Duration
    
    public init(
        maxConcurrency: Int = 4,
        continueOnFailure: Bool = true,
        timeout: Duration = .seconds(5)
    ) {
        self.maxConcurrency = max(1, maxConcurrency)
        self.continueOnFailure = continueOnFailure
        self.timeout = timeout
    }
    
    /// Default options
    public static let `default` = PEBatchOptions()
    
    /// Serial execution (one at a time)
    public static let serial = PEBatchOptions(maxConcurrency: 1)
    
    /// Fast parallel execution
    public static let fast = PEBatchOptions(maxConcurrency: 8, timeout: .seconds(3))
}
