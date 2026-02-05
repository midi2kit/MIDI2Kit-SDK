//
//  WarmUpStrategyTests.swift
//  MIDI2Kit
//
//  Tests for WarmUpStrategy and WarmUpCache
//

import Testing
import Foundation
@testable import MIDI2Kit
@testable import MIDI2Core

// MARK: - WarmUpStrategy Tests

@Suite("WarmUpStrategy Tests")
struct WarmUpStrategyTests {

    @Test("Strategy equality")
    func strategyEquality() {
        #expect(WarmUpStrategy.always == WarmUpStrategy.always)
        #expect(WarmUpStrategy.never == WarmUpStrategy.never)
        #expect(WarmUpStrategy.adaptive == WarmUpStrategy.adaptive)
        #expect(WarmUpStrategy.vendorBased == WarmUpStrategy.vendorBased)
        #expect(WarmUpStrategy.always != WarmUpStrategy.never)
    }

    @Test("Legacy conversion from true")
    func legacyConversionTrue() {
        let strategy = WarmUpStrategy.from(legacyWarmUp: true)
        #expect(strategy == .always)
    }

    @Test("Legacy conversion from false")
    func legacyConversionFalse() {
        let strategy = WarmUpStrategy.from(legacyWarmUp: false)
        #expect(strategy == .never)
    }

    @Test("May require warm-up property")
    func mayRequireWarmUp() {
        #expect(WarmUpStrategy.always.mayRequireWarmUp == true)
        #expect(WarmUpStrategy.never.mayRequireWarmUp == false)
        #expect(WarmUpStrategy.adaptive.mayRequireWarmUp == true)
        #expect(WarmUpStrategy.vendorBased.mayRequireWarmUp == true)
    }
}

// MARK: - WarmUpCache Tests

@Suite("WarmUpCache Tests")
struct WarmUpCacheTests {

    @Test("Empty cache returns false for needsWarmUp")
    func emptyCacheNeedsWarmUp() async {
        let cache = WarmUpCache()
        let result = await cache.needsWarmUp(for: "test-device")
        #expect(result == false)
    }

    @Test("Empty cache returns false for canSkipWarmUp")
    func emptyCacheCanSkipWarmUp() async {
        let cache = WarmUpCache()
        let result = await cache.canSkipWarmUp(for: "test-device")
        #expect(result == false)
    }

    @Test("Record needs warm-up")
    func recordNeedsWarmUp() async {
        let cache = WarmUpCache()
        await cache.recordNeedsWarmUp("test-device")

        let needsWarmUp = await cache.needsWarmUp(for: "test-device")
        let canSkip = await cache.canSkipWarmUp(for: "test-device")

        #expect(needsWarmUp == true)
        #expect(canSkip == false)
    }

    @Test("Record no warm-up needed")
    func recordNoWarmUpNeeded() async {
        let cache = WarmUpCache()
        await cache.recordNoWarmUpNeeded("test-device")

        let needsWarmUp = await cache.needsWarmUp(for: "test-device")
        let canSkip = await cache.canSkipWarmUp(for: "test-device")

        #expect(needsWarmUp == false)
        #expect(canSkip == true)
    }

    @Test("Recording overwrites previous state")
    func recordOverwrites() async {
        let cache = WarmUpCache()

        // First record needs warm-up
        await cache.recordNeedsWarmUp("test-device")
        #expect(await cache.needsWarmUp(for: "test-device") == true)

        // Then record no warm-up needed
        await cache.recordNoWarmUpNeeded("test-device")
        #expect(await cache.needsWarmUp(for: "test-device") == false)
        #expect(await cache.canSkipWarmUp(for: "test-device") == true)
    }

    @Test("Clear specific device")
    func clearDevice() async {
        let cache = WarmUpCache()
        await cache.recordNeedsWarmUp("device-a")
        await cache.recordNeedsWarmUp("device-b")

        await cache.clear(for: "device-a")

        #expect(await cache.needsWarmUp(for: "device-a") == false)
        #expect(await cache.needsWarmUp(for: "device-b") == true)
    }

