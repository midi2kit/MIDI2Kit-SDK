//
//  ReceiveHub.swift
//  MIDI2Kit
//
//  Multicast event distribution for MIDI2Client
//

import Foundation

// MARK: - ReceiveHub

/// Internal actor for multicast event distribution
///
/// ReceiveHub solves the "single consumer AsyncStream" problem by:
/// - Managing multiple subscriber continuations
/// - Broadcasting events to all subscribers
/// - Properly cleaning up when subscribers are terminated
///
/// ## Design Decisions
///
/// - **Buffer Policy**: `bufferingNewest(100)` - drops oldest events on overflow
/// - **Cleanup**: Uses `onTermination` handler for automatic subscriber removal
/// - **Thread Safety**: All state is actor-isolated
internal actor ReceiveHub<Event: Sendable> {
    
    // MARK: - Properties
    
    /// Active subscribers
    private var subscribers: [UUID: AsyncStream<Event>.Continuation] = [:]
    
    /// Buffer policy for new streams
    nonisolated let bufferPolicy: AsyncStream<Event>.Continuation.BufferingPolicy
    
    /// Whether the hub has been stopped
    private var isStopped = false
    
    // MARK: - Initialization
    
    init(bufferPolicy: AsyncStream<Event>.Continuation.BufferingPolicy = .bufferingNewest(100)) {
        self.bufferPolicy = bufferPolicy
    }
    
    // MARK: - Public Methods
    
    /// Create a new event stream
    ///
    /// Each call returns an independent stream. Multiple streams can
    /// be active simultaneously, each receiving all broadcast events.
    ///
    /// - Returns: A new AsyncStream that will receive all broadcast events
    func makeStream() -> AsyncStream<Event> {
        // If stopped, return an immediately-finished stream
        if isStopped {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        
        let subscriberID = UUID()
        var storedContinuation: AsyncStream<Event>.Continuation?
        
        let stream = AsyncStream<Event>(bufferingPolicy: bufferPolicy) { continuation in
            storedContinuation = continuation
        }
        
        // Add subscriber immediately (we're already isolated)
        if let continuation = storedContinuation {
            addSubscriberSync(id: subscriberID, continuation: continuation)
            
            // Set up cleanup on termination
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeSubscriber(id: subscriberID)
                }
            }
        }
        
        return stream
    }
    
    /// Broadcast an event to all subscribers
    ///
    /// - Parameter event: The event to broadcast
    func broadcast(_ event: Event) {
        guard !isStopped else { return }
        
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }
    
    /// Finish all streams and stop accepting new subscribers
    ///
    /// After this call:
    /// - All existing streams will be finished
    /// - New calls to `makeStream()` will return immediately-finished streams
    func finishAll() {
        isStopped = true
        
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }
    
    /// Reset the hub for reuse (e.g., after stop/start cycle)
    func reset() {
        isStopped = false
        // Note: Don't clear subscribers here - they manage their own lifecycle
    }
    
    /// Current number of subscribers
    var subscriberCount: Int {
        subscribers.count
    }
    
    // MARK: - Private Methods
    
    private func addSubscriberSync(id: UUID, continuation: AsyncStream<Event>.Continuation) {
        // Don't add if already stopped
        if isStopped {
            continuation.finish()
            return
        }
        subscribers[id] = continuation
    }
    
    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}
