//
//  PEManager+Batch.swift
//  MIDI2Kit
//
//  Batch request extension for PEManager
//

import Foundation
import MIDI2Core
import MIDI2Transport

// MARK: - Batch GET

extension PEManager {
    
    /// Fetch multiple resources in parallel
    ///
    /// This method executes multiple GET requests concurrently, respecting
    /// the `maxConcurrency` limit to avoid overwhelming the device.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let response = try await peManager.batchGet(
    ///     ["DeviceInfo", "ResourceList", "ProgramList"],
    ///     from: device
    /// )
    ///
    /// if let deviceInfo = response["DeviceInfo"]?.response {
    ///     print("Got DeviceInfo: \(deviceInfo.status)")
    /// }
    ///
    /// print("Success: \(response.successCount)/\(response.results.count)")
    /// ```
    ///
    /// - Parameters:
    ///   - resources: Array of resource names to fetch
    ///   - device: Target device handle
    ///   - options: Batch execution options
    /// - Returns: Batch response with results for each resource
    public func batchGet(
        _ resources: [String],
        from device: PEDeviceHandle,
        options: PEBatchOptions = .default
    ) async -> PEBatchResponse {
        var results: [String: PEBatchResult] = [:]
        
        // Execute with concurrency control using simple semaphore pattern
        let semaphore = BatchSemaphore(maxConcurrency: options.maxConcurrency)
        
        await withTaskGroup(of: (String, PEBatchResult).self) { group in
            for resource in resources {
                group.addTask { [self] in
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    
                    do {
                        let response = try await self.get(resource, from: device, timeout: options.timeout)
                        return (resource, .success(response))
                    } catch {
                        return (resource, .failure(error))
                    }
                }
            }
            
            for await (resource, result) in group {
                results[resource] = result
                
                // Check if we should stop on failure
                if !options.continueOnFailure, case .failure = result {
                    group.cancelAll()
                    break
                }
            }
        }
        
        return PEBatchResponse(results: results)
    }
    
    /// Fetch multiple resources in parallel (MUID-only)
    ///
    /// Requires `destinationResolver` to be configured.
    public func batchGet(
        _ resources: [String],
        from muid: MUID,
        options: PEBatchOptions = .default
    ) async throws -> PEBatchResponse {
        let device = try await resolveDeviceInternal(muid)
        return await batchGet(resources, from: device, options: options)
    }
    
    /// Fetch multiple channel-specific resources in parallel
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Get program info for channels 0-15
    /// let channels = Array(0..<16)
    /// let response = try await peManager.batchGetChannels(
    ///     "ProgramInfo",
    ///     channels: channels,
    ///     from: device
    /// )
    /// ```
    public func batchGetChannels(
        _ resource: String,
        channels: [Int],
        from device: PEDeviceHandle,
        options: PEBatchOptions = .default
    ) async -> PEBatchResponse {
        var results: [String: PEBatchResult] = [:]
        let semaphore = BatchSemaphore(maxConcurrency: options.maxConcurrency)
        
        await withTaskGroup(of: (String, PEBatchResult).self) { group in
            for channel in channels {
                let key = "\(resource)[\(channel)]"
                group.addTask { [self] in
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    
                    do {
                        let response = try await self.get(resource, channel: channel, from: device, timeout: options.timeout)
                        return (key, .success(response))
                    } catch {
                        return (key, .failure(error))
                    }
                }
            }
            
            for await (key, result) in group {
                results[key] = result
                
                if !options.continueOnFailure, case .failure = result {
                    group.cancelAll()
                    break
                }
            }
        }
        
        return PEBatchResponse(results: results)
    }
    
    // MARK: - Batch SET

