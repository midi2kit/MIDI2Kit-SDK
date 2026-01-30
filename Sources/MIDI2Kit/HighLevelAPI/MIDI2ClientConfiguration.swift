//
//  MIDI2ClientConfiguration.swift
//  MIDI2Kit
//
//  Configuration for MIDI2Client
//

import Foundation
import MIDI2Core
import MIDI2Transport

import MIDI2PE

// MARK: - ClientPreset

/// Preset configurations for common use cases
public enum ClientPreset: Sendable {
    /// Default configuration suitable for most applications
    case `default`
    
    /// Configuration optimized for device exploration/debugging
    case explorer
    
    /// Minimal configuration for quick testing
    case minimal
}

// MARK: - MIDI2ClientConfiguration

/// Configuration for MIDI2Client
///
/// ## Example
///
/// ```swift
/// // Use preset
/// let client = try MIDI2Client(name: "MyApp", preset: .explorer)
///
/// // Or customize
/// var config = MIDI2ClientConfiguration()
/// config.discoveryInterval = .seconds(3)
/// config.peTimeout = .seconds(10)
/// let client = try MIDI2Client(name: "MyApp", configuration: config)
/// ```
public struct MIDI2ClientConfiguration: Sendable {
    
    // MARK: - Discovery Settings
    
    /// How often to send Discovery Inquiry broadcasts
    ///
    /// Shorter intervals find devices faster but use more bandwidth.
    /// Default: 10 seconds
    public var discoveryInterval: Duration
    
    /// How long before a device is considered lost
    ///
    /// Should be at least 2-3x the discovery interval.
    /// Default: 60 seconds
    public var deviceTimeout: Duration
    
    /// Whether to automatically start discovery when `start()` is called
    ///
    /// Default: true
    public var autoStartDiscovery: Bool
    
    // MARK: - Property Exchange Settings
    
    /// Default timeout for PE requests
    ///
    /// Individual requests can override this.
    /// Default: 5 seconds
    public var peTimeout: Duration
    
    /// Maximum concurrent PE requests per device
    ///
    /// Lower values prevent overwhelming slow devices.
    /// Default: 2
    public var maxInflightPerDevice: Int
    
    /// Whether to fetch DeviceInfo before ResourceList as a "warm-up"
    ///
    /// Some devices (especially over BLE) benefit from a single-chunk
    /// request before multi-chunk requests. DeviceInfo is ideal for this
    /// because it's always single-chunk.
    ///
    /// Default: true (recommended for KORG and BLE devices)
    public var warmUpBeforeResourceList: Bool
    
    // MARK: - Resilience Settings
    
    /// Maximum number of retries for PE requests on timeout
    ///
    /// When a PE request times out, it will be retried up to this many times.
    /// Set to 0 to disable automatic retries.
    ///
    /// Default: 2 (total of 3 attempts)
    public var maxRetries: Int
    
    /// Delay between retry attempts
    ///
    /// A small delay can help recover from transient connection issues.
    ///
    /// Default: 100ms
    public var retryDelay: Duration
    
    /// Timeout multiplier for multi-chunk requests
    ///
    /// Multi-chunk responses (like ResourceList) may need more time.
    /// The base peTimeout is multiplied by this value for such requests.
    ///
    /// Default: 1.5 (e.g., 5s becomes 7.5s)
    public var multiChunkTimeoutMultiplier: Double
    
    // MARK: - Destination Resolution
    
    /// Strategy for resolving MUID to destination
    ///
    /// Default: `.preferModule` (optimized for KORG and similar devices)
    public var destinationStrategy: DestinationStrategy
    
    // MARK: - PE Send Strategy
    
    /// Strategy for sending PE requests
    ///
    /// Controls how PE requests are routed to destinations:
    /// - `.single`: Send to resolved destination only (most efficient)
    /// - `.broadcast`: Send to all destinations (most reliable, but may cause side effects)
    /// - `.fallback`: Try single first, broadcast on timeout (recommended)
    /// - `.learned`: Use only cached destinations
    ///
    /// Default: `.fallback` (recommended for KORG and BLE devices)
    public var peSendStrategy: PESendStrategy
    
