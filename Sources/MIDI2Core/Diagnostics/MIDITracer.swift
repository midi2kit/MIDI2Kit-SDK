//
//  MIDITracer.swift
//  MIDI2Kit
//
//  Ring buffer for MIDI message tracing and diagnostics
//

import Foundation

// MARK: - Trace Entry

/// Direction of MIDI message
public enum MIDIDirection: String, Sendable {
    case send = "→"
    case receive = "←"
}

/// A single trace entry
public struct MIDITraceEntry: Sendable {
    /// When the message was traced
    public let timestamp: Date
    
    /// Send or receive
    public let direction: MIDIDirection
    
    /// Endpoint identifier (source or destination)
    public let endpoint: UInt32
    
    /// Endpoint name (if available)
    public let endpointName: String?
    
    /// Raw message bytes
    public let data: [UInt8]
    
    /// Optional label (e.g., "Discovery", "PE GET")
    public let label: String?
    
    public init(
        timestamp: Date = Date(),
        direction: MIDIDirection,
        endpoint: UInt32,
        endpointName: String? = nil,
        data: [UInt8],
        label: String? = nil
    ) {
        self.timestamp = timestamp
        self.direction = direction
        self.endpoint = endpoint
        self.endpointName = endpointName
        self.data = data
        self.label = label
    }
    
    /// Format as hex string
    public var hexString: String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// Format as compact hex (no spaces)
    public var compactHex: String {
        data.map { String(format: "%02X", $0) }.joined()
    }
    
    /// Formatted timestamp
    public var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    /// Single-line description
    public var oneLine: String {
        let endpointStr = endpointName ?? "0x\(String(format: "%08X", endpoint))"
        let labelStr = label.map { "[\($0)] " } ?? ""
        let preview = data.count > 32
            ? "\(data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " "))... (\(data.count)B)"
            : hexString
        return "\(formattedTime) \(direction.rawValue) \(endpointStr) \(labelStr)\(preview)"
    }
    
    /// Auto-detect label from SysEx content
    public static func detectLabel(for data: [UInt8]) -> String? {
        guard data.count >= 5,
              data[0] == 0xF0,
              data[1] == 0x7E else { return nil }
        
        // Universal SysEx - check sub-ID
        guard data.count >= 6 else { return nil }
        
        let subID1 = data[4]
        let subID2 = data.count > 5 ? data[5] : 0
        
        switch (subID1, subID2) {
        case (0x0D, 0x70): return "Discovery"
        case (0x0D, 0x71): return "Discovery Reply"
        case (0x0D, 0x72): return "Endpoint Info"
        case (0x0D, 0x73): return "Endpoint Info Reply"
        case (0x0D, 0x7E): return "Invalidate MUID"
        case (0x0D, 0x7F): return "NAK"
        case (0x0D, 0x34): return "PE GET"
        case (0x0D, 0x35): return "PE GET Reply"
        case (0x0D, 0x36): return "PE SET"
        case (0x0D, 0x37): return "PE SET Reply"
        case (0x0D, 0x38): return "PE Subscribe"
        case (0x0D, 0x39): return "PE Subscribe Reply"
        case (0x0D, 0x3F): return "PE Notify"
        default:
            if subID1 == 0x0D {
                return "MIDI-CI 0x\(String(format: "%02X", subID2))"
            }
            return nil
        }
    }
}

// MARK: - MIDI Tracer

