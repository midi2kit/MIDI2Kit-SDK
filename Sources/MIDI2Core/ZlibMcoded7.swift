//
//  ZlibMcoded7.swift
//  MIDI2Kit
//
//  zlib compression + Mcoded7 encoding for Property Exchange
//

import Foundation
import Compression

/// zlib compression combined with Mcoded7 encoding for Property Exchange
///
/// MIDI-CI 1.2 Section 5.10.3 specifies three encoding options for PE data:
/// - ASCII (7-bit safe text)
/// - Mcoded7 (8-bit binary data)
/// - zlib + Mcoded7 (compressed 8-bit binary data)
///
/// This type provides the third option: zlib compression followed by Mcoded7 encoding.
///
/// ## Usage
///
/// ```swift
/// // Encode (compress + Mcoded7)
/// let largeJSON = jsonData  // Could be several KB
/// if let encoded = ZlibMcoded7.encode(largeJSON) {
///     // Send as PE body with mutualEncoding = "Mcoded7+zlib"
/// }
///
/// // Decode (Mcoded7 + decompress)
/// if let decoded = ZlibMcoded7.decode(receivedData) {
///     // Process original data
/// }
/// ```
///
/// ## When to Use
///
/// zlib+Mcoded7 is beneficial when:
/// - The data is large (>1KB recommended)
/// - The data is compressible (JSON, text, repeated patterns)
/// - Both initiator and responder support the encoding
///
/// For small data (<1KB), plain Mcoded7 may be more efficient due to zlib overhead.
///
/// ## Interoperability Note
///
/// Not all MIDI-CI implementations support zlib encoding. Always check the device's
/// supported encodings before using this format. When in doubt, use plain Mcoded7.
public enum ZlibMcoded7 {

    /// Compression algorithm to use
    ///
    /// MIDI-CI specifies zlib (deflate) compression.
    private static let algorithm = COMPRESSION_ZLIB

    /// Minimum size to consider compression worthwhile
    ///
    /// Below this threshold, compression overhead may exceed savings.
    public static let minimumSizeForCompression: Int = 256

    // MARK: - Encoding (Compress + Mcoded7)

    /// Encode data using zlib compression followed by Mcoded7 encoding
    ///
    /// - Parameter data: Original 8-bit data to encode
    /// - Returns: Mcoded7-encoded zlib-compressed data, or nil if compression fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// let jsonData = try JSONEncoder().encode(resourceList)
    /// if let encoded = ZlibMcoded7.encode(jsonData) {
    ///     // encoded is 7-bit safe and compressed
    ///     print("Compression ratio: \(Float(jsonData.count) / Float(encoded.count))")
    /// }
    /// ```
    public static func encode(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }

        // Step 1: Compress with zlib
        guard let compressed = compress(data) else {
            return nil
        }

