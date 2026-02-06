//
//  PEEmptyResponseTests.swift
//  MIDI2Kit
//
//  Tests for empty response handling
//

import Testing
import Foundation
@testable import MIDI2PE

// MARK: - PEEmptyResponse Tests

@Suite("PEEmptyResponse Tests")
struct PEEmptyResponseTests {

    @Test("Array conforms to PEEmptyResponseRepresentable")
    func arrayConformance() {
        let empty: [String] = [String].emptyResponse
        #expect(empty.isEmpty)
    }

    @Test("emptyResponse error has correct description")
    func emptyResponseDescription() {
        let error = PEError.emptyResponse(resource: "ResourceList")
        #expect(error.description.contains("ResourceList"))
        #expect(error.description.contains("Empty"))
    }

    @Test("emptyResponse is not retryable")
    func emptyResponseNotRetryable() {
        let error = PEError.emptyResponse(resource: "DeviceInfo")
        #expect(!error.isRetryable)
    }

    @Test("emptyResponse is not client error")
    func emptyResponseNotClientError() {
        let error = PEError.emptyResponse(resource: "DeviceInfo")
        #expect(!error.isClientError)
    }

    @Test("emptyResponse is not device error")
    func emptyResponseNotDeviceError() {
        let error = PEError.emptyResponse(resource: "DeviceInfo")
        #expect(!error.isDeviceError)
    }
}