/// Thread-safe ring buffer for MIDI message tracing
///
/// ## Usage
///
/// ```swift
/// let tracer = MIDITracer(capacity: 100)
///
/// // Record messages
/// tracer.record(direction: .send, endpoint: destID, data: message)
/// tracer.record(direction: .receive, endpoint: sourceID, data: response)
///
/// // Dump recent messages
/// print(tracer.dump())
///
/// // Export for analysis
/// let entries = tracer.entries
/// ```
public final class MIDITracer: @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Maximum number of entries to retain
    public let capacity: Int
    
    // MARK: - State (all protected by lock)
    
    private var _isEnabled: Bool = true
    private var buffer: [MIDITraceEntry]
    private var writeIndex: Int = 0
    private var count: Int = 0
    private let lock = NSLock()
    
    /// Whether tracing is enabled
    public var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isEnabled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isEnabled = newValue
        }
    }
    
    // MARK: - Initialization
    
    /// Create a tracer with specified capacity
    /// - Parameter capacity: Maximum entries to retain (default: 200)
    public init(capacity: Int = 200) {
        self.capacity = max(10, capacity)
        self.buffer = []
        self.buffer.reserveCapacity(self.capacity)
    }
    
    // MARK: - Recording
    
    /// Record a MIDI message
    public func record(
        direction: MIDIDirection,
        endpoint: UInt32,
        data: [UInt8],
        label: String? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        guard _isEnabled else { return }
        
        let entry = MIDITraceEntry(
            direction: direction,
            endpoint: endpoint,
            endpointName: nil,
            data: data,
            label: label
        )
        
        if buffer.count < capacity {
            buffer.append(entry)
        } else {
            buffer[writeIndex] = entry
        }
        
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }
    
    /// Record a send
    public func recordSend(to endpoint: UInt32, data: [UInt8], label: String? = nil) {
        record(direction: .send, endpoint: endpoint, data: data, label: label)
    }
    
    /// Record a receive
    public func recordReceive(from endpoint: UInt32, data: [UInt8], label: String? = nil) {
        record(direction: .receive, endpoint: endpoint, data: data, label: label)
    }
    
    // MARK: - Retrieval
    
    /// Get all entries in chronological order
    public var entries: [MIDITraceEntry] {
        lock.lock()
        defer { lock.unlock() }
        
        guard count > 0 else { return [] }
        
        if count < capacity {
            return Array(buffer)
        }
        
        // Ring buffer is full - reorder from oldest to newest
        let start = writeIndex
        return Array(buffer[start...]) + Array(buffer[..<start])
    }
    
    /// Get the last N entries
    public func lastEntries(_ n: Int) -> [MIDITraceEntry] {
        let all = entries
        return Array(all.suffix(n))
    }
    
    /// Get entries filtered by direction
    public func entries(direction: MIDIDirection) -> [MIDITraceEntry] {
        entries.filter { $0.direction == direction }
    }
    
    /// Get entries filtered by endpoint
    public func entries(endpoint: UInt32) -> [MIDITraceEntry] {
        entries.filter { $0.endpoint == endpoint }
    }
    
    /// Get entries within time range
    public func entries(from start: Date, to end: Date) -> [MIDITraceEntry] {
        entries.filter { $0.timestamp >= start && $0.timestamp <= end }
    }
    
    /// Number of entries currently stored
    public var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    
    // MARK: - Dump
    
    /// Dump all entries as formatted string
    public func dump() -> String {
        let all = entries
        guard !all.isEmpty else { return "=== MIDI Trace (empty) ===" }
        
        var lines = ["=== MIDI Trace (\(all.count) entries) ==="]
        for entry in all {
            lines.append(entry.oneLine)
        }
        return lines.joined(separator: "\n")
    }
    
    /// Dump last N entries
    public func dump(last n: Int) -> String {
        let recent = lastEntries(n)
        guard !recent.isEmpty else { return "=== MIDI Trace (empty) ===" }
        
        var lines = ["=== MIDI Trace (last \(recent.count)) ==="]
        for entry in recent {
            lines.append(entry.oneLine)
        }
        return lines.joined(separator: "\n")
    }
    
    /// Dump with full hex (no truncation)
    public func dumpFull() -> String {
        let all = entries
        guard !all.isEmpty else { return "=== MIDI Trace Full (empty) ===" }
        
        var lines = ["=== MIDI Trace Full (\(all.count) entries) ==="]
        for entry in all {
            let endpointStr = entry.endpointName ?? "0x\(String(format: "%08X", entry.endpoint))"
            let labelStr = entry.label.map { "[\($0)]" } ?? ""
            lines.append("\(entry.formattedTime) \(entry.direction.rawValue) \(endpointStr) \(labelStr)")
            lines.append("  \(entry.hexString)")
        }
        return lines.joined(separator: "\n")
    }
    
    /// Export as JSON for external analysis
    public func exportJSON() throws -> Data {
        struct ExportEntry: Encodable {
            let timestamp: String
            let direction: String
            let endpoint: UInt32
            let label: String?
            let data: String
            let size: Int
        }
        
        let exportEntries = entries.map { entry in
            ExportEntry(
                timestamp: ISO8601DateFormatter().string(from: entry.timestamp),
                direction: entry.direction.rawValue,
                endpoint: entry.endpoint,
                label: entry.label,
                data: entry.compactHex,
                size: entry.data.count
            )
        }
        return try JSONEncoder().encode(exportEntries)
    }
    
    // MARK: - Clear
    
    /// Clear all entries
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        buffer.removeAll(keepingCapacity: true)
        writeIndex = 0
        count = 0
    }
}

// MARK: - Shared Tracer

extension MIDITracer {
    /// Shared global tracer for convenience
    ///
    /// Configure capacity before first use if needed:
    /// ```swift
    /// MIDITracer.shared = MIDITracer(capacity: 500)
    /// ```
    public nonisolated(unsafe) static var shared = MIDITracer(capacity: 200)
}