        // Step 2: Encode with Mcoded7
        return Mcoded7.encode(compressed)
    }

    /// Encode data, falling back to plain Mcoded7 if compression is not beneficial
    ///
    /// - Parameter data: Original 8-bit data to encode
    /// - Returns: Tuple of (encoded data, wasCompressed flag)
    ///
    /// This method compares the compressed size to the original and returns
    /// whichever is smaller. Use the `wasCompressed` flag to set the appropriate
    /// `mutualEncoding` header value.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let (encoded, wasCompressed) = ZlibMcoded7.encodeWithFallback(data)
    /// let encoding = wasCompressed ? "Mcoded7+zlib" : "Mcoded7"
    /// ```
    public static func encodeWithFallback(_ data: Data) -> (data: Data, wasCompressed: Bool) {
        guard !data.isEmpty else { return (Data(), false) }

        // Try compression
        if data.count >= minimumSizeForCompression,
           let compressed = compress(data) {
            let compressedMcoded7 = Mcoded7.encode(compressed)
            let plainMcoded7 = Mcoded7.encode(data)

            // Use compressed version only if it's smaller
            if compressedMcoded7.count < plainMcoded7.count {
                return (compressedMcoded7, true)
            }
        }

        // Fall back to plain Mcoded7
        return (Mcoded7.encode(data), false)
    }

    // MARK: - Decoding (Mcoded7 + Decompress)

    /// Decode Mcoded7-encoded zlib-compressed data
    ///
    /// - Parameter data: Mcoded7-encoded compressed data
    /// - Returns: Original uncompressed data, or nil if decoding/decompression fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Received PE response with mutualEncoding = "Mcoded7+zlib"
    /// if let decoded = ZlibMcoded7.decode(response.body) {
    ///     let resourceList = try JSONDecoder().decode([Resource].self, from: decoded)
    /// }
    /// ```
    public static func decode(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }

        // Step 1: Decode Mcoded7
        guard let compressed = Mcoded7.decode(data) else {
            return nil
        }

        // Step 2: Decompress zlib
        return decompress(compressed)
    }

    // MARK: - Size Estimation

    /// Estimate encoded size for given input size
    ///
    /// This is a rough estimate. Actual size depends on data compressibility.
    /// For incompressible data, the result may be larger than the original.
    ///
    /// - Parameter originalSize: Size of original data
    /// - Returns: Estimated encoded size (assuming 50% compression ratio)
    public static func estimatedEncodedSize(for originalSize: Int) -> Int {
        // Assume 50% compression ratio as a rough estimate
        let estimatedCompressed = originalSize / 2
        return Mcoded7.encodedSize(for: max(estimatedCompressed, 10))
    }

    // MARK: - Private Compression Helpers

    /// Compress data using zlib
    private static func compress(_ data: Data) -> Data? {
        // Allocate destination buffer
        // zlib typically achieves 50-80% compression on text, but can expand incompressible data
        let destinationBufferSize = max(data.count + 64, data.count * 2)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }

            return compression_encode_buffer(
                destinationBuffer,
                destinationBufferSize,
                sourcePtr,
                data.count,
                nil,
                algorithm
            )
        }

        guard compressedSize > 0 else { return nil }

        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    /// Decompress zlib data
    private static func decompress(_ data: Data) -> Data? {
        // Allocate destination buffer - decompressed data can be much larger
        // Start with a reasonable estimate and grow if needed
        var destinationBufferSize = max(data.count * 4, 1024)

        while destinationBufferSize <= 100_000_000 { // 100MB max to prevent memory exhaustion
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
            defer { destinationBuffer.deallocate() }

            let decompressedSize = data.withUnsafeBytes { sourceBuffer -> Int in
                guard let sourcePtr = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }

                return compression_decode_buffer(
                    destinationBuffer,
                    destinationBufferSize,
                    sourcePtr,
                    data.count,
                    nil,
                    algorithm
                )
            }

            if decompressedSize > 0 && decompressedSize < destinationBufferSize {
                // Success - copy data and return
                return Data(bytes: destinationBuffer, count: decompressedSize)
            } else if decompressedSize == destinationBufferSize {
                // Buffer may be too small, try larger
                destinationBufferSize *= 2
                continue
            } else {
                // Decompression failed
                return nil
            }
        }

        // Data too large
        return nil
    }
}

// MARK: - Compression Statistics

extension ZlibMcoded7 {

    /// Statistics from a compression operation
    public struct CompressionStats: Sendable {
        /// Original data size
        public let originalSize: Int

        /// Size after zlib compression
        public let compressedSize: Int

        /// Size after Mcoded7 encoding
        public let encodedSize: Int

        /// Compression ratio (original / compressed)
        public var compressionRatio: Double {
            guard compressedSize > 0 else { return 0 }
            return Double(originalSize) / Double(compressedSize)
        }

        /// Overall encoding ratio (original / encoded)
        public var overallRatio: Double {
            guard encodedSize > 0 else { return 0 }
            return Double(originalSize) / Double(encodedSize)
        }

        /// Whether compression was beneficial
        public var isBeneficial: Bool {
            encodedSize < Mcoded7.encodedSize(for: originalSize)
        }
    }

    /// Encode data and return compression statistics
    ///
    /// - Parameter data: Data to encode
    /// - Returns: Tuple of encoded data and statistics, or nil if encoding fails
    public static func encodeWithStats(_ data: Data) -> (data: Data, stats: CompressionStats)? {
        guard !data.isEmpty else {
            return (Data(), CompressionStats(originalSize: 0, compressedSize: 0, encodedSize: 0))
        }

        guard let compressed = compress(data) else {
            return nil
        }

        let encoded = Mcoded7.encode(compressed)

        let stats = CompressionStats(
            originalSize: data.count,
            compressedSize: compressed.count,
            encodedSize: encoded.count
        )

        return (encoded, stats)
    }
}
