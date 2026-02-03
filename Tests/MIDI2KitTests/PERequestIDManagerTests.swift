//
//  PERequestIDManagerTests.swift
//  MIDI2Kit
//
//  Tests for PE Request ID management
//

import Testing
import Foundation
@testable import MIDI2PE

@Suite("PERequestIDManager Tests")
struct PERequestIDManagerTests {

    @Test("Acquire returns valid 7-bit ID")
    func acquireValid7BitID() {
        var manager = PERequestIDManager(cooldownPeriod: 0)

        guard let id = manager.acquire() else {
            Issue.record("Should acquire ID")
            return
        }

        #expect(id <= 127)
    }

    @Test("Sequential IDs are unique")
    func sequentialUnique() {
        var manager = PERequestIDManager(cooldownPeriod: 0)
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

    @Test("Release allows reuse (no cooldown)")
    func releaseAllowsReuse() {
        var manager = PERequestIDManager(cooldownPeriod: 0)

        guard let id1 = manager.acquire() else {
            Issue.record("Should acquire ID")
            return
        }

        manager.release(id1)

        // After releasing with no cooldown, should be able to acquire more
        guard let id2 = manager.acquire() else {
            Issue.record("Should acquire ID after release")
            return
        }

        #expect(id2 <= 127)
    }

    @Test("All 128 IDs can be acquired")
    func acquireAll128() {
        var manager = PERequestIDManager(cooldownPeriod: 0)
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
        var manager = PERequestIDManager(cooldownPeriod: 0)

        let id1 = manager.acquire()
        let id2 = manager.acquire()
        let id3 = manager.acquire()

        #expect(manager.usedCount == 3)

        manager.release([id1!, id2!, id3!])

        #expect(manager.usedCount == 0)
    }

    @Test("IsInUse tracking")
    func isInUseTracking() {
        var manager = PERequestIDManager(cooldownPeriod: 0)

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
        var manager = PERequestIDManager(cooldownPeriod: 0)

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
        var manager = PERequestIDManager(cooldownPeriod: 0)

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
        var manager = PERequestIDManager(cooldownPeriod: 0)

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
        var manager = PERequestIDManager(cooldownPeriod: 0)

        guard let id = manager.acquire() else {
            Issue.record("Should acquire ID")
            return
        }

        // Release with MSB set (should be masked)
        manager.release(id | 0x80)

        #expect(!manager.isInUse(id))
    }
}

// MARK: - Cooldown Tests

@Suite("PERequestIDManager Cooldown Tests")
struct PERequestIDManagerCooldownTests {

    @Test("Released ID enters cooldown")
    func releasedIDEntersCooldown() {
        var manager = PERequestIDManager(cooldownPeriod: 10.0)
        let now = Date()

        guard let id = manager.acquire(now: now) else {
            Issue.record("Should acquire ID")
            return
        }

        #expect(!manager.isCooling(id))

        manager.release(id, at: now)

        #expect(!manager.isInUse(id))
        #expect(manager.isCooling(id))
        #expect(manager.coolingCount == 1)
    }

    @Test("Cooling ID cannot be reacquired immediately")
    func coolingIDNotReacquirable() {
        var manager = PERequestIDManager(cooldownPeriod: 10.0)
        let now = Date()

        // Acquire all 128 IDs
        var ids: [UInt8] = []
        for _ in 0..<128 {
            if let id = manager.acquire(now: now) {
                ids.append(id)
            }
        }
        #expect(ids.count == 128)

        // Release one
        manager.release(ids[0], at: now)

        // Try to acquire - should fail because ID is cooling
        #expect(manager.acquire(now: now) == nil)

        // Available count should be 0 (1 cooling, 127 in use)
        #expect(manager.availableCount == 0)
        #expect(manager.coolingCount == 1)
        #expect(manager.usedCount == 127)
    }

    @Test("Cooldown expires after period")
    func cooldownExpires() {
        var manager = PERequestIDManager(cooldownPeriod: 1.0)
        let now = Date()

        // Acquire all IDs
        var ids: [UInt8] = []
        for _ in 0..<128 {
            if let id = manager.acquire(now: now) {
                ids.append(id)
            }
        }

        // Release one
        manager.release(ids[0], at: now)

        // Cannot acquire immediately
        #expect(manager.acquire(now: now) == nil)

        // After cooldown period, should be able to acquire
        let later = now.addingTimeInterval(1.5)
        guard let newID = manager.acquire(now: later) else {
            Issue.record("Should acquire after cooldown expires")
            return
        }

        #expect(newID == ids[0])  // Should get the same ID back
        #expect(manager.coolingCount == 0)
    }

    @Test("Force cooldown expire")
    func forceCooldownExpire() {
        var manager = PERequestIDManager(cooldownPeriod: 100.0)
        let now = Date()

        guard let id = manager.acquire(now: now) else {
            Issue.record("Should acquire ID")
            return
        }

        manager.release(id, at: now)
        #expect(manager.isCooling(id))

        manager.forceCooldownExpire(id)
        #expect(!manager.isCooling(id))

        // Should be able to acquire now
        #expect(manager.acquire(now: now) != nil)
    }

    @Test("Release all clears cooldowns")
    func releaseAllClearsCooldowns() {
        var manager = PERequestIDManager(cooldownPeriod: 100.0)
        let now = Date()

        let id1 = manager.acquire(now: now)!
        let id2 = manager.acquire(now: now)!

        manager.release(id1, at: now)
        manager.release(id2, at: now)

        #expect(manager.coolingCount == 2)

        manager.releaseAll()

        #expect(manager.coolingCount == 0)
        #expect(manager.availableCount == 128)
    }

    @Test("Default cooldown period is 2 seconds")
    func defaultCooldownPeriod() {
        let manager = PERequestIDManager()
        #expect(manager.cooldownPeriod == 2.0)
    }

    @Test("Cooldown prevents stale response mismatch")
    func cooldownPreventsStaleResponseMismatch() {
        // Simulate the scenario:
        // 1. Request A uses ID 5, times out at T=0
        // 2. ID 5 is released (enters cooldown)
        // 3. New request at T=0.5 cannot get ID 5
        // 4. At T=2.5 (after cooldown), ID 5 becomes available again

        var manager = PERequestIDManager(cooldownPeriod: 2.0)
        let t0 = Date()
        let t05 = t0.addingTimeInterval(0.5)
        let t25 = t0.addingTimeInterval(2.5)

        // Acquire all IDs
        var ids: [UInt8] = []
        for _ in 0..<128 {
            if let id = manager.acquire(now: t0) {
                ids.append(id)
            }
        }

        // Find ID 5 and release it (simulating timeout)
        let targetID: UInt8 = 5
        manager.release(targetID, at: t0)

        // At T=0.5, try to acquire - should NOT get ID 5
        let newID = manager.acquire(now: t05)
        #expect(newID == nil)  // All IDs in use or cooling

        // At T=2.5, ID 5 should be available again
        let laterID = manager.acquire(now: t25)
        #expect(laterID == targetID)
    }
}
