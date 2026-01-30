//
//  PENotifyAssemblyManager.swift
//  MIDI2Kit
//
//  Multi-chunk assembly for inbound PE Notify messages.
//
//  Notes
//  - Notify requestIDs are owned by the device (inbound-only). We must NOT
//    allocate/release RequestIDs for Notify, and we must not couple Notify
//    assembly to PETransactionManager (which owns GET/SET request lifecycle).
//  - Notify chunks can arrive interleaved across devices. We therefore key
//    assemblies by (sourceMUID, requestID) by holding one PEChunkAssembler per
//    source device.
//

import Foundation
import MIDI2Core

/// A timeout event produced by `PENotifyAssemblyManager.pollTimeouts()`.
public struct PENotifyTimeout: Sendable {
    public let sourceMUID: MUID
    public let result: PEChunkResult
}

/// Assembles multi-chunk Property Exchange Notify messages.
public actor PENotifyAssemblyManager {
    private static let logCategory = "PENotifyAssembly"

    private let timeout: TimeInterval
    private let logger: any MIDI2Logger

    /// One assembler per source device.
    private var assemblersBySource: [MUID: PEChunkAssembler] = [:]

    public init(
        timeout: TimeInterval = 2.0,
        logger: any MIDI2Logger = NullMIDI2Logger()
    ) {
        self.timeout = timeout
        self.logger = logger
    }

    /// Process a Notify chunk from a specific source device.
    ///
    /// - Note: This does **not** consume or allocate Request IDs.
    public func processChunk(
        sourceMUID: MUID,
        requestID: UInt8,
        thisChunk: Int,
        numChunks: Int,
        headerData: Data,
        propertyData: Data
    ) -> PEChunkResult {
        var assembler = assemblersBySource[sourceMUID] ?? PEChunkAssembler(timeout: timeout, logger: logger)

        let result = assembler.addChunk(
            requestID: requestID,
            thisChunk: thisChunk,
            numChunks: numChunks,
            headerData: headerData,
            propertyData: propertyData,
            resource: "Notify"
        )

        if assembler.hasPending {
            assemblersBySource[sourceMUID] = assembler
        } else {
            assemblersBySource.removeValue(forKey: sourceMUID)
        }

        return result
    }

    /// Actively check and prune timed-out Notify assemblies.
    ///
    /// This is primarily intended for deterministic unit tests.
    public func pollTimeouts() -> [PENotifyTimeout] {
        var out: [PENotifyTimeout] = []

        for (source, var assembler) in assemblersBySource {
            let results = assembler.checkTimeouts()
            for r in results {
                if case .timeout = r {
                    out.append(PENotifyTimeout(sourceMUID: source, result: r))
                }
            }

            if assembler.hasPending {
                assemblersBySource[source] = assembler
            } else {
                assemblersBySource.removeValue(forKey: source)
            }
        }

        for t in out {
            if case .timeout(let id, let received, let total, _) = t.result {
                logger.warning(
                    "Notify chunk assembly timeout for \(t.sourceMUID) [\(id)]: \(received)/\(total)",
                    category: Self.logCategory
                )
            }
        }

        return out
    }

    /// Total number of pending Notify assemblies.
    public var pendingCount: Int {
        assemblersBySource.values.reduce(0) { $0 + $1.pendingCount }
    }

    /// Drop all pending Notify assemblies.
    public func cancelAll() {
        assemblersBySource.removeAll()
    }
}
