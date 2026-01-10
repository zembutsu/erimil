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
                print("[ArchiveManager] Opening with Shift_JIS encoding")
                return try Archive(url: url, accessMode: .read, pathEncoding: .shiftJIS)
            case .utf8:
                print("[ArchiveManager] Opening with UTF-8 encoding")
                return try Archive(url: url, accessMode: .read, pathEncoding: .utf8)
            case .unknown, .none:
                print("[ArchiveManager] Opening with default encoding")
                return try Archive(url: url, accessMode: .read)
            }
        } catch {
            print("[ArchiveManager] Failed to open archive: \(error)")
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
            print("[ArchiveManager] listImageEntries called for: \(url.lastPathComponent)")
            
            guard let archive = openArchive() else {
                print("[ArchiveManager] Failed to open archive: \(url)")
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
            
            print("[ArchiveManager] Archive contains \(allEntries.count) total entries")
            print("[ArchiveManager] Found \(results.count) image entries:")
            for (index, entry) in results.prefix(10).enumerated() {
                print("  [\(index)] \(entry.name) - \(entry.path)")
            }
            if results.count > 10 {
                print("  ... and \(results.count - 10) more")
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
                print("[thumbnail] Cache HIT for \(entry.name)")
                return cached
            }
        }
        
        // Cache miss - extract and generate
        print("[thumbnail] Cache MISS for \(entry.name), extracting...")
        guard let (image, imageData) = extractImageWithData(for: entry) else { return nil }
        
        // Calculate content hash
        let contentHash = cache.contentHash(for: imageData)
        
        // Register mapping
        cache.registerMapping(pathHash: pathHash, contentHash: contentHash)
        
        // Generate thumbnail
        let thumbnail = resizedImage(image, maxSize: maxSize)
        
        // Save to cache
        cache.saveThumbnail(thumbnail, for: contentHash)
        
        return thumbnail
    }
    
    /// Get full-size image
    func fullImage(for entry: ImageEntry) -> NSImage? {
        return extractImageWithData(for: entry)?.0
    }
    
    // MARK: - Private Helpers
    
    /// Extract image and raw data from ZIP
    private func extractImageWithData(for imageEntry: ImageEntry) -> (NSImage, Data)? {
        return accessQueue.sync {
            print("[extractImage] Looking for '\(imageEntry.path)' in '\(url.lastPathComponent)'")
            
            guard let archive = openArchive() else {
                print("[extractImage] Failed to open archive: \(url.path)")
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
                print("[extractImage] Entry not found: \(imageEntry.path)")
                print("[extractImage] ZIP '\(url.lastPathComponent)' contains \(availablePaths.count) entries:")
                for path in availablePaths.prefix(10) {
                    print("  - \(path)")
                }
                if availablePaths.count > 10 {
                    print("  ... and \(availablePaths.count - 10) more")
                }
                return nil
            }
            
            var imageData = Data()
            do {
                _ = try archive.extract(entry) { data in
                    imageData.append(data)
                }
            } catch {
                print("[extractImage] Extract failed for \(imageEntry.name): \(error)")
                return nil
            }
            
            guard let image = NSImage(data: imageData) else {
                print("[extractImage] Invalid image data for: \(imageEntry.name), size: \(imageData.count) bytes")
                return nil
            }
            
            return (image, imageData)
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
    func exportOptimized(excluding excludedPaths: Set<String>, to destinationURL: URL) throws {
        print("exportOptimized called")
        print("Excluded paths: \(excludedPaths)")
        
        guard let sourceArchive = openArchive() else {
            print("Failed to open source archive")
            throw ArchiveError.cannotOpenSource
        }
        print("Source archive opened")
        
        guard let destinationArchive = try? Archive(url: destinationURL, accessMode: .create) else {
            print("Failed to create destination archive at: \(destinationURL.path)")
            throw ArchiveError.cannotCreateDestination
        }
        print("Destination archive created")
        
        let encoding = getPathEncoding()
        
        for entry in sourceArchive {
            let path = encoding != nil ? entry.path(using: encoding!) : entry.path
            
            if excludedPaths.contains(path) {
                print("Excluding: \(path)")
                continue
            }
            
            if path.contains("__MACOSX/") {
                print("Skipping __MACOSX: \(path)")
                continue
            }
            
            if entry.type == .directory {
                print("Skipping directory: \(path)")
                continue
            }
            
            print("Copying: \(path)")
            
            var entryData = Data()
            do {
                _ = try sourceArchive.extract(entry) { data in
                    entryData.append(data)
                }
                print("  Extracted: \(entryData.count) bytes")
            } catch {
                print("  Extract failed: \(error)")
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
                print("  Added to destination")
            } catch {
                print("  Add failed: \(error)")
                continue
            }
        }
        
        print("Export completed successfully")
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
