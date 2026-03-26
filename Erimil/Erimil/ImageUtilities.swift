//
//  ImageUtilities.swift
//  Erimil
//
//  Shared image processing utilities
//  Created: S053 (2026-02-23) - #134 P6: CGImageSource thumbnail generation
//

import Foundation
import AppKit
import ImageIO
import os

/// Shared image processing utilities
enum ImageUtilities {
    
    /// Generate a downsampled thumbnail from image data in a single pass.
    ///
    /// Uses `CGImageSourceCreateThumbnailAtIndex` to decode and resize simultaneously,
    /// avoiding full-resolution bitmap allocation. ~40x faster than NSImage.lockFocus
    /// for typical JPEG images (16ms vs 628ms benchmark).
    ///
    /// The resulting image is fully materialized in memory — no progressive/lazy
    /// decoding, so SwiftUI displays it instantly without top-to-bottom drawing.
    ///
    /// - Parameters:
    ///   - data: Raw image data (JPEG, PNG, etc.)
    ///   - maxSize: Maximum pixel dimension for the longest edge
    /// - Returns: Downsampled NSImage, or nil if data is invalid
    static func downsampledThumbnail(from data: Data, maxSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return createThumbnail(from: source, maxSize: maxSize)
    }
    
    /// Generate a downsampled thumbnail from a file URL in a single pass.
    ///
    /// More efficient than loading Data first — ImageIO can memory-map the file.
    ///
    /// - Parameters:
    ///   - url: File URL of the image
    ///   - maxSize: Maximum pixel dimension for the longest edge
    /// - Returns: Downsampled NSImage, or nil if file is invalid
    static func downsampledThumbnail(from url: URL, maxSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return createThumbnail(from: source, maxSize: maxSize)
    }
    
    // MARK: - Private
    
    /// Load an image from disk and force complete pixel decode.
    ///
    /// Used for disk cache reads where the image is already at thumbnail size.
    /// `NSImage(contentsOf:)` creates a lazily-decoded image that SwiftUI renders
    /// progressively (top-to-bottom). This method forces full decode via CGContext.
    ///
    /// - Parameter url: File URL of the cached image
    /// - Returns: Fully materialized NSImage, or nil if file is invalid
    static func loadAndMaterialize(from url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        return materializeBitmap(cgImage)
    }
    
    /// Create a fully materialized full-size image from raw data.
    ///
    /// Used by fullImage() to prevent progressive rendering in Viewer/Slide Mode.
    /// Decodes all pixels via CGContext before returning.
    ///
    /// - Parameter data: Raw image data (JPEG, PNG, etc.)
    /// - Returns: Fully decoded NSImage at original resolution, or nil if invalid
    static func materializedImage(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        return materializeBitmap(cgImage)
    }
    
    /// Create a fully materialized full-size image from a file URL.
    ///
    /// Used by fullImage() for folder sources. Memory-maps the file for efficiency.
    ///
    /// - Parameter url: File URL of the image
    /// - Returns: Fully decoded NSImage at original resolution, or nil if invalid
    static func materializedImage(from url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        return materializeBitmap(cgImage)
    }
    
    /// Core thumbnail generation from CGImageSource
    private static func createThumbnail(from source: CGImageSource, maxSize: CGFloat) -> NSImage? {
        let t0 = CFAbsoluteTimeGetCurrent()
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // Apply EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,         // Hint to decode eagerly
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ]
        
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        let t1 = CFAbsoluteTimeGetCurrent()
        
        // Force full bitmap materialization: draw into CGContext so all pixels
        // are decoded before returning. Without this, SwiftUI may render the
        // image progressively (top-to-bottom visible drawing).
        let result = materializeBitmap(cgThumb, scaleFactor: AppSettings.shared.displayScaleFactor)
        
        let t2 = CFAbsoluteTimeGetCurrent()
        let thumbMs = (t1 - t0) * 1000
        let matMs = (t2 - t1) * 1000
        let totalMs = (t2 - t0) * 1000
        Logger.thumbnailGrid.debug("★PERF★ CGImageSource: thumb=\(String(format: "%.1f", thumbMs))ms materialize=\(String(format: "%.1f", matMs))ms total=\(String(format: "%.1f", totalMs))ms size=\(cgThumb.width)x\(cgThumb.height)")
        
        return result
    }
    
    /// Draw CGImage into a fresh bitmap context to force complete pixel decode.
    /// Returns an NSImage backed by fully-rendered pixel data.
    private static func materializeBitmap(_ cgImage: CGImage, scaleFactor: CGFloat = 1.0) -> NSImage? {
        let width = cgImage.width
        let height = cgImage.height
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,    // Let Core Graphics calculate optimal stride
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            // Fallback: return without materialization
            return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(width) / scaleFactor, height: CGFloat(height) / scaleFactor))
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let materialized = context.makeImage() else {
            return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(width) / scaleFactor, height: CGFloat(height) / scaleFactor))
        }
        
        return NSImage(cgImage: materialized, size: NSSize(width: CGFloat(width) / scaleFactor, height: CGFloat(height) / scaleFactor))
    }
}
