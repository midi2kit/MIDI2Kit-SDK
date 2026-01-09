//
//  MIDI2Logger.swift
//  MIDI2Kit
//
//  Logging infrastructure for MIDI2Kit
//

import Foundation
import os.log

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

// MARK: - OSLog Logger (Production)

/// Logger that uses Apple's OSLog system
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

