//
//  ArchiveManager.swift
//  Erimil
//
//  ImageSource implementation for ZIP archives
//  Reference: https://github.com/weichsel/ZIPFoundation#closure-based-reading-and-writing
//

import Foundation
import ZIPFoundation
import AppKit
import os

class ArchiveManager: ImageSource {
    let url: URL
    let sourceType: ImageSourceType = .archive
    
    // Serial queue for thread-safe archive access
    private let accessQueue = DispatchQueue(label: "com.erimil.archive", qos: .userInitiated)
    
    // Convenience alias
    var zipURL: URL { url }
    
    /// Cached encoding detection result
    private var detectedEncoding: ZIPEncodingDetector.DetectedEncoding?
    
    init(zipURL: URL) {
        self.url = zipURL
    }
    
    // MARK: - Archive Opening with Encoding Detection
    
    /// Open archive with appropriate encoding based on detection
    private func openArchive() -> Archive? {
        // Detect encoding on first access, cache result
        if detectedEncoding == nil {
            detectedEncoding = ZIPEncodingDetector.detect(for: url)
        }
        
        do {
            switch detectedEncoding {
            case .shiftJIS:
                Logger.archive.debug("Opening with Shift_JIS encoding")
                return try Archive(url: url, accessMode: .read, pathEncoding: .shiftJIS)
            case .utf8:
                Logger.archive.debug("Opening with UTF-8 encoding")
                return try Archive(url: url, accessMode: .read, pathEncoding: .utf8)
            case .unknown, .none:
                Logger.archive.debug("Opening with default encoding")
                return try Archive(url: url, accessMode: .read)
            }
        } catch {
            Logger.archive.error("Failed to open archive: \(error, privacy: .public)")
            return nil
        }
    }
    
    /// Get String.Encoding based on detected encoding
    private func getPathEncoding() -> String.Encoding? {
        switch detectedEncoding {
        case .utf8:
            return .utf8
        case .shiftJIS:
            return .shiftJIS
        case .unknown, .none:
            return nil
        }
    }
    
