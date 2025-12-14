//
//  CacheManager.swift
//  Erimil
//
//  Cache infrastructure with hash-based privacy design
//  Stores thumbnails and metadata in ~/Library/Application Support/Erimil/
//

import Foundation
import AppKit
import CryptoKit

/// Manages thumbnail cache and metadata with privacy-first hash-based storage
class CacheManager {
    static let shared = CacheManager()
    
    // MARK: - Directory Structure
    
    /// ~/Library/Application Support/Erimil/
    private let baseDirectory: URL
    
    /// ~/Library/Application Support/Erimil/cache/
    private let cacheDirectory: URL
    
    /// ~/Library/Application Support/Erimil/index.json
    private let indexFileURL: URL
    
    /// ~/Library/Application Support/Erimil/favorites.json
    let favoritesFileURL: URL
    
    // MARK: - In-Memory Cache
    
    /// pathHash → contentHash mapping (loaded from index.json)
    private var pathIndex: [String: String] = [:]
    private let indexLock = NSLock()
    
    /// contentHash → thumbnail (memory cache, thread-safe)
    private let thumbnailCache = NSCache<NSString, NSImage>()
    
    // MARK: - Initialization
    
    private init() {
        // Setup base directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("Erimil", isDirectory: true)
        cacheDirectory = baseDirectory.appendingPathComponent("cache", isDirectory: true)
        indexFileURL = baseDirectory.appendingPathComponent("index.json")
        favoritesFileURL = baseDirectory.appendingPathComponent("favorites.json")
        
        // Configure cache
        thumbnailCache.countLimit = 200
        
        // Create directories if needed
        createDirectoriesIfNeeded()
        
        // Load index
        loadIndex()
    }
    
    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        
        do {
            if !fm.fileExists(atPath: baseDirectory.path) {
                try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
                print("[CacheManager] Created base directory: \(baseDirectory.path)")
            }
            
            if !fm.fileExists(atPath: cacheDirectory.path) {
                try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                print("[CacheManager] Created cache directory: \(cacheDirectory.path)")
            }
        } catch {
            print("[CacheManager] Failed to create directories: \(error)")
        }
    }
    
    // MARK: - Hash Calculation
    
    /// Calculate SHA256 hash of a string (for path hashing)
    func hashString(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return "sha256:" + hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Calculate SHA256 hash of data (for content hashing)
    func hashData(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return "sha256:" + hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Calculate content hash for image data
    func contentHash(for imageData: Data) -> String {
        return hashData(imageData)
    }
    
    /// Calculate path hash for a file path
    func pathHash(for path: String) -> String {
        return hashString(path)
    }
    
    // MARK: - Index Management
    
    private func loadIndex() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else {
            pathIndex = [:]
            return
        }
        
        do {
            let data = try Data(contentsOf: indexFileURL)
            indexLock.lock()
            pathIndex = try JSONDecoder().decode([String: String].self, from: data)
            indexLock.unlock()
            print("[CacheManager] Loaded index with \(pathIndex.count) entries")
        } catch {
            print("[CacheManager] Failed to load index: \(error)")
            pathIndex = [:]
        }
    }
    
    private func saveIndex() {
        indexLock.lock()
        let currentIndex = pathIndex
        indexLock.unlock()
        
        do {
            let data = try JSONEncoder().encode(currentIndex)
            try data.write(to: indexFileURL)
        } catch {
            print("[CacheManager] Failed to save index: \(error)")
        }
    }
    
    /// Register path → content hash mapping
    func registerMapping(pathHash: String, contentHash: String) {
        indexLock.lock()
        pathIndex[pathHash] = contentHash
        indexLock.unlock()
        saveIndex()
    }
    
    /// Get content hash for a path hash
    func getContentHash(for pathHash: String) -> String? {
        indexLock.lock()
        let result = pathIndex[pathHash]
        indexLock.unlock()
        return result
    }
    
    // MARK: - Thumbnail Cache
    
    /// Get cached thumbnail URL for a content hash
    private func thumbnailURL(for contentHash: String) -> URL {
        let filename = contentHash.replacingOccurrences(of: "sha256:", with: "") + ".thumb.jpg"
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    /// Check if thumbnail exists in disk cache
    func hasThumbnailOnDisk(for contentHash: String) -> Bool {
        return FileManager.default.fileExists(atPath: thumbnailURL(for: contentHash).path)
    }
    
    /// Get thumbnail from memory cache
    func getThumbnailFromMemory(for contentHash: String) -> NSImage? {
        return thumbnailCache.object(forKey: contentHash as NSString)
    }
    
    /// Get thumbnail from disk cache
    func getThumbnailFromDisk(for contentHash: String) -> NSImage? {
        let url = thumbnailURL(for: contentHash)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        
        // Add to memory cache
        thumbnailCache.setObject(image, forKey: contentHash as NSString)
        
        return image
    }
    
    /// Get thumbnail (tries memory first, then disk)
    func getThumbnail(for contentHash: String) -> NSImage? {
        // Try memory cache first
        if let cached = getThumbnailFromMemory(for: contentHash) {
            return cached
        }
        
        // Try disk cache
        return getThumbnailFromDisk(for: contentHash)
    }
    
    /// Save thumbnail to both memory and disk cache
    func saveThumbnail(_ image: NSImage, for contentHash: String) {
        // Add to memory cache
        thumbnailCache.setObject(image, forKey: contentHash as NSString)
        
        // Save to disk
        saveThumbnailToDisk(image, for: contentHash)
    }
    
    private func saveThumbnailToDisk(_ image: NSImage, for contentHash: String) {
        let url = thumbnailURL(for: contentHash)
        
        // Skip if already exists
        guard !FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        
        // Convert to JPEG data
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            print("[CacheManager] Failed to convert thumbnail to JPEG")
            return
        }
        
        do {
            try jpegData.write(to: url)
        } catch {
            print("[CacheManager] Failed to save thumbnail: \(error)")
        }
    }
    
    // MARK: - Full Workflow
    
    /// Get or create thumbnail with caching
    /// Returns (thumbnail, contentHash) or nil if failed
    func getOrCreateThumbnail(
        sourcePath: String,
        imageDataProvider: () -> Data?,
        thumbnailGenerator: (Data) -> NSImage?
    ) -> (thumbnail: NSImage, contentHash: String)? {
        let pHash = pathHash(for: sourcePath)
        
        // Check if we already have content hash for this path
        if let cHash = getContentHash(for: pHash) {
            // Try to get cached thumbnail
            if let thumbnail = getThumbnail(for: cHash) {
                return (thumbnail, cHash)
            }
        }
        
        // Need to load image data
        guard let imageData = imageDataProvider() else {
            return nil
        }
        
        // Calculate content hash
        let cHash = contentHash(for: imageData)
        
        // Register mapping
        registerMapping(pathHash: pHash, contentHash: cHash)
        
        // Check if thumbnail exists for this content (maybe from different path)
        if let thumbnail = getThumbnail(for: cHash) {
            return (thumbnail, cHash)
        }
        
        // Generate new thumbnail
        guard let thumbnail = thumbnailGenerator(imageData) else {
            return nil
        }
        
        // Save to cache
        saveThumbnail(thumbnail, for: cHash)
        
        return (thumbnail, cHash)
    }
    
    // MARK: - Cache Management
    
    /// Clear memory cache
    func clearMemoryCache() {
        thumbnailCache.removeAllObjects()
        print("[CacheManager] Memory cache cleared")
    }
    
    /// Clear all cache (memory + disk)
    func clearAllCache() {
        clearMemoryCache()
        
        // Clear disk cache
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: cacheDirectory.path) {
                try fm.removeItem(at: cacheDirectory)
                try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            }
            
            // Clear index
            indexLock.lock()
            pathIndex.removeAll()
            indexLock.unlock()
            saveIndex()
            
            print("[CacheManager] All cache cleared")
        } catch {
            print("[CacheManager] Failed to clear cache: \(error)")
        }
    }
    
    /// Get cache size info
    func getCacheInfo() -> (fileCount: Int, totalSize: Int64) {
        let fm = FileManager.default
        var count = 0
        var size: Int64 = 0
        
        guard let enumerator = fm.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return (0, 0)
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            count += 1
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }
        
        return (count, size)
    }
}