    /// Timeout for each step in fallback strategy
    ///
    /// When using `.fallback` strategy, this is the timeout for each attempt
    /// before trying the next fallback.
    ///
    /// Default: 500ms
    public var fallbackStepTimeout: Duration
    
    /// Time-to-live for destination cache
    ///
    /// Cached destinations expire after this duration.
    /// Handles device reconnections where the destination may have changed.
    ///
    /// Default: 30 minutes (1800 seconds)
    public var destinationCacheTTL: Duration
    
    // MARK: - Advanced Settings
    
    /// Whether to respond to Discovery Inquiries (act as Responder)
    ///
    /// Default: false (most apps are Initiator-only)
    public var respondToDiscovery: Bool

    /// Whether to register devices from received Discovery Inquiry messages
    ///
    /// When `false` (default), only devices that respond to our Discovery Inquiry
    /// with a Discovery Reply are registered. This ensures that registered devices
    /// are actually capable of responding to our requests.
    ///
    /// When `true`, devices are also registered when they send Discovery Inquiry
    /// to us. This is useful for devices like KORG Module Pro that send Inquiry
    /// but don't respond to our Inquiry with a Reply.
    ///
    /// Default: false
    public var registerFromInquiry: Bool
    
    /// Whether to tolerate CI version mismatches
    ///
    /// Some devices (e.g., KORG) report CI 1.2 but send PE messages in CI 1.1 format.
    /// When enabled (default), the parser will try multiple format versions before failing.
    ///
    /// Default: true (recommended for maximum compatibility)
    public var tolerateCIVersionMismatch: Bool
    
    /// Maximum SysEx size (0 = no limit)
    ///
    /// Default: 0
    public var maxSysExSize: UInt32
    
    /// Device identity to advertise (if responding to discovery)
    public var deviceIdentity: DeviceIdentity
    
    /// Category support to advertise
    public var categorySupport: CategorySupport

    /// Logger for MIDI2Kit operations
    ///
    /// Default: NullMIDI2Logger() (silent)
    ///
    /// For debugging, use:
    /// ```swift
    /// let logger = OSLogMIDI2Logger(subsystem: "com.myapp.midi", minimumLevel: .debug)
    /// var config = MIDI2ClientConfiguration()
    /// config.logger = logger
    /// ```
    public var logger: any MIDI2Core.MIDI2Logger

    // MARK: - Initialization
    
    /// Create configuration with default values
    public init() {
        self.discoveryInterval = .seconds(10)
        self.deviceTimeout = .seconds(60)
        self.autoStartDiscovery = true
        self.peTimeout = .seconds(5)
        self.maxInflightPerDevice = 2
        self.warmUpBeforeResourceList = true
        self.maxRetries = 2
        self.retryDelay = .milliseconds(100)
        self.multiChunkTimeoutMultiplier = 1.5
        self.destinationStrategy = .preferModule
        self.peSendStrategy = .fallback
        self.fallbackStepTimeout = .milliseconds(500)
        self.destinationCacheTTL = .seconds(1800)
        self.respondToDiscovery = false
        self.registerFromInquiry = false
        self.tolerateCIVersionMismatch = true
        self.maxSysExSize = 0
        self.deviceIdentity = .default
        self.categorySupport = .propertyExchange
        self.logger = MIDI2Core.NullMIDI2Logger()
    }
    
    /// Create configuration from preset
    public init(preset: ClientPreset) {
        self.init()
        
        switch preset {
        case .default:
            // Use defaults
            break
            
        case .explorer:
            // More aggressive discovery for debugging
            self.discoveryInterval = .seconds(5)
            self.deviceTimeout = .seconds(120)
            self.peTimeout = .seconds(10)
            
        case .minimal:
            // Quick testing with short timeouts
            self.discoveryInterval = .seconds(3)
            self.deviceTimeout = .seconds(15)
            self.peTimeout = .seconds(3)
        }
    }
    
    // MARK: - Presets
    
    /// Default configuration
    public static let `default` = MIDI2ClientConfiguration()
    
    /// Explorer configuration (longer timeouts, faster discovery)
    public static let explorer = MIDI2ClientConfiguration(preset: .explorer)
    
    /// Minimal configuration (short timeouts)
    public static let minimal = MIDI2ClientConfiguration(preset: .minimal)
}
