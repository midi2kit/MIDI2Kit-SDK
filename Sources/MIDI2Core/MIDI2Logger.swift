//
//  MIDI2Logger.swift
//  MIDI2Kit
//
//  Logging infrastructure for MIDI2Kit
//

import Foundation

#if canImport(os)
import os.log
#endif

// MARK: - Log Level

/// Log severity levels
public enum MIDI2LogLevel: Int, Comparable, Sendable {
    case debug = 0    // Verbose debugging info
    case info = 1     // General information
    case notice = 2   // Notable events
    case warning = 3  // Potential issues
    case error = 4    // Errors that don't stop operation
    case fault = 5    // Critical errors
    
    public static func < (lhs: MIDI2LogLevel, rhs: MIDI2LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    public var symbol: String {
        switch self {
        case .debug:   return "🔍"
        case .info:    return "ℹ️"
        case .notice:  return "📋"
        case .warning: return "⚠️"
        case .error:   return "❌"
        case .fault:   return "💥"
        }
    }
    
    public var name: String {
        switch self {
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .notice:  return "NOTICE"
        case .warning: return "WARNING"
        case .error:   return "ERROR"
        case .fault:   return "FAULT"
        }
    }
}

// MARK: - Logger Protocol

/// Protocol for MIDI2Kit logging
public protocol MIDI2Logger: Sendable {
    /// Minimum level to log (messages below this are ignored)
    var minimumLevel: MIDI2LogLevel { get }
    
    /// Log a message
    func log(
        level: MIDI2LogLevel,
        message: @autoclosure () -> String,
        category: String,
        file: String,
        function: String,
        line: Int
    )
}

extension MIDI2Logger {
    /// Convenience: log only if level >= minimumLevel
    @inlinable
    public func shouldLog(_ level: MIDI2LogLevel) -> Bool {
        level >= minimumLevel
    }
    
    // MARK: - Level-specific methods
    
    @inlinable
    public func debug(
        _ message: @autoclosure () -> String,
        category: String = "MIDI2Kit",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message(), category: category, file: file, function: function, line: line)
    }
    
    @inlinable
    public func info(
        _ message: @autoclosure () -> String,
        category: String = "MIDI2Kit",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message(), category: category, file: file, function: function, line: line)
    }
    
    @inlinable
    public func notice(
        _ message: @autoclosure () -> String,
        category: String = "MIDI2Kit",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .notice, message: message(), category: category, file: file, function: function, line: line)
    }
    
    @inlinable
    public func warning(
        _ message: @autoclosure () -> String,
        category: String = "MIDI2Kit",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message(), category: category, file: file, function: function, line: line)
    }
    
    @inlinable
    public func error(
        _ message: @autoclosure () -> String,
        category: String = "MIDI2Kit",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message(), category: category, file: file, function: function, line: line)
    }
    
    @inlinable
    public func fault(
        _ message: @autoclosure () -> String,
        category: String = "MIDI2Kit",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .fault, message: message(), category: category, file: file, function: function, line: line)
    }
}

// MARK: - Null Logger (Default - Silent)

/// Logger that discards all messages (default)
public struct NullMIDI2Logger: MIDI2Logger {
    public let minimumLevel: MIDI2LogLevel = .fault
    
    public init() {}
    
    @inlinable
    public func log(
        level: MIDI2LogLevel,
        message: @autoclosure () -> String,
        category: String,
        file: String,
        function: String,
        line: Int
    ) {
        // Intentionally empty - discard all logs
    }
}

// MARK: - Stdout Logger (Development)

/// Logger that prints to stdout (for development/debugging)
public final class StdoutMIDI2Logger: MIDI2Logger, @unchecked Sendable {
    public let minimumLevel: MIDI2LogLevel
    private let includeLocation: Bool
    private let lock = NSLock()
    
    public init(minimumLevel: MIDI2LogLevel = .debug, includeLocation: Bool = false) {
        self.minimumLevel = minimumLevel
        self.includeLocation = includeLocation
    }
    
    public func log(
        level: MIDI2LogLevel,
        message: @autoclosure () -> String,
        category: String,
        file: String,
        function: String,
        line: Int
    ) {
        guard shouldLog(level) else { return }
        
        let msg = message()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        var output = "\(level.symbol) [\(category)] \(msg)"
        
        if includeLocation {
            let filename = (file as NSString).lastPathComponent
            output += " (\(filename):\(line) \(function))"
        }
        
        lock.lock()
        print("\(timestamp) \(output)")
        lock.unlock()
    }
}

// MARK: - OSLog Logger (Production - Apple platforms only)

#if canImport(os)

/// Logger that uses Apple's OSLog system
///
/// - Note: This logger is only available on Apple platforms (iOS, macOS, tvOS, watchOS).
///         On other platforms, use `StdoutMIDI2Logger` instead.
public final class OSLogMIDI2Logger: MIDI2Logger, @unchecked Sendable {
    public let minimumLevel: MIDI2LogLevel
    private let subsystem: String
    private var loggers: [String: OSLog] = [:]
    private let lock = NSLock()
    
    public init(subsystem: String, minimumLevel: MIDI2LogLevel = .notice) {
        self.subsystem = subsystem
        self.minimumLevel = minimumLevel
    }
    
    private func osLog(for category: String) -> OSLog {
        lock.lock()
        defer { lock.unlock() }
        
        if let existing = loggers[category] {
            return existing
        }
        
        let logger = OSLog(subsystem: subsystem, category: category)
        loggers[category] = logger
        return logger
    }
    