    /// Set multiple resources in parallel
    ///
    /// This method executes multiple SET requests concurrently, respecting
    /// the `maxConcurrency` limit to avoid overwhelming the device.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let items = [
    ///     try PESetItem.json(resource: "Volume", value: ["level": 100]),
    ///     try PESetItem.json(resource: "Pan", value: ["position": 64]),
    ///     try PESetItem.json(resource: "Reverb", value: ["amount": 50])
    /// ]
    ///
    /// let response = await peManager.batchSet(items, to: device)
    ///
    /// if response.allSucceeded {
    ///     print("All \(response.successCount) settings applied")
    /// } else {
    ///     for (resource, error) in response.failures {
    ///         print("\(resource) failed: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - items: Array of SET items
    ///   - device: Target device handle
    ///   - options: Batch execution options
    /// - Returns: Batch response with results for each resource
    public func batchSet(
        _ items: [PESetItem],
        to device: PEDeviceHandle,
        options: PEBatchSetOptions = .default
    ) async -> PEBatchSetResponse {
        var results: [String: PEBatchResult] = [:]

        // Validate payloads if requested
        if options.validatePayloads, let registry = payloadValidatorRegistry {
            for item in items {
                do {
                    try await registry.validate(item.data, for: item.resource)
                } catch let validationError as PEPayloadValidationError {
                    results[item.resource] = .failure(PEError.payloadValidationFailed(validationError))
                    if options.stopOnFirstFailure {
                        return PEBatchSetResponse(results: results)
                    }
                } catch {
                    // Unexpected error during validation - wrap in a generic validation error
                    results[item.resource] = .failure(PEError.payloadValidationFailed(
                        .customValidation("Validation threw unexpected error: \(error)")
                    ))
                    if options.stopOnFirstFailure {
                        return PEBatchSetResponse(results: results)
                    }
                }
            }
            // If validation failed for any and we're continuing, filter out failed items
            let validItems = items.filter { results[$0.resource] == nil }
            if validItems.isEmpty {
                return PEBatchSetResponse(results: results)
            }
        }

        // Filter to items not already failed in validation
        let itemsToProcess = items.filter { results[$0.resource] == nil }

        // Execute with concurrency control
        let semaphore = BatchSemaphore(maxConcurrency: options.maxConcurrency)

        await withTaskGroup(of: (String, PEBatchResult).self) { group in
            for item in itemsToProcess {
                group.addTask { [self] in
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    do {
                        let response: PEResponse
                        if let channel = item.channel {
                            response = try await self.set(
                                item.resource,
                                data: item.data,
                                channel: channel,
                                to: device,
                                timeout: options.timeout
                            )
                        } else {
                            response = try await self.set(
                                item.resource,
                                data: item.data,
                                to: device,
                                timeout: options.timeout
                            )
                        }
                        return (item.resource, .success(response))
                    } catch {
                        return (item.resource, .failure(error))
                    }
                }
            }

            for await (resource, result) in group {
                results[resource] = result

                // Check if we should stop on failure
                if options.stopOnFirstFailure, case .failure = result {
                    group.cancelAll()
                    break
                }
            }
        }

        return PEBatchSetResponse(results: results)
    }

    /// Set multiple resources in parallel (MUID-only)
    ///
    /// Requires `destinationResolver` to be configured.
    public func batchSet(
        _ items: [PESetItem],
        to muid: MUID,
        options: PEBatchSetOptions = .default
    ) async throws -> PEBatchSetResponse {
        let device = try await resolveDeviceInternal(muid)
        return await batchSet(items, to: device, options: options)
    }

    /// Set multiple channel-specific values in parallel
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Set volume to 100 on channels 0-7
    /// let volumeData = try JSONEncoder().encode(["level": 100])
    /// let response = await peManager.batchSetChannels(
    ///     "Volume",
    ///     data: volumeData,
    ///     channels: Array(0..<8),
    ///     to: device
    /// )
    /// ```
    public func batchSetChannels(
        _ resource: String,
        data: Data,
        channels: [Int],
        to device: PEDeviceHandle,
        options: PEBatchSetOptions = .default
    ) async -> PEBatchSetResponse {
        var results: [String: PEBatchResult] = [:]
        let semaphore = BatchSemaphore(maxConcurrency: options.maxConcurrency)

        await withTaskGroup(of: (String, PEBatchResult).self) { group in
            for channel in channels {
                let key = "\(resource)[\(channel)]"
                group.addTask { [self] in
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    do {
                        let response = try await self.set(
                            resource,
                            data: data,
                            channel: channel,
                            to: device,
                            timeout: options.timeout
                        )
                        return (key, .success(response))
                    } catch {
                        return (key, .failure(error))
                    }
                }
            }

            for await (key, result) in group {
                results[key] = result

                if options.stopOnFirstFailure, case .failure = result {
                    group.cancelAll()
                    break
                }
            }
        }

        return PEBatchSetResponse(results: results)
    }