    /// List all image entries in the ZIP
    func listImageEntries() -> [ImageEntry] {
        return accessQueue.sync {
            Logger.archive.debug("listImageEntries called for: \(self.url.lastPathComponent)")
            
            guard let archive = openArchive() else {
                Logger.archive.error("Failed to open archive: \(self.url)")
                return []
            }
            
            let encoding = getPathEncoding()
            var results: [ImageEntry] = []
            var allEntries: [String] = []
            
            for entry in archive {
                // Use explicit encoding for path decoding
                let path = encoding != nil ? entry.path(using: encoding!) : entry.path
                allEntries.append(path)
                if entry.type == .file {
                    let imageEntry = ImageEntry(
                        path: path,
                        size: entry.uncompressedSize
                    )
                    
                    // Filter: images only, exclude __MACOSX metadata
                    if imageEntry.isImage && !path.contains("__MACOSX/") && !imageEntry.name.hasPrefix("._") {
                        results.append(imageEntry)
                    }
                }
            }
            
            Logger.archive.debug("Archive contains \(allEntries.count, privacy: .public) total entries")
            Logger.archive.debug("Found \(results.count, privacy: .public) image entries:")
            for (index, entry) in results.prefix(10).enumerated() {
                Logger.archive.debug("  [\(index, privacy: .public)] \(entry.name) - \(entry.path)")
            }
            if results.count > 10 {
                Logger.archive.debug("  ... and \(results.count - 10, privacy: .public) more")
            }
            
            return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
    }
    
    /// Generate thumbnail for entry
    func thumbnail(for entry: ImageEntry, maxSize: CGFloat = 120) -> NSImage? {
        let cache = CacheManager.shared
        
        // Create unique path identifier: sourceURL + entryPath
        let fullPath = url.path + "/" + entry.path
        let pathHash = cache.pathHash(for: fullPath)
        
        // Check if we have cached content hash
        if let contentHash = cache.getContentHash(for: pathHash) {
            // Try to get cached thumbnail
            if let cached = cache.getThumbnail(for: contentHash) {
                Logger.thumbnailGrid.debug("Cache HIT for \(entry.name)")
                return cached
            }
        }
        
        // Cache miss - extract and generate
        Logger.thumbnailGrid.debug("Cache MISS for \(entry.name), extracting...")
        guard let imageData = extractData(for: entry) else { return nil }
        
        // Calculate content hash
        let contentHash = cache.contentHash(for: imageData)
        
        // Register mapping
        cache.registerMapping(pathHash: pathHash, contentHash: contentHash)
        
        // #134 P6: Single-pass downsample via CGImageSource (no full bitmap allocation)
        guard let thumbnail = ImageUtilities.downsampledThumbnail(from: imageData, maxSize: maxSize) else {
            Logger.thumbnailGrid.error("CGImageSource thumbnail failed for \(entry.name), falling back to NSImage")
            // Fallback: decode + resize (legacy path)
            guard let image = NSImage(data: imageData) else { return nil }
            let fallback = resizedImage(image, maxSize: maxSize)
            cache.saveThumbnail(fallback, for: contentHash)
            return fallback
        }
        
        // Save to cache
        cache.saveThumbnail(thumbnail, for: contentHash)
        
        return thumbnail
    }
    
    /// Get full-size image (fully materialized — no progressive rendering)
    func fullImage(for entry: ImageEntry) -> NSImage? {
        // #134: Check memory cache first (prevents redundant decode on SwiftUI re-evaluation)
        let cache = CacheManager.shared
        let fullPath = url.path + "/" + entry.path
        let pathHash = cache.pathHash(for: fullPath)
        if let contentHash = cache.getContentHash(for: pathHash),
           let cached = cache.getFullImageFromMemory(for: contentHash) {
            Logger.archive.info("★PERF★ fullImage CACHE HIT \(entry.name)")
            return cached
        }
        
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let data = extractData(for: entry) else { return nil }
        let t1 = CFAbsoluteTimeGetCurrent()
        
        // #134 P6: Use CGImageSource + materialize to force complete decode.
        // NSImage(data:) creates lazily-decoded image that renders progressively.
        if let materialized = ImageUtilities.materializedImage(from: data) {
            let t2 = CFAbsoluteTimeGetCurrent()
            let extractMs = (t1 - t0) * 1000
            let matMs = (t2 - t1) * 1000
            Logger.archive.info("★PERF★ fullImage \(entry.name): extract=\(String(format: "%.1f", extractMs))ms materialize=\(String(format: "%.1f", matMs))ms total=\(String(format: "%.1f", extractMs + matMs))ms size=\(materialized.size.debugDescription)")
            
            // Cache with contentHash
            let contentHash = cache.contentHash(for: data)
            cache.registerMapping(pathHash: pathHash, contentHash: contentHash)
            cache.cacheFullImage(materialized, for: contentHash)
            
            return materialized
        }
        
        // Fallback: legacy path
        Logger.archive.error("materializedImage failed for \(entry.name), falling back to NSImage(data:)")
        guard let image = NSImage(data: data) else {
            Logger.archive.error("Invalid image data for: \(entry.name), size: \(data.count, privacy: .public) bytes")
            return nil
        }
        return image
    }
    
    // MARK: - Private Helpers
    
    /// Extract raw data from ZIP entry (#140: internal for MetadataExtractor access)
    func extractData(for imageEntry: ImageEntry) -> Data? {
        return accessQueue.sync {
            Logger.archive.debug("Looking for '\(imageEntry.path)' in '\(self.url.lastPathComponent)'")
            
            guard let archive = openArchive() else {
                Logger.archive.error("Failed to open archive: \(self.url.path)")
                return nil
            }
            
            let encoding = getPathEncoding()
            
            // Find entry by iterating (reliable for all encodings)
            var foundEntry: Entry?
            var availablePaths: [String] = []
            for entry in archive {
                let path = encoding != nil ? entry.path(using: encoding!) : entry.path
                availablePaths.append(path)
                if path == imageEntry.path {
                    foundEntry = entry
                    break
                }
            }
            
            guard let entry = foundEntry else {
                Logger.archive.debug("Entry not found: \(imageEntry.path)")
                Logger.archive.debug("ZIP '\(self.url.lastPathComponent)' contains \(availablePaths.count, privacy: .public) entries:")
                for path in availablePaths.prefix(10) {
                    Logger.archive.debug("  - \(path)")
                }
                if availablePaths.count > 10 {
                    Logger.archive.debug("  ... and \(availablePaths.count - 10, privacy: .public) more")
                }
                return nil
            }
            
            var imageData = Data()
            do {
                _ = try archive.extract(entry) { data in
                    imageData.append(data)
                }
            } catch {
                Logger.archive.error("Extract failed for \(imageEntry.name): \(error, privacy: .public)")
                return nil
            }
            
            return imageData
        }
    }
    
    private func resizedImage(_ image: NSImage, maxSize: CGFloat) -> NSImage {
        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else {
            return image
        }
        
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height, 1.0)
        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        
        return newImage
    }
    
