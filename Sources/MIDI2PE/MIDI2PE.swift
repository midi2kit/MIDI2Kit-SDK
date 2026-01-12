//
//  MIDI2PE.swift
//  MIDI2Kit
//
//  Property Exchange implementation
//

/// # MIDI2PE
///
/// Property Exchange (PE) implementation for reading and writing device properties.
///
/// ## Overview
///
/// MIDI2PE provides a complete Property Exchange implementation including:
///
/// - **GET/SET Operations**: Read and write device properties
/// - **Pagination**: Handle large resource lists
/// - **Subscriptions**: Receive notifications when properties change
/// - **Transaction Management**: Automatic request ID and timeout handling
/// - **Per-device Rate Limiting**: Prevent overwhelming slow devices
///
/// ## Basic Usage
///
/// ```swift
/// import MIDI2PE
///
/// // Create PE manager
/// let peManager = PEManager(
///     transport: transport,
///     sourceMUID: ciManager.muid
/// )
/// await peManager.startReceiving()
///
/// // Create device handle
/// let handle = PEDeviceHandle(
///     muid: device.muid,
///     destination: destination
/// )
///
/// // GET request
/// let response = try await peManager.get("DeviceInfo", from: handle)
/// let deviceInfo = try JSONDecoder().decode(PEDeviceInfo.self, from: response.decodedBody)
/// print("Product: \(deviceInfo.productName ?? "Unknown")")
///
/// // SET request
/// let data = try JSONEncoder().encode(["value": 42])
/// let setResponse = try await peManager.set("Parameter", data: data, to: handle)
/// ```
///
/// ## Channel-Specific Resources
///
/// ```swift
/// // Get program info for channel 0
/// let response = try await peManager.get(
///     "ProgramInfo",
///     channel: 0,
///     from: handle
/// )
///
/// // Set program for channel 5
/// try await peManager.set(
///     "CurrentProgram",
///     data: programData,
///     channel: 5,
///     to: handle
/// )
/// ```
///
/// ## Pagination
///
/// ```swift
/// // Get first 10 programs
/// let response = try await peManager.get(
///     "ProgramList",
///     offset: 0,
///     limit: 10,
///     from: handle
/// )
///
/// // Check for more
/// if let header = response.header,
///    let total = header.totalCount,
///    total > 10 {
///     // Fetch more pages...
/// }
/// ```
///
/// ## Batch Requests
///
/// ```swift
/// // Fetch multiple resources in parallel
/// let response = await peManager.batchGet(
///     ["DeviceInfo", "ResourceList", "ProgramList"],
///     from: handle
/// )
///
/// // Check results
/// for (resource, result) in response.results {
///     switch result {
///     case .success(let response):
///         print("\(resource): \(response.status)")
///     case .failure(let error):
///         print("\(resource) failed: \(error)")
///     }
/// }
///
/// // Type-safe batch
/// let (deviceInfo, resourceList) = try await peManager.batchGetTyped(
///     from: handle,
///     ("DeviceInfo", PEDeviceInfo.self),
///     ("ResourceList", [PEResourceEntry].self)
/// )
/// ```
///
/// ## Subscriptions
///
/// ```swift
/// // Subscribe to property changes
/// try await peManager.subscribe(to: "ProgramList", on: handle)
///
/// // Receive notifications
/// for await notification in peManager.notifications {
///     print("Changed: \(notification.resource)")
///     print("Data: \(notification.data)")
/// }
///
/// // Unsubscribe
/// try await peManager.unsubscribe(subscribeId: subscribeId, from: handle)
/// ```
///
/// ## Auto-Reconnecting Subscriptions
///
/// ```swift
/// // Use PESubscriptionManager for robust subscriptions
/// let subscriptionManager = PESubscriptionManager(
///     peManager: peManager,
///     ciManager: ciManager
/// )
/// await subscriptionManager.start()
///
/// // Subscribe with device identity for matching after reconnection
/// try await subscriptionManager.subscribe(
///     to: "ProgramList",
///     on: device.muid,
///     identity: device.identity
/// )
///
/// // Handle events
/// for await event in subscriptionManager.events {
///     switch event {
///     case .notification(let notification):
///         print("Data changed")
///     case .suspended(_, let reason):
///         print("Subscription suspended: \(reason)")
///     case .restored(_, _):
///         print("Subscription restored!")
///     case .failed(_, let reason):
///         print("Subscription failed: \(reason)")
///     default:
///         break
///     }
/// }
/// ```
///
/// ## Error Handling
///
/// ```swift
/// do {
///     let response = try await peManager.get("DeviceInfo", from: handle)
/// } catch PEError.timeout(let resource) {
///     print("Timeout fetching \(resource)")
/// } catch PEError.deviceError(let status, let message) {
///     print("Device error \(status): \(message ?? "Unknown")")
/// } catch PEError.nak(let details) {
///     print("NAK: \(details.statusCode)")
///     if details.isTransient {
///         // Retry might succeed
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### High-Level API
/// - ``PEManager``
/// - ``PEDeviceHandle``
/// - ``PERequest``
/// - ``PEResponse``
///
/// ### Subscriptions
/// - ``PESubscriptionManager``
/// - ``PESubscription``
/// - ``PENotification``
///
/// ### Transaction Management
/// - ``PETransactionManager``
/// - ``PERequestIDManager``
/// - ``PEChunkAssembler``
///
/// ### Resource Types
/// - ``PEResource``
/// - ``PEDeviceInfo``
/// - ``PEControllerDef``
/// - ``PEProgramDef``
/// - ``PEChannelInfo``
///
/// ### Errors
/// - ``PEError``
/// - ``PERequestError``
/// - ``PENAKDetails``

@_exported import MIDI2Core
@_exported import MIDI2CI
