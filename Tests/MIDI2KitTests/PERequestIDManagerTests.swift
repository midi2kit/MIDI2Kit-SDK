//
//  PERequestIDManagerTests.swift
//  MIDI2Kit
//
//  Tests for PE Request ID management
//

import Testing
@testable import MIDI2PE

@Suite("PERequestIDManager Tests")
struct PERequestIDManagerTests {
    
    @Test("Acquire returns valid 7-bit ID")
    func acquireValid7BitID() {
        var manager = PERequestIDManager()
        
        guard let id = manager.acquire() else {
            Issue.record("Should acquire ID")
            return
        }
        
        #expect(id <= 127)
    }
    
    @Test("Sequential IDs are unique")
    func sequentialUnique() {
        var manager = PERequestIDManager()
        var ids: Set<UInt8> = []
        
        for _ in 0..<10 {
            guard let id = manager.acquire() else {
                Issue.record("Should acquire ID")
                return
            }
            #expect(!ids.contains(id))
            ids.insert(id)
        }
    }
    
    @Test("Release allows reuse")
    func releaseAllowsReuse() {
        var manager = PERequestIDManager()
        
        guard let id1 = manager.acquire() else {
            Issue.record("Should acquire ID")
            return
        }
        
        manager.release(id1)
        
        // After releasing, should be able to acquire more
        guard let id2 = manager.acquire() else {
            Issue.record("Should acquire ID after release")
            return
        }
        
        #expect(id2 <= 127)
    }
    
    @Test("All 128 IDs can be acquired")
    func acquireAll128() {
        var manager = PERequestIDManager()
        var acquired: [UInt8] = []
        
        for i in 0..<128 {
            guard let id = manager.acquire() else {
                Issue.record("Failed to acquire ID \(i)")
                return
            }
            acquired.append(id)
        }
        
        #expect(acquired.count == 128)
        #expect(Set(acquired).count == 128)  // All unique
        
        // 129th should fail
        #expect(manager.acquire() == nil)
    }
    
    @Test("Release multiple IDs")
    func releaseMultiple() {
        var manager = PERequestIDManager()
        
        let id1 = manager.acquire()
        let id2 = manager.acquire()
        let id3 = manager.acquire()
        
        #expect(manager.usedCount == 3)
        
        manager.release([id1!, id2!, id3!])
        
        #expect(manager.usedCount == 0)
    }
    
    @Test("IsInUse tracking")
    func isInUseTracking() {
        var manager = PERequestIDManager()
        
        guard let id = manager.acquire() else {
            Issue.record("Should acquire ID")
            return
        }
        
        #expect(manager.isInUse(id))
        
        manager.release(id)
        
        #expect(!manager.isInUse(id))
    }
    
    @Test("Available count")
    func availableCount() {
        var manager = PERequestIDManager()
        
        #expect(manager.availableCount == 128)
        #expect(manager.usedCount == 0)
        
        _ = manager.acquire()
        _ = manager.acquire()
        _ = manager.acquire()
        
        #expect(manager.availableCount == 125)
        #expect(manager.usedCount == 3)
    }
    
    @Test("Release all")
    func releaseAll() {
        var manager = PERequestIDManager()
        
        for _ in 0..<50 {
            _ = manager.acquire()
        }
        
        #expect(manager.usedCount == 50)
        
        manager.releaseAll()
        
        #expect(manager.usedCount == 0)
        #expect(manager.availableCount == 128)
    }
    
    @Test("ID wraps around at 128")
    func wrapAround() {
        var manager = PERequestIDManager()
        
        // Acquire and release to advance counter
        for _ in 0..<200 {
            guard let id = manager.acquire() else {
                Issue.record("Should acquire ID")
                return
            }
            #expect(id <= 127)  // Always 7-bit
            manager.release(id)
        }
    }
    
    @Test("7-bit masking on release")
    func maskingOnRelease() {
        var manager = PERequestIDManager()
        
        guard let id = manager.acquire() else {
            Issue.record("Should acquire ID")
            return
        }
        
        // Release with MSB set (should be masked)
        manager.release(id | 0x80)
        
        #expect(!manager.isInUse(id))
    }
}