    // MARK: - Export functionality
    
    /// Export excluding specified paths
    /// Reference: https://github.com/weichsel/ZIPFoundation#adding-and-removing-entries
    /// Uses atomic safe export to prevent data loss when destination == source (#161)
    func exportOptimized(excluding excludedPaths: Set<String>, to destinationURL: URL) throws {
        Logger.archive.info("exportOptimized called")
        Logger.archive.debug("Excluded paths: \(excludedPaths)")
        
        try ExportUtilities.safeExport(to: destinationURL) { tempURL in
            guard let sourceArchive = openArchive() else {
                Logger.archive.error("Failed to open source archive")
                throw ArchiveError.cannotOpenSource
            }
            Logger.archive.debug("Source archive opened")
            
            guard let destinationArchive = try? Archive(url: tempURL, accessMode: .create) else {
                Logger.archive.error("Failed to create destination archive at: \(tempURL.path)")
                throw ArchiveError.cannotCreateDestination
            }
            Logger.archive.debug("Destination archive created (temp)")
            
            let encoding = getPathEncoding()
            
            for entry in sourceArchive {
                let path = encoding != nil ? entry.path(using: encoding!) : entry.path
                
                if excludedPaths.contains(path) {
                    Logger.archive.debug("Excluding: \(path)")
                    continue
                }
                
                if path.contains("__MACOSX/") {
                    Logger.archive.debug("Skipping __MACOSX: \(path)")
                    continue
                }
                
                if entry.type == .directory {
                    Logger.archive.debug("Skipping directory: \(path)")
                    continue
                }
                
                Logger.archive.debug("Copying: \(path)")
                
                var entryData = Data()
                do {
                    _ = try sourceArchive.extract(entry) { data in
                        entryData.append(data)
                    }
                    Logger.archive.debug("  Extracted: \(entryData.count, privacy: .public) bytes")
                } catch {
                    Logger.archive.error("  Extract failed: \(error, privacy: .public)")
                    continue
                }
                
                do {
                    // Write with correctly decoded path (UTF-8 in destination)
                    try destinationArchive.addEntry(
                        with: path,
                        type: entry.type,
                        uncompressedSize: Int64(entryData.count),
                        provider: { position, size in
                            let start = Int(position)
                            let end = min(start + size, entryData.count)
                            return entryData.subdata(in: start..<end)
                        }
                    )
                    Logger.archive.debug("  Added to destination")
                } catch {
                    Logger.archive.error("  Add failed: \(error, privacy: .public)")
                    continue
                }
            }
            
            Logger.archive.info("Export completed successfully")
        }
    }
}

enum ArchiveError: Error, LocalizedError {
    case cannotOpenSource
    case cannotCreateDestination
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenSource:
            return "元のZIPファイルを開けません"
        case .cannotCreateDestination:
            return "新しいZIPファイルを作成できません"
        }
    }
}
