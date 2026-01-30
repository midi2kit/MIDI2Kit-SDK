//
//  PEResponse.swift
//  MIDI2Kit
//
//  Property Exchange response type
//

import Foundation
import MIDI2Core

// MARK: - PE Response

/// Property Exchange response
public struct PEResponse: Sendable {
    /// HTTP-style status code
    public let status: Int

    /// Response header (parsed JSON)
    public let header: PEHeader?

    /// Response body (raw data, may be Mcoded7 encoded)
    public let body: Data

    /// Decoded body (Mcoded7 decoded if needed)
    ///
    /// Decoding logic:
    /// 1. If header indicates Mcoded7 encoding, decode it
    /// 2. If body starts with '{' or '[', assume it's already JSON
    /// 3. Otherwise, try Mcoded7 decode as fallback (for devices like KORG that don't set the header flag)
    public var decodedBody: Data {
        // If header explicitly indicates Mcoded7
        if header?.isMcoded7 == true {
            return Mcoded7.decode(body) ?? body
        }

        // If body looks like JSON already (starts with '{' or '['), return as-is
        if let firstByte = body.first, firstByte == 0x7B || firstByte == 0x5B {
            return body
        }

        // Fallback: try Mcoded7 decode for devices that don't set the header flag
        // (e.g., KORG devices send Mcoded7-encoded data without mutualEncoding header)
        if let decoded = Mcoded7.decode(body) {
            return decoded
        }

        return body
    }

    /// Body as UTF-8 string
    public var bodyString: String? {
        String(data: decodedBody, encoding: .utf8)
    }

    /// Is success response
    public var isSuccess: Bool {
        status >= 200 && status < 300
    }

    /// Is error response
    public var isError: Bool {
        status >= 400
    }

    public init(status: Int, header: PEHeader?, body: Data) {
        self.status = status
        self.header = header
        self.body = body
    }
}
