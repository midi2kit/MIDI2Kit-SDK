//
//  PESubscriptionTypes.swift
//  MIDI2Kit
//
//  Property Exchange Subscription Types
//

import Foundation
import MIDI2Core

// MARK: - PE Notification

/// Property Exchange subscription notification
public struct PENotification: Sendable {
    /// Resource that changed
    public let resource: String

    /// Subscription ID
    public let subscribeId: String

    /// Change header
    public let header: PEHeader?

    /// Change data
    public let data: Data

    /// Source device MUID
    public let sourceMUID: MUID
}

// MARK: - PE Subscription

/// Active subscription information
public struct PESubscription: Sendable {
    /// Subscription ID assigned by device
    public let subscribeId: String

    /// Resource being subscribed to
    public let resource: String

    /// Device handle
    public let device: PEDeviceHandle
}

// MARK: - PE Subscribe Response

/// Subscribe response
public struct PESubscribeResponse: Sendable {
    /// HTTP-style status code
    public let status: Int

    /// Subscription ID (if successful)
    public let subscribeId: String?

    /// Is success response
    public var isSuccess: Bool {
        status >= 200 && status < 300
    }
}
