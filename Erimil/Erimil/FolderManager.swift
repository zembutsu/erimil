//
//  FolderManager.swift
//  Erimil
//
//  ImageSource implementation for folder browsing
//

import Foundation
import AppKit
import ZIPFoundation

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
            print("Failed to read folder: \(url)")
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
                print("[FolderManager] Cache HIT for \(entry.name)")
                return cached
            }
        }
        
        // Cache miss - load file and generate
        print("[FolderManager] Cache MISS for \(entry.name), loading...")
        let fileURL = URL(fileURLWithPath: entry.path)
        
        guard let imageData = try? Data(contentsOf: fileURL) else {
            print("[FolderManager] Failed to read file: \(entry.path)")
            return nil
        }
        
        guard let image = NSImage(data: imageData) else {
            print("[FolderManager] Invalid image data: \(entry.path)")
            return nil
        }
        
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
    
    /// Get full-size image - direct file access
    func fullImage(for entry: ImageEntry) -> NSImage? {
        let fileURL = URL(fileURLWithPath: entry.path)
        print("[FolderManager] Loading image: \(fileURL.lastPathComponent)")
        
        guard let image = NSImage(contentsOf: fileURL) else {
            print("[FolderManager] Failed to load: \(entry.path)")
            return nil
        }
        return image
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
    func createZip(excluding excludedPaths: Set<String>, to destinationURL: URL) throws {
        print("createZip called")
        print("Excluded paths: \(excludedPaths)")
        
        guard let archive = Archive(url: destinationURL, accessMode: .create) else {
            throw FolderError.cannotCreateZip
        }
        
        let entries = listImageEntries()
        
        for entry in entries {
            if excludedPaths.contains(entry.path) {
                print("Excluding: \(entry.name)")
                continue
            }
            
            let fileURL = URL(fileURLWithPath: entry.path)
            
            do {
                try archive.addEntry(with: entry.name, relativeTo: fileURL.deletingLastPathComponent())
                print("Added: \(entry.name)")
            } catch {
                print("Failed to add \(entry.name): \(error)")
            }
        }
        
        print("ZIP creation completed")
    }
    
    /// Move selected images to Trash
    func moveToTrash(paths: Set<String>) throws -> Int {
        var trashedCount = 0
        
        for path in paths {
            let fileURL = URL(fileURLWithPath: path)
            
            do {
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                print("Trashed: \(fileURL.lastPathComponent)")
                trashedCount += 1
            } catch {
                print("Failed to trash \(fileURL.lastPathComponent): \(error)")
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