    public func log(
        level: MIDI2LogLevel,
        message: @autoclosure () -> String,
        category: String,
        file: String,
        function: String,
        line: Int
    ) {
        guard shouldLog(level) else { return }
        
        let logger = osLog(for: category)
        let osLogType = level.osLogType
        let msg = message()
        
        os_log("%{public}@", log: logger, type: osLogType, msg)
    }
}

extension MIDI2LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug:   return .debug
        case .info:    return .info
        case .notice:  return .default
        case .warning: return .default
        case .error:   return .error
        case .fault:   return .fault
        }
    }
}

#endif

// MARK: - Composite Logger

/// Logger that forwards to multiple loggers
public final class CompositeMIDI2Logger: MIDI2Logger, @unchecked Sendable {
    public let minimumLevel: MIDI2LogLevel
    private let loggers: [any MIDI2Logger]
    
    public init(loggers: [any MIDI2Logger]) {
        self.loggers = loggers
        self.minimumLevel = loggers.map(\.minimumLevel).min() ?? .fault
    }
    
    public func log(
        level: MIDI2LogLevel,
        message: @autoclosure () -> String,
        category: String,
        file: String,
        function: String,
        line: Int
    ) {
        let msg = message()
        for logger in loggers {
            logger.log(level: level, message: msg, category: category, file: file, function: function, line: line)
        }
    }
}

// MARK: - Logging Utilities

/// Utilities for safe, structured logging
///
/// ## Logging Guidelines
///
/// ### What to Log (Structured Data)
/// - Request ID, MUID, resource name
/// - Chunk progress (thisChunk/numChunks)
/// - Status codes, timeout types
/// - Data size (not content)
/// - First N bytes as hex (limited preview)
///
/// ### What NOT to Log
/// - Full SysEx dumps (size, performance, sensitive)
/// - Complete message bodies
/// - Raw binary data without limits
///
/// ### Log Levels
/// - `debug`: Development only, detailed flow (chunk received, state changes)
/// - `info`: Lifecycle events (start/stop monitoring, connection changes)
/// - `notice`: Notable events (timeout, transaction complete)
/// - `warning`: Recoverable issues (unknown requestID, near exhaustion)
/// - `error`: Operation failures (ID exhausted, send failed)
/// - `fault`: Critical issues (data corruption, invariant violations)
public enum MIDI2LogUtils {
    
    /// Maximum bytes to include in hex preview (default: 32)
    public static let defaultHexPreviewLimit = 32
    
    /// Format data as limited hex string for safe logging
    ///
    /// - Parameters:
    ///   - data: Data to format
    ///   - limit: Maximum bytes to show (default: 32)
    /// - Returns: Hex string with truncation indicator if needed
    ///
    /// Example output: "F0 7E 7F 0D 34 01..." (32 of 128 bytes)
    public static func hexPreview(_ data: Data, limit: Int = defaultHexPreviewLimit) -> String {
        hexPreview(Array(data), limit: limit)
    }
    
    /// Format byte array as limited hex string for safe logging
    ///
    /// - Parameters:
    ///   - bytes: Bytes to format
    ///   - limit: Maximum bytes to show (default: 32)
    /// - Returns: Hex string with truncation indicator if needed
    public static func hexPreview(_ bytes: [UInt8], limit: Int = defaultHexPreviewLimit) -> String {
        guard !bytes.isEmpty else { return "(empty)" }
        
        let preview = bytes.prefix(limit)
        let hex = preview.map { String(format: "%02X", $0) }.joined(separator: " ")
        
        if bytes.count > limit {
            return "\(hex)... (\(limit) of \(bytes.count) bytes)"
        } else {
            return "\(hex) (\(bytes.count) bytes)"
        }
    }
    
    /// Format MUID for logging (hex representation)
    public static func formatMUID(_ muid: UInt32) -> String {
        String(format: "0x%08X", muid)
    }
    
    /// Format chunk progress for logging
    ///
    /// Example output: "3/5 chunks"
    public static func chunkProgress(received: Int, total: Int) -> String {
        "\(received)/\(total) chunks"
    }
    
    /// Format transaction info for structured logging
    ///
    /// Example output: "[42] DeviceInfo -> 0x12345678"
    public static func transactionInfo(requestID: UInt8, resource: String, destinationMUID: UInt32) -> String {
        "[\(requestID)] \(resource) -> \(formatMUID(destinationMUID))"
    }
    
    /// Format PE response summary for logging
    ///
    /// Example output: "status=200, header=45B, body=1024B"
    public static func responseSummary(status: Int, headerSize: Int, bodySize: Int) -> String {
        "status=\(status), header=\(headerSize)B, body=\(bodySize)B"
    }
    
    /// Format timeout event for logging
    ///
    /// Example output: "timeout after 5.0s (received 2/4 chunks)"
    public static func timeoutInfo(elapsedSeconds: TimeInterval, receivedChunks: Int, totalChunks: Int) -> String {
        let elapsed = String(format: "%.1f", elapsedSeconds)
        return "timeout after \(elapsed)s (received \(receivedChunks)/\(totalChunks) chunks)"
    }
}

// MARK: - Convenience Extensions

extension Data {
    /// Safe hex preview for logging (limited to 32 bytes by default)
    public var logPreview: String {
        MIDI2LogUtils.hexPreview(self)
    }
    
    /// Safe hex preview with custom limit
    public func logPreview(limit: Int) -> String {
        MIDI2LogUtils.hexPreview(self, limit: limit)
    }
}

extension Array where Element == UInt8 {
    /// Safe hex preview for logging (limited to 32 bytes by default)
    public var logPreview: String {
        MIDI2LogUtils.hexPreview(self)
    }
    
    /// Safe hex preview with custom limit
    public func logPreview(limit: Int) -> String {
        MIDI2LogUtils.hexPreview(self, limit: limit)
    }
}
