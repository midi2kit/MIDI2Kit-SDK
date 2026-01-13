//
//  PEManagerSession.swift
//  MIDI2Kit
//
//  Lifecycle wrapper for PEManager
//

import Foundation
import MIDI2Core
import MIDI2Transport

/// A lifecycle wrapper that makes it hard to forget `PEManager.stopReceiving()`.
///
/// `PEManager` requires callers to call `stopReceiving()` before releasing it,
/// otherwise pending continuations may be dropped.
/// This wrapper provides a deterministic `stop()` path.
///
/// ## Usage
/// ```swift
/// let session = await PEManagerSession(
///     transport: transport,
///     sourceMUID: myMUID,
///     stopTransportOnStop: true
/// )
/// let pe = session.manager
///
/// // ... use `pe` ...
///
/// await session.stop()
/// ```
public final class PEManagerSession {
    public let manager: PEManager

    private let transport: any MIDITransport
    private let stopTransportOnStop: Bool

    public init(
        transport: any MIDITransport,
        sourceMUID: MUID,
        maxInflightPerDevice: Int = 2,
        notifyAssemblyTimeout: TimeInterval = 0.5,
        logger: any MIDI2Logger = NullMIDI2Logger(),
        stopTransportOnStop: Bool = false
    ) async {
        self.transport = transport
        self.stopTransportOnStop = stopTransportOnStop

        let m = PEManager(
            transport: transport,
            sourceMUID: sourceMUID,
            maxInflightPerDevice: maxInflightPerDevice,
            notifyAssemblyTimeout: notifyAssemblyTimeout,
            logger: logger
        )
        self.manager = m
        await m.startReceiving()
    }

    /// Deterministic shutdown (recommended).
    public func stop() async {
        await manager.stopReceiving()
        if stopTransportOnStop {
            await transport.shutdown()
        }
    }

    deinit {
        // Intentionally no automatic cleanup.
        //
        // Call `await session.stop()` explicitly to shut down PEManager safely.
        // (Avoids Strict Concurrency issues with Task.detached capturing non-Sendable values.)
    }
}
