//
//  FolderManager.swift
//  Erimil
//
//  ImageSource implementation for folder browsing
//

import Foundation
import AppKit
import ZIPFoundation
import os

class FolderManager: ImageSource {
    let url: URL
    let sourceType: ImageSourceType = .folder
    
    init(folderURL: URL) {
        self.url = folderURL
    }
    
    /// List all image files in the folder (non-recursive)
    func listImageEntries() -> [ImageEntry] {
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Logger.folder.error("Failed to read folder: \(self.url)")
            return []
        }
        
        var results: [ImageEntry] = []
        
        for fileURL in contents {
            // Skip directories
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            let entry = ImageEntry(
                path: fileURL.path,
                name: fileURL.lastPathComponent,
                size: UInt64(resourceValues.fileSize ?? 0)
            )
            
            if entry.isImage {
                results.append(entry)
            }
        }
        
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    /// Generate thumbnail - with disk cache
    func thumbnail(for entry: ImageEntry, maxSize: CGFloat = 120) -> NSImage? {
        let cache = CacheManager.shared
        
        // Use full file path as unique identifier
        let pathHash = cache.pathHash(for: entry.path)
        
        // Check if we have cached content hash
        if let contentHash = cache.getContentHash(for: pathHash) {
            // Try to get cached thumbnail
            if let cached = cache.getThumbnail(for: contentHash) {
                Logger.folder.debug("Cache HIT for \(entry.name)")
                return cached
            }
        }
        
        // Cache miss - load file and generate
        Logger.folder.debug("Cache MISS for \(entry.name), loading...")
        let fileURL = URL(fileURLWithPath: entry.path)
        
        guard let imageData = try? Data(contentsOf: fileURL) else {
            Logger.folder.error("Failed to read file: \(entry.path)")
            return nil
        }
        
        // Calculate content hash
        let contentHash = cache.contentHash(for: imageData)
        
        // Register mapping
        cache.registerMapping(pathHash: pathHash, contentHash: contentHash)
        
        // #134 P6: Single-pass downsample via CGImageSource (no full bitmap allocation)
        guard let thumbnail = ImageUtilities.downsampledThumbnail(from: imageData, maxSize: maxSize) else {
            Logger.folder.error("CGImageSource thumbnail failed for \(entry.name), falling back to NSImage")
            // Fallback: legacy path
            guard let image = NSImage(data: imageData) else {
                Logger.folder.error("Invalid image data: \(entry.path)")
                return nil
            }
            let fallback = resizedImage(image, maxSize: maxSize)
            cache.saveThumbnail(fallback, for: contentHash)
            return fallback
        }
        
        // Save to cache
        cache.saveThumbnail(thumbnail, for: contentHash)
        
        return thumbnail
    }
    
    /// Get full-size image - direct file access (fully materialized)
    func fullImage(for entry: ImageEntry) -> NSImage? {
        let fileURL = URL(fileURLWithPath: entry.path)
        
        // #134: Check memory cache first (prevents redundant decode on SwiftUI re-evaluation)
        let cache = CacheManager.shared
        let pathHash = cache.pathHash(for: entry.path)
        if let contentHash = cache.getContentHash(for: pathHash),
           let cached = cache.getFullImageFromMemory(for: contentHash) {
            Logger.folder.info("★PERF★ fullImage CACHE HIT \(entry.name)")
            return cached
        }
        
        Logger.folder.debug("Loading image: \(fileURL.lastPathComponent)")
        
        let t0 = CFAbsoluteTimeGetCurrent()
        
        // #134 P6: Use CGImageSource + materialize to force complete decode.
        // NSImage(contentsOf:) creates lazily-decoded image that renders progressively.
        if let materialized = ImageUtilities.materializedImage(from: fileURL) {
            let t1 = CFAbsoluteTimeGetCurrent()
            let ms = (t1 - t0) * 1000
            Logger.folder.info("★PERF★ fullImage \(entry.name): materialize=\(String(format: "%.1f", ms))ms size=\(materialized.size.debugDescription)")
            
            // Cache with contentHash (read file for hash if needed)
            if let contentHash = cache.getContentHash(for: pathHash) {
                cache.cacheFullImage(materialized, for: contentHash)
            } else if let data = try? Data(contentsOf: fileURL) {
                let contentHash = cache.contentHash(for: data)
                cache.registerMapping(pathHash: pathHash, contentHash: contentHash)
                cache.cacheFullImage(materialized, for: contentHash)
            }
            
            return materialized
        }
        
        // Fallback: legacy path
        Logger.folder.error("materializedImage failed for \(entry.name), falling back to NSImage(contentsOf:)")
        guard let image = NSImage(contentsOf: fileURL) else {
            Logger.folder.error("Failed to load: \(entry.path)")
            return nil
        }
        return image
    }
    
    func fileURL(for entry: ImageEntry) -> URL? {
        URL(fileURLWithPath: entry.path)
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
    
    // MARK: - Folder Operations
    
    /// Create ZIP from selected images (excluding excludedPaths)
    /// Uses atomic safe export to prevent data loss (#161)
    func createZip(excluding excludedPaths: Set<String>, to destinationURL: URL) throws {
        Logger.folder.info("createZip called")
        Logger.folder.debug("Excluded paths: \(excludedPaths)")
        
        try ExportUtilities.safeExport(to: destinationURL) { tempURL in
            guard let archive = Archive(url: tempURL, accessMode: .create) else {
                throw FolderError.cannotCreateZip
            }
            
            let entries = listImageEntries()
            
            for entry in entries {
                if excludedPaths.contains(entry.path) {
                    Logger.folder.debug("Excluding: \(entry.name)")
                    continue
                }
                
                let fileURL = URL(fileURLWithPath: entry.path)
                
                do {
                    try archive.addEntry(with: entry.name, relativeTo: fileURL.deletingLastPathComponent())
                    Logger.folder.debug("Added: \(entry.name)")
                } catch {
                    Logger.folder.error("Failed to add \(entry.name): \(error, privacy: .public)")
                }
            }
            
            Logger.folder.info("ZIP creation completed")
        }
    }
    
    /// Move selected images to Trash
    func moveToTrash(paths: Set<String>) throws -> Int {
        var trashedCount = 0
        
        for path in paths {
            let fileURL = URL(fileURLWithPath: path)
            
            do {
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                Logger.folder.info("Trashed: \(fileURL.lastPathComponent)")
                trashedCount += 1
            } catch {
                Logger.folder.error("Failed to trash \(fileURL.lastPathComponent): \(error, privacy: .public)")
            }
        }
        
        return trashedCount
    }
}

enum FolderError: Error, LocalizedError {
    case cannotCreateZip
    case cannotReadFolder
    
    var errorDescription: String? {
        switch self {
        case .cannotCreateZip:
            return "ZIPファイルを作成できません"
        case .cannotReadFolder:
            return "フォルダを読み込めません"
        }
    }
}
