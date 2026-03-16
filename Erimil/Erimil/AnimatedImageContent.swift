// MARK: - AnimatedImageContent.swift
// #201 Phase 1: Animated GIF Playback
// GIF frame data model + CGImageSource-based decoder

import Foundation
import CoreGraphics
import ImageIO

struct AnimatedImageContent {

    struct Frame {
        let image: CGImage
        let duration: TimeInterval
    }

    let frames: [Frame]
    let loopCount: Int          // 0 = infinite (GIF spec default)
    let totalDuration: TimeInterval

    var frameCount: Int { frames.count }

    // MARK: - Safety Limits

    static let maxFrameCount = 500
    static let maxMemoryBytes = 100 * 1024 * 1024  // 100 MB

    // MARK: - Decode (URL)

    /// Full decode of animated GIF from file URL.
    /// Returns nil if not multi-frame or exceeds safety limits.
    static func decode(from url: URL) -> AnimatedImageContent? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return decodeSource(source)
    }

    // MARK: - Decode (Data)

    /// Full decode of animated GIF from in-memory data (for ZIP archives).
    /// Returns nil if not multi-frame or exceeds safety limits.
    static func decode(from data: Data) -> AnimatedImageContent? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return decodeSource(source)
    }

    // MARK: - Lightweight Check

    /// Returns true if URL points to a multi-frame image. Does NOT fully decode.
    static func isAnimated(url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    /// Returns true if data contains a multi-frame image. Does NOT fully decode.
    static func isAnimated(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    // MARK: - Shared Decode Logic

    private static func decodeSource(_ source: CGImageSource) -> AnimatedImageContent? {
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }
        guard count <= maxFrameCount else { return nil }

        let loopCount = gifLoopCount(from: source)

        var frames: [Frame] = []
        frames.reserveCapacity(count)
        var totalMemory = 0
        var totalDuration: TimeInterval = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

            let bytesPerFrame = cgImage.bytesPerRow * cgImage.height
            totalMemory += bytesPerFrame
            if totalMemory > maxMemoryBytes { return nil }

            let delay = frameDelay(at: i, source: source)
            frames.append(Frame(image: cgImage, duration: delay))
            totalDuration += delay
        }

        guard frames.count > 1 else { return nil }

        return AnimatedImageContent(
            frames: frames,
            loopCount: loopCount,
            totalDuration: totalDuration
        )
    }

    // MARK: - Private Helpers

    private static func frameDelay(at index: Int, source: CGImageSource) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }

        // Prefer unclamped delay, then clamped delay
        if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval, unclamped > 0 {
            return max(unclamped, 0.02)  // Floor at 20ms (browser convention ~10-20ms)
        }
        if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? TimeInterval, delay > 0 {
            return max(delay, 0.02)
        }

        return 0.1  // Fallback: 100ms
    }

    private static func gifLoopCount(from source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
              let count = gifDict[kCGImagePropertyGIFLoopCount] as? Int else {
            return 0  // Default: infinite
        }
        return count
    }
}
