//
//  MIDI2CI.swift
//  MIDI2Kit
//
//  MIDI Capability Inquiry (MIDI-CI) implementation
//

/// # MIDI2CI
///
/// MIDI Capability Inquiry protocol implementation for device discovery and management.
///
/// ## Overview
///
/// MIDI2CI implements the MIDI-CI specification for discovering and communicating with
/// MIDI 2.0 devices. Key features include:
///
/// - **Device Discovery**: Automatic discovery of MIDI-CI capable devices
/// - **Lifecycle Management**: Track device connections, updates, and disconnections
/// - **Message Building**: Construct MIDI-CI SysEx messages
/// - **Message Parsing**: Parse incoming MIDI-CI responses
///
/// ## Device Discovery
///
/// ```swift
/// import MIDI2CI
///
/// // Create and configure CI manager
/// let config = CIManagerConfiguration(
///     discoveryInterval: 5.0,      // Send Discovery every 5 seconds
///     deviceTimeout: 15.0,         // Mark device lost after 15 seconds
///     categorySupport: .propertyExchange
/// )
///
/// let ciManager = CIManager(
///     transport: transport,
///     configuration: config
/// )
///
/// // Start discovery
/// try await ciManager.start()
///
/// // Listen for events
/// for await event in ciManager.events {
///     switch event {
///     case .deviceDiscovered(let device):
///         print("Found: \(device.displayName)")
///         print("MUID: \(device.muid)")
///         print("Supports PE: \(device.supportsPropertyExchange)")
///         
///     case .deviceLost(let muid):
///         print("Lost device: \(muid)")
///         
///     case .deviceUpdated(let device):
///         print("Updated: \(device.displayName)")
///         
///     default:
///         break
///     }
/// }
/// ```
///
/// ## Finding Device Destinations
///
/// MIDI-CI requires bidirectional communication. Use `destination(for:)` to find
/// the correct output endpoint for a discovered device:
///
/// ```swift
/// if let destination = await ciManager.destination(for: device.muid) {
///     // Create PE device handle
///     let handle = PEDeviceHandle(
///         muid: device.muid,
///         destination: destination,
///         name: device.displayName
///     )
///     
///     // Now you can use Property Exchange
///     let response = try await peManager.get("DeviceInfo", from: handle)
/// }
/// ```
///
/// ## Building MIDI-CI Messages
///
/// ```swift
/// // Discovery Inquiry (broadcast)
/// let inquiry = CIMessageBuilder.discoveryInquiry(
///     sourceMUID: muid,
///     deviceIdentity: .default,
///     categorySupport: .propertyExchange
/// )
///
/// // PE Get Inquiry
/// let getInquiry = CIMessageBuilder.peGetInquiry(
///     sourceMUID: muid,
///     destinationMUID: targetMUID,
///     requestID: requestID,
///     headerData: CIMessageBuilder.resourceRequestHeader(resource: "DeviceInfo")
/// )
/// ```
///
/// ## Parsing MIDI-CI Messages
///
/// ```swift
/// if let parsed = CIMessageParser.parse(sysexData) {
///     switch parsed.messageType {
///     case .discoveryReply:
///         if let reply = CIMessageParser.parseDiscoveryReply(parsed.payload) {
///             print("Device: \(reply.identity)")
///         }
///         
///     case .peGetReply:
///         if let reply = CIMessageParser.parsePEReply(parsed.payload) {
///             print("Data: \(reply.propertyData)")
///         }
///         
///     default:
///         break
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Device Management
/// - ``CIManager``
/// - ``CIManagerConfiguration``
/// - ``CIManagerEvent``
/// - ``DiscoveredDevice``
///
/// ### Message Building
/// - ``CIMessageBuilder``
///
/// ### Message Parsing
/// - ``CIMessageParser``

@_exported import MIDI2Core