    // MARK: - Private

    /// Internal device resolver (avoiding duplicate code)
    private func resolveDeviceInternal(_ muid: MUID) async throws -> PEDeviceHandle {
        guard let resolver = destinationResolver else {
            throw PEError.deviceNotFound(muid)
        }
        guard let destination = await resolver(muid) else {
            throw PEError.deviceNotFound(muid)
        }
        return PEDeviceHandle(muid: muid, destination: destination)
    }
}

// MARK: - Typed Batch API

extension PEManager {
    
    /// Fetch multiple resources and decode as specific types
    ///
    /// ## Example
    ///
    /// ```swift
    /// let (deviceInfo, resourceList) = try await peManager.batchGetTyped(
    ///     from: device,
    ///     ("DeviceInfo", PEDeviceInfo.self),
    ///     ("ResourceList", [PEResourceEntry].self)
    /// )
    /// ```
    public func batchGetTyped<T1: Decodable & Sendable, T2: Decodable & Sendable>(
        from device: PEDeviceHandle,
        _ r1: (String, T1.Type),
        _ r2: (String, T2.Type),
        timeout: Duration = .seconds(5)
    ) async throws -> (T1, T2) {
        let resource1 = r1.0
        let resource2 = r2.0
        
        async let v1: T1 = getJSON(resource1, from: device, timeout: timeout)
        async let v2: T2 = getJSON(resource2, from: device, timeout: timeout)
        return try await (v1, v2)
    }
    
    /// Fetch 3 resources with specific types
    public func batchGetTyped<T1: Decodable & Sendable, T2: Decodable & Sendable, T3: Decodable & Sendable>(
        from device: PEDeviceHandle,
        _ r1: (String, T1.Type),
        _ r2: (String, T2.Type),
        _ r3: (String, T3.Type),
        timeout: Duration = .seconds(5)
    ) async throws -> (T1, T2, T3) {
        let resource1 = r1.0
        let resource2 = r2.0
        let resource3 = r3.0
        
        async let v1: T1 = getJSON(resource1, from: device, timeout: timeout)
        async let v2: T2 = getJSON(resource2, from: device, timeout: timeout)
        async let v3: T3 = getJSON(resource3, from: device, timeout: timeout)
        return try await (v1, v2, v3)
    }
    
    /// Fetch 4 resources with specific types
    public func batchGetTyped<T1: Decodable & Sendable, T2: Decodable & Sendable, T3: Decodable & Sendable, T4: Decodable & Sendable>(
        from device: PEDeviceHandle,
        _ r1: (String, T1.Type),
        _ r2: (String, T2.Type),
        _ r3: (String, T3.Type),
        _ r4: (String, T4.Type),
        timeout: Duration = .seconds(5)
    ) async throws -> (T1, T2, T3, T4) {
        let resource1 = r1.0
        let resource2 = r2.0
        let resource3 = r3.0
        let resource4 = r4.0
        
        async let v1: T1 = getJSON(resource1, from: device, timeout: timeout)
        async let v2: T2 = getJSON(resource2, from: device, timeout: timeout)
        async let v3: T3 = getJSON(resource3, from: device, timeout: timeout)
        async let v4: T4 = getJSON(resource4, from: device, timeout: timeout)
        return try await (v1, v2, v3, v4)
    }
}

// MARK: - Batch Semaphore

/// Simple actor-based semaphore for concurrency control
private actor BatchSemaphore {
    private let maxConcurrency: Int
    private var currentCount: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(maxConcurrency: Int) {
        self.maxConcurrency = max(1, maxConcurrency)
    }
    
    func wait() async {
        if currentCount < maxConcurrency {
            currentCount += 1
            return
        }
        
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    func signal() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            currentCount = max(0, currentCount - 1)
        }
    }
}
