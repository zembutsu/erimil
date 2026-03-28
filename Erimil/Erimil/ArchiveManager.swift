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
    
    /// #24: Tile sheet state tracking
    private var tileSheetInitialized = false
    private var tileSheetAvailable = false
    
    /// #24: Cached archive hash (computed once per instance)
    private var cachedArchiveHash: String?
    
    /// #24: Background prefetch for tile sheet collection
    private var prefetchStarted = false
    private let prefetchQueue = DispatchQueue(
        label: "com.erimil.archive.prefetch",
        qos: .utility
    )
    
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
            
            // #24 S085: Preload tile sheet into memory cache during entry listing (D005 pattern).
            // This runs inside accessQueue.sync BEFORE any onAppear → loadThumbnailIfNeeded,
            // ensuring the synchronous memory check (SYNC memory hit) in ThumbnailGridView
            // hits for all tile-sheet-covered pages — no loading icon flash.
            // Also guarantees single-thread execution (eliminates N× redundant loads).
            // Only handles "tile sheet exists on disk" case — if no tile sheet,
            // flags stay unset and thumbnail() fallback triggers prefetchAllThumbnails().
            if !tileSheetInitialized {
                tileSheetInitialized = true
                prefetchStarted = true
                let tileCache = TileSheetCache.shared
                if cachedArchiveHash == nil {
                    cachedArchiveHash = tileCache.archiveHash(for: url)
                }
                if let hash = cachedArchiveHash, tileCache.hasTileSheet(for: url, archiveHash: hash) {
                    tileSheetAvailable = true
                    let loaded = tileCache.loadAllThumbnails(for: url, archiveHash: hash)
                    if loaded == 0 {
                        tileSheetAvailable = false
                        prefetchAllThumbnails(entries: results)
                    } else {
                        Logger.thumbnailGrid.info("TileSheet: preloaded \(loaded, privacy: .public) thumbnails for \(self.url.lastPathComponent)")
                        if loaded < results.count {
                            // Partial coverage — prefetch remaining entries
                            tileSheetAvailable = false
                            Logger.cache.info("TileSheet: partial coverage (\(loaded)/\(results.count)) — starting prefetch")
                            prefetchAllThumbnails(entries: results)
                        }
                    }
                } else {
                    // No tile sheet — full prefetch
                    prefetchAllThumbnails(entries: results)
                }
            }
            
            return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
    }
    
    /// Generate thumbnail for entry
    func thumbnail(for entry: ImageEntry, maxSize: CGFloat = AppSettings.shared.effectiveRetinaThumbnailSize) -> NSImage? {
        // #24: Tile sheet initialization — fallback for when thumbnail() is called
        // before listImageEntries(), or when no tile sheet exists on disk.
        // Both flags set immediately to prevent other threads from starting prefetch
        // while this thread loads tile sheet or decides to prefetch.
        if !tileSheetInitialized {
            tileSheetInitialized = true
            prefetchStarted = true  // Block all other threads from prefetch check
            let tileCache = TileSheetCache.shared
            if cachedArchiveHash == nil {
                cachedArchiveHash = tileCache.archiveHash(for: url)
            }
            if let hash = cachedArchiveHash, tileCache.hasTileSheet(for: url, archiveHash: hash) {
                tileSheetAvailable = true  // BEFORE load (block registerThumbnail during load)
                let loaded = tileCache.loadAllThumbnails(for: url, archiveHash: hash)
                if loaded == 0 {
                    tileSheetAvailable = false  // Revert on failure
                } else {
                    Logger.thumbnailGrid.info("TileSheet: preloaded \(loaded, privacy: .public) thumbnails for \(self.url.lastPathComponent)")
                }
            } else {
                // No tile sheet on disk — start background prefetch to collect all thumbnails
                prefetchAllThumbnails(entries: listImageEntries())
            }
        }

        let cache = CacheManager.shared

        // Create unique path identifier: sourceURL + entryPath
        let fullPath = url.path + "/" + entry.path
        let pathHash = cache.pathHash(for: fullPath)

        // Check if we have cached content hash
        if let contentHash = cache.getContentHash(for: pathHash) {
            // Try to get cached thumbnail
            if let cached = cache.getThumbnail(for: contentHash) {
                Logger.thumbnailGrid.debug("Cache HIT for \(entry.name)")
                // #24: Register for deferred tile sheet build (debounce resets on each call)
                if !tileSheetAvailable, let hash = cachedArchiveHash {
                    TileSheetCache.shared.registerThumbnail(
                        for: url, archiveHash: hash, entryPath: entry.path,
                        contentHash: contentHash, image: cached
                    )
                }
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
            // #24: Register fallback for tile sheet build
            if !tileSheetAvailable, let hash = cachedArchiveHash {
                TileSheetCache.shared.registerThumbnail(
                    for: url, archiveHash: hash, entryPath: entry.path,
                    contentHash: contentHash, image: fallback
                )
            }
            return fallback
        }

        // Save to cache
        cache.saveThumbnail(thumbnail, for: contentHash)

        // #24: Register for deferred tile sheet build
        if !tileSheetAvailable, let hash = cachedArchiveHash {
            TileSheetCache.shared.registerThumbnail(
                for: url, archiveHash: hash, entryPath: entry.path,
                contentHash: contentHash, image: thumbnail
            )
        }

        return thumbnail
    }
    
    func registerThumbnailForTileSheet(for entry: ImageEntry, contentHash: String, image: NSImage) {
        guard !tileSheetAvailable, let hash = cachedArchiveHash else { return }
        TileSheetCache.shared.registerThumbnail(
            for: url, archiveHash: hash, entryPath: entry.path,
            contentHash: contentHash, image: image
        )
    }
    
    /// #24: Background prefetch — collect all thumbnails for tile sheet build.
    /// Runs on utility queue. Uses existing cache when available, generates otherwise.
    /// #223: entries passed as parameter to avoid accessQueue deadlock when called from listImageEntries().
    private func prefetchAllThumbnails(entries: [ImageEntry]) {
        let archiveURL = self.url
        let maxSize: CGFloat = AppSettings.shared.effectiveRetinaThumbnailSize
        guard let hash = cachedArchiveHash else { return }

        prefetchQueue.async { [weak self] in
            guard let self = self else { return }
            let cache = CacheManager.shared
            let tileCache = TileSheetCache.shared

            Logger.cache.info("TileSheet prefetch: starting \(entries.count, privacy: .public) entries for \(archiveURL.lastPathComponent)")

            for entry in entries {
                let fullPath = archiveURL.path + "/" + entry.path
                let pathHash = cache.pathHash(for: fullPath)

                // Try existing cache first (hybrid: reuse what's already there)
                if let contentHash = cache.getContentHash(for: pathHash),
                   let cached = cache.getThumbnail(for: contentHash) {
                    tileCache.registerThumbnail(
                        for: archiveURL, archiveHash: hash, entryPath: entry.path,
                        contentHash: contentHash, image: cached
                    )
                    continue
                }

                // Cache miss — extract and generate
                guard let imageData = self.extractDataForPrefetch(for: entry) else { continue }
                let contentHash = cache.contentHash(for: imageData)
                cache.registerMapping(pathHash: pathHash, contentHash: contentHash)

                // Check if thumbnail exists under content hash (different path, same content)
                if let cached = cache.getThumbnail(for: contentHash) {
                    tileCache.registerThumbnail(
                        for: archiveURL, archiveHash: hash, entryPath: entry.path,
                        contentHash: contentHash, image: cached
                    )
                    continue
                }

                // Generate thumbnail
                guard let thumbnail = ImageUtilities.downsampledThumbnail(from: imageData, maxSize: maxSize) else {
                    continue
                }
                cache.saveThumbnail(thumbnail, for: contentHash)
                tileCache.registerThumbnail(
                    for: archiveURL, archiveHash: hash, entryPath: entry.path,
                    contentHash: contentHash, image: thumbnail
                )
            }

            Logger.cache.info("TileSheet prefetch: completed \(entries.count, privacy: .public) entries")
            TileSheetCache.shared.finalizeBuild(for: hash)
        }
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
    
    // MARK: - Animated Image Support (#201)
   
    func fileURL(for entry: ImageEntry) -> URL? {
        nil
    }
   
    func isAnimatedImage(for entry: ImageEntry) -> Bool {
        guard let data = extractData(for: entry) else { return false }
        return AnimatedImageContent.isAnimated(data: data)
    }
   
    func animatedImageContent(for entry: ImageEntry) -> AnimatedImageContent? {
        guard let data = extractData(for: entry) else { return nil }
        return AnimatedImageContent.decode(from: data)
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

    /// Prefetch-only extract — opens own Archive handle to avoid accessQueue contention.
    /// On-demand thumbnail() uses extractData() which serializes via accessQueue;
    /// this method bypasses that queue so prefetch and on-demand can run in parallel.
    private func extractDataForPrefetch(for imageEntry: ImageEntry) -> Data? {
        guard let archive = openArchive() else { return nil }
        let encoding = getPathEncoding()

        var foundEntry: Entry?
        for entry in archive {
            let path = encoding != nil ? entry.path(using: encoding!) : entry.path
            if path == imageEntry.path {
                foundEntry = entry
                break
            }
        }
        guard let entry = foundEntry else { return nil }

        var imageData = Data()
        do {
            _ = try archive.extract(entry) { data in
                imageData.append(data)
            }
        } catch {
            Logger.archive.error("Prefetch extract failed for \(imageEntry.name): \(error, privacy: .public)")
            return nil
        }
        return imageData
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
