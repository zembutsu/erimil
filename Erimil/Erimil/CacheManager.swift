//
//  CacheManager.swift
//  Erimil
//
//  Cache infrastructure with hash-based privacy design
//  Stores thumbnails and metadata in ~/Library/Application Support/Erimil/
//  Updated: S017 (2026-01-24) - Last position management (#52)
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
    
    /// ~/Library/Application Support/Erimil/last_position.json (#52)
    private let lastPositionFileURL: URL
    
    // MARK: - In-Memory Cache
    
    /// pathHash → contentHash mapping (loaded from index.json)
    private var pathIndex: [String: String] = [:]
    private let indexLock = NSLock()
    
    /// contentHash → thumbnail (memory cache, thread-safe)
    private let thumbnailCache = NSCache<NSString, NSImage>()
    
    /// Favorites lock for thread-safety
    private let favoritesLock = NSLock()
    
    /// Last viewed position per source (#52)
    private var lastPositions: [String: Int] = [:]
    private let positionLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // Setup base directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("Erimil", isDirectory: true)
        cacheDirectory = baseDirectory.appendingPathComponent("cache", isDirectory: true)
        indexFileURL = baseDirectory.appendingPathComponent("index.json")
        favoritesFileURL = baseDirectory.appendingPathComponent("favorites.json")
        lastPositionFileURL = baseDirectory.appendingPathComponent("last_position.json")
        
        // Configure cache
        thumbnailCache.countLimit = 200
        
        // Create directories if needed
        createDirectoriesIfNeeded()
        
        // Load index, favorites, and last positions
        loadIndex()
        loadFavorites()
        loadLastPositions()
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
    
    // MARK: - Hybrid Favorites Management
    
    /// Favorite status enum
    enum FavoriteStatus {
        case none       // Not favorited
        case inherited  // Content is favorited (from other source) - shows ☆
        case direct     // Favorited in this source - shows ★
    }
    
    /// Hybrid favorites file structure (v2)
    private struct HybridFavoritesFile: Codable {
        var version: Int = 2
        var byContent: [String: FavoriteMetadata]  // contentHash → metadata
        var bySource: [String: FavoriteMetadata]   // sourceKey → metadata (sourceKey = hash of sourceURL+entryPath)
    }
    
    private struct FavoriteMetadata: Codable {
        let addedAt: Date
        var contentHash: String?  // For bySource entries, link to content
    }
    
    /// In-memory favorites
    private var favoritesByContent: Set<String> = []  // contentHash
    private var favoritesBySource: Set<String> = []   // sourceKey (hash of sourceURL+entryPath)
    private var sourceToContent: [String: String] = [:] // sourceKey → contentHash mapping
    
    /// Hybrid favorites file URL
    private var hybridFavoritesFileURL: URL {
        return baseDirectory.appendingPathComponent("favorites_hybrid.json")
    }
    
    private func loadFavorites() {
        let fileURL = hybridFavoritesFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            favoritesByContent = []
            favoritesBySource = []
            sourceToContent = [:]
            print("[CacheManager] No hybrid favorites file")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(HybridFavoritesFile.self, from: data)
            
            favoritesLock.lock()
            favoritesByContent = Set(file.byContent.keys)
            favoritesBySource = Set(file.bySource.keys)
            
            // Build sourceToContent mapping
            sourceToContent = [:]
            for (sourceKey, metadata) in file.bySource {
                if let contentHash = metadata.contentHash {
                    sourceToContent[sourceKey] = contentHash
                }
            }
            favoritesLock.unlock()
            
            print("[CacheManager] Loaded \(favoritesBySource.count) source favorites, \(favoritesByContent.count) content favorites")
        } catch {
            print("[CacheManager] Failed to load favorites: \(error)")
            favoritesByContent = []
            favoritesBySource = []
            sourceToContent = [:]
        }
    }
    
    private func saveFavorites() {
        favoritesLock.lock()
        let contentFavs = favoritesByContent
        let sourceFavs = favoritesBySource
        let s2c = sourceToContent
        favoritesLock.unlock()
        
        var byContent: [String: FavoriteMetadata] = [:]
        for hash in contentFavs {
            byContent[hash] = FavoriteMetadata(addedAt: Date(), contentHash: nil)
        }
        
        var bySource: [String: FavoriteMetadata] = [:]
        for key in sourceFavs {
            bySource[key] = FavoriteMetadata(addedAt: Date(), contentHash: s2c[key])
        }
        
        let file = HybridFavoritesFile(version: 2, byContent: byContent, bySource: bySource)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(file)
            try data.write(to: hybridFavoritesFileURL)
        } catch {
            print("[CacheManager] Failed to save favorites: \(error)")
        }
    }
    
    /// Generate source key (hash of sourceURL + entryPath)
    func sourceKey(sourceURL: URL, entryPath: String) -> String {
        let fullPath = sourceURL.path + "/" + entryPath
        return hashString(fullPath)
    }
    
    /// Get favorite status for an entry
    func getFavoriteStatus(sourceURL: URL, entryPath: String, contentHash: String?) -> FavoriteStatus {
        favoritesLock.lock()
        defer { favoritesLock.unlock() }
        
        // Check source first (direct favorite in this source)
        let sKey = sourceKey(sourceURL: sourceURL, entryPath: entryPath)
        if favoritesBySource.contains(sKey) {
            return .direct
        }
        
        // Check content (inherited from other source)
        if let cHash = contentHash, favoritesByContent.contains(cHash) {
            return .inherited
        }
        
        return .none
    }
    
    /// Check if directly favorited in this source (for delete protection)
    func isDirectFavorite(sourceURL: URL, entryPath: String) -> Bool {
        let sKey = sourceKey(sourceURL: sourceURL, entryPath: entryPath)
        favoritesLock.lock()
        let result = favoritesBySource.contains(sKey)
        favoritesLock.unlock()
        return result
    }
    
    /// Toggle favorite - adds/removes from both bySource and byContent
    /// Returns new FavoriteStatus
    func toggleFavorite(sourceURL: URL, entryPath: String, contentHash: String?) -> FavoriteStatus {
        let sKey = sourceKey(sourceURL: sourceURL, entryPath: entryPath)
        
        favoritesLock.lock()
        
        let wasDirectFavorite = favoritesBySource.contains(sKey)
        
        if wasDirectFavorite {
            // Remove from source
            favoritesBySource.remove(sKey)
            sourceToContent.removeValue(forKey: sKey)
            // Note: We don't remove from byContent - other sources may still reference it
            
            favoritesLock.unlock()
            saveFavorites()
            
            // Check if still inherited
            if let cHash = contentHash {
                favoritesLock.lock()
                let stillInherited = favoritesByContent.contains(cHash)
                favoritesLock.unlock()
                return stillInherited ? .inherited : .none
            }
            return .none
        } else {
            // Add to source
            favoritesBySource.insert(sKey)
            if let cHash = contentHash {
                sourceToContent[sKey] = cHash
                // Add to content as well
                favoritesByContent.insert(cHash)
            }
            
            favoritesLock.unlock()
            saveFavorites()
            
            return .direct
        }
    }
    
    /// Get content hash for a path (if cached)
    func getContentHashForPath(_ path: String) -> String? {
        let pHash = pathHash(for: path)
        return getContentHash(for: pHash)
    }
    
    // Legacy compatibility methods (deprecated, for migration)
    
    func isFavorite(_ contentHash: String) -> Bool {
        favoritesLock.lock()
        let result = favoritesByContent.contains(contentHash)
        favoritesLock.unlock()
        return result
    }
    
    func isFavoriteByPath(_ path: String) -> Bool {
        let pHash = pathHash(for: path)
        guard let cHash = getContentHash(for: pHash) else {
            return false
        }
        return isFavorite(cHash)
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
    
    // MARK: - Last Position Management (#52)
    
    /// Load last positions from disk
    private func loadLastPositions() {
        guard FileManager.default.fileExists(atPath: lastPositionFileURL.path) else {
            lastPositions = [:]
            return
        }
        
        do {
            let data = try Data(contentsOf: lastPositionFileURL)
            positionLock.lock()
            lastPositions = try JSONDecoder().decode([String: Int].self, from: data)
            positionLock.unlock()
            print("[CacheManager] Loaded last positions with \(lastPositions.count) entries")
        } catch {
            print("[CacheManager] Failed to load last positions: \(error)")
            lastPositions = [:]
        }
    }
    
    /// Save last positions to disk
    private func saveLastPositions() {
        positionLock.lock()
        let currentPositions = lastPositions
        positionLock.unlock()
        
        do {
            let data = try JSONEncoder().encode(currentPositions)
            try data.write(to: lastPositionFileURL)
        } catch {
            print("[CacheManager] Failed to save last positions: \(error)")
        }
    }
    
    /// Get last viewed position for a source
    /// - Parameter sourceURL: The URL of the source (folder or archive)
    /// - Returns: The last viewed index, or nil if not found
    func getLastPosition(for sourceURL: URL) -> Int? {
        let key = hashString(sourceURL.path)
        positionLock.lock()
        let result = lastPositions[key]
        positionLock.unlock()
        return result
    }
    
    /// Set last viewed position for a source
    /// - Parameters:
    ///   - sourceURL: The URL of the source (folder or archive)
    ///   - index: The current viewed index
    func setLastPosition(for sourceURL: URL, index: Int) {
        let key = hashString(sourceURL.path)
        positionLock.lock()
        lastPositions[key] = index
        positionLock.unlock()
        saveLastPositions()
    }
    
    /// Clear last position for a source (optional, for cleanup)
    func clearLastPosition(for sourceURL: URL) {
        let key = hashString(sourceURL.path)
        positionLock.lock()
        lastPositions.removeValue(forKey: key)
        positionLock.unlock()
        saveLastPositions()
    }
}