    @Test("Clear all devices")
    func clearAll() async {
        let cache = WarmUpCache()
        await cache.recordNeedsWarmUp("device-a")
        await cache.recordNoWarmUpNeeded("device-b")

        await cache.clearAll()

        #expect(await cache.needsWarmUp(for: "device-a") == false)
        #expect(await cache.canSkipWarmUp(for: "device-b") == false)
    }

    @Test("Diagnostics reports correct counts")
    func diagnostics() async {
        let cache = WarmUpCache()
        await cache.recordNeedsWarmUp("device-a")
        await cache.recordNeedsWarmUp("device-b")
        await cache.recordNoWarmUpNeeded("device-c")

        let diag = await cache.diagnostics

        #expect(diag.needsWarmUpCount == 2)
        #expect(diag.noWarmUpNeededCount == 1)
        #expect(diag.totalEntries == 3)
    }

    @Test("Device key from manufacturer and model")
    func deviceKeyFromInfo() {
        let key = WarmUpCache.deviceKey(manufacturer: "KORG", model: "Module Pro")
        #expect(key == "KORG:Module Pro")
    }

    @Test("Device key with nil values")
    func deviceKeyWithNil() {
        let key1 = WarmUpCache.deviceKey(manufacturer: nil, model: "Model")
        #expect(key1 == "unknown:Model")

        let key2 = WarmUpCache.deviceKey(manufacturer: "Vendor", model: nil)
        #expect(key2 == "Vendor:unknown")
    }

    @Test("Device key from MUID")
    func deviceKeyFromMUID() {
        let muid = MUID.random()
        let key = WarmUpCache.deviceKey(muid: muid)
        #expect(key.hasPrefix("muid:"))
    }

    @Test("Multiple devices are tracked independently")
    func multipleDevices() async {
        let cache = WarmUpCache()

        await cache.recordNeedsWarmUp("korg:module")
        await cache.recordNoWarmUpNeeded("roland:integra")
        await cache.recordNeedsWarmUp("yamaha:montage")

        #expect(await cache.needsWarmUp(for: "korg:module") == true)
        #expect(await cache.canSkipWarmUp(for: "roland:integra") == true)
        #expect(await cache.needsWarmUp(for: "yamaha:montage") == true)
        #expect(await cache.needsWarmUp(for: "unknown:device") == false)
    }
}

// MARK: - WarmUpCacheDiagnostics Tests

@Suite("WarmUpCacheDiagnostics Tests")
struct WarmUpCacheDiagnosticsTests {

    @Test("Description format")
    func descriptionFormat() {
        let diag = WarmUpCacheDiagnostics(
            needsWarmUpCount: 2,
            noWarmUpNeededCount: 3,
            totalEntries: 5
        )

        #expect(diag.description.contains("2 need warm-up"))
        #expect(diag.description.contains("3 don't"))
        #expect(diag.description.contains("5 total"))
    }
}

// MARK: - MIDI2ClientConfiguration WarmUpStrategy Tests

@Suite("MIDI2ClientConfiguration WarmUpStrategy Tests")
struct ConfigurationWarmUpStrategyTests {

    @Test("Default configuration uses adaptive strategy")
    func defaultConfiguration() {
        let config = MIDI2ClientConfiguration()
        #expect(config.warmUpStrategy == .adaptive)
    }

    @Test("Explorer preset uses adaptive strategy")
    func explorerPreset() {
        let config = MIDI2ClientConfiguration(preset: .explorer)
        #expect(config.warmUpStrategy == .adaptive)
    }

    @Test("Can set custom strategy")
    func customStrategy() {
        var config = MIDI2ClientConfiguration()

        config.warmUpStrategy = .always
        #expect(config.warmUpStrategy == .always)

        config.warmUpStrategy = .never
        #expect(config.warmUpStrategy == .never)

        config.warmUpStrategy = .vendorBased
        #expect(config.warmUpStrategy == .vendorBased)
    }
}
