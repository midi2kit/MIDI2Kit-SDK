//
//  MIDI2Logger.swift
//  MIDI2Kit
//
//  Unified logging for MIDI2Kit High-Level API
//

import Foundation
import os.log

// MARK: - AtomicBool

/// Thread-safe boolean wrapper using os_unfair_lock
private final class AtomicBool: @unchecked Sendable {
    private var _value: Bool
    private let lock = OSAllocatedUnfairLock()
    
    init(_ initialValue: Bool) {
        _value = initialValue
    }
    
    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

// MARK: - MIDI2Logger

/// Unified logger for MIDI2Kit
///
/// Uses `os.Logger` for efficient, filterable logging.
///
/// ## Log Categories
///
/// - `client`: MIDI2Client lifecycle and general events
/// - `dispatcher`: Message receive/dispatch events
/// - `destination`: Destination resolution
/// - `pe`: Property Exchange operations
///
/// ## Filtering Logs
///
/// Use Console.app or `log` command to filter:
/// ```
/// log stream --predicate 'subsystem == "com.midi2kit"'
/// log stream --predicate 'subsystem == "com.midi2kit" AND category == "dispatcher"'
/// ```
///
/// ## Disabling Logs
///
/// Set `MIDI2Logger.isEnabled = false` to disable all logging.
public enum MIDI2Logger {
    
    // MARK: - Configuration
    
    /// Whether logging is enabled (default: true)
    ///
    /// Set to `false` to disable all MIDI2Kit logging.
    /// Thread-safe via atomic storage.
    public static var isEnabled: Bool {
        get { _isEnabled.value }
        set { _isEnabled.value = newValue }
    }
    private static let _isEnabled = AtomicBool(true)
    
    /// Whether verbose logging is enabled (default: false)
    ///
    /// When `true`, includes detailed message hex dumps and timing info.
    /// Thread-safe via atomic storage.
    public static var isVerbose: Bool {
        get { _isVerbose.value }
        set { _isVerbose.value = newValue }
    }
    private static let _isVerbose = AtomicBool(false)
    
    // MARK: - Subsystem
    
    private static let subsystem = "com.midi2kit"
    
    // MARK: - Loggers
    
    /// Client lifecycle logger
    public static let client = Logger(subsystem: subsystem, category: "client")
    
    /// Message dispatcher logger
    public static let dispatcher = Logger(subsystem: subsystem, category: "dispatcher")
    
    /// Destination resolution logger
    public static let destination = Logger(subsystem: subsystem, category: "destination")
    
    /// Property Exchange logger
    public static let pe = Logger(subsystem: subsystem, category: "pe")
}

// MARK: - Logger Extensions

extension Logger {
    /// Log debug message if MIDI2Logger is enabled
    @inlinable
    func midi2Debug(_ message: String) {
        guard MIDI2Logger.isEnabled else { return }
        self.debug("\(message, privacy: .public)")
    }
    
    /// Log info message if MIDI2Logger is enabled
    @inlinable
    func midi2Info(_ message: String) {
        guard MIDI2Logger.isEnabled else { return }
        self.info("\(message, privacy: .public)")
    }
    
    /// Log warning if MIDI2Logger is enabled
    @inlinable
    func midi2Warning(_ message: String) {
        guard MIDI2Logger.isEnabled else { return }
        self.warning("\(message, privacy: .public)")
    }
    
    /// Log error if MIDI2Logger is enabled
    @inlinable
    func midi2Error(_ message: String) {
        guard MIDI2Logger.isEnabled else { return }
        self.error("\(message, privacy: .public)")
    }
    
    /// Log verbose detail (only if isVerbose is true)
    @inlinable
    func midi2Verbose(_ message: String) {
        guard MIDI2Logger.isEnabled && MIDI2Logger.isVerbose else { return }
        self.debug("\(message, privacy: .public)")
    }
}
