//
//  CacheManager.swift
//  Erimil
//
//  Cache infrastructure with hash-based privacy design
//  Stores thumbnails and metadata in ~/Library/Application Support/Erimil/
//  Updated: S017 (2026-01-24) - Last position management (#52)
//  Updated: S018 (2026-01-24) - Source settings with reading direction (#54)
//

import Foundation
import AppKit
import CryptoKit

/// Per-source settings (#54)
struct SourceSettings: Codable {
    var lastPosition: Int?
    var readingDirection: ReadingDirection?  // nil = use global default
    // var singlePageIndices: Set<Int>?      // #56: Reserved for future use
    
    /// Check if settings are empty (can be removed)
    var isEmpty: Bool {
        lastPosition == nil && readingDirection == nil
    }
}

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
    
    /// ~/Library/Application Support/Erimil/last_position.json (legacy, for migration)
    private let lastPositionFileURL: URL
    
    /// ~/Library/Application Support/Erimil/source_settings.json (#54)
    private let sourceSettingsFileURL: URL
    
    // MARK: - In-Memory Cache
    
    /// pathHash → contentHash mapping (loaded from index.json)
    private var pathIndex: [String: String] = [:]
    private let indexLock = NSLock()
    
    /// contentHash → thumbnail (memory cache, thread-safe)
    private let thumbnailCache = NSCache<NSString, NSImage>()
    
    /// Favorites lock for thread-safety
    private let favoritesLock = NSLock()
    
    /// Source settings per source (#54, replaces lastPositions)
    private var sourceSettings: [String: SourceSettings] = [:]
    private let settingsLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // Setup base directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("Erimil", isDirectory: true)
        cacheDirectory = baseDirectory.appendingPathComponent("cache", isDirectory: true)
        indexFileURL = baseDirectory.appendingPathComponent("index.json")
        favoritesFileURL = baseDirectory.appendingPathComponent("favorites.json")
        lastPositionFileURL = baseDirectory.appendingPathComponent("last_position.json")
        sourceSettingsFileURL = baseDirectory.appendingPathComponent("source_settings.json")
        
        // Configure cache
        thumbnailCache.countLimit = 200
        
        // Create directories if needed
        createDirectoriesIfNeeded()
        
        // Load index and favorites
        loadIndex()
        loadFavorites()
        
        // Load source settings (with migration from legacy format)
        loadSourceSettings()
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
    
    /// In-memory favorites (simplified sets for fast lookup)
    private var favoritesByContent: Set<String> = []  // contentHashes
    private var favoritesBySource: Set<String> = []   // sourceKeys
    private var sourceToContent: [String: String] = [:] // sourceKey → contentHash
    
    private func loadFavorites() {
        let fm = FileManager.default
        let hybridURL = baseDirectory.appendingPathComponent("favorites_hybrid.json")
        
        // Try hybrid format first
        if fm.fileExists(atPath: hybridURL.path) {
            do {
                let data = try Data(contentsOf: hybridURL)
                let hybrid = try JSONDecoder().decode(HybridFavoritesFile.self, from: data)
                
                favoritesLock.lock()
                favoritesByContent = Set(hybrid.byContent.keys)
                favoritesBySource = Set(hybrid.bySource.keys)
                sourceToContent = [:]
                for (sourceKey, metadata) in hybrid.bySource {
                    if let cHash = metadata.contentHash {
                        sourceToContent[sourceKey] = cHash
                    }
                }
                favoritesLock.unlock()
                
                print("[CacheManager] Loaded hybrid favorites: \(favoritesByContent.count) by content, \(favoritesBySource.count) by source")
                return
            } catch {
                print("[CacheManager] Failed to load hybrid favorites: \(error)")
            }
        }
        
        // Legacy format migration
        if fm.fileExists(atPath: favoritesFileURL.path) {
            do {
                let data = try Data(contentsOf: favoritesFileURL)
                let legacyFavorites = try JSONDecoder().decode([String].self, from: data)
                
                favoritesLock.lock()
                favoritesByContent = Set(legacyFavorites)
                favoritesBySource = []
                sourceToContent = [:]
                favoritesLock.unlock()
                
                print("[CacheManager] Migrated \(legacyFavorites.count) legacy favorites")
                saveFavorites()  // Save in new format
                return
            } catch {
                print("[CacheManager] Failed to load legacy favorites: \(error)")
            }
        }
        
        // No favorites file
        favoritesByContent = []
        favoritesBySource = []
        sourceToContent = [:]
    }
    
    private func saveFavorites() {
        favoritesLock.lock()
        
        var byContent: [String: FavoriteMetadata] = [:]
        for cHash in favoritesByContent {
            byContent[cHash] = FavoriteMetadata(addedAt: Date(), contentHash: nil)
        }
        
        var bySource: [String: FavoriteMetadata] = [:]
        for sKey in favoritesBySource {
            let cHash = sourceToContent[sKey]
            bySource[sKey] = FavoriteMetadata(addedAt: Date(), contentHash: cHash)
        }
        
        favoritesLock.unlock()
        
        let hybrid = HybridFavoritesFile(version: 2, byContent: byContent, bySource: bySource)
        let hybridURL = baseDirectory.appendingPathComponent("favorites_hybrid.json")
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(hybrid)
            try data.write(to: hybridURL)
        } catch {
            print("[CacheManager] Failed to save favorites: \(error)")
        }
    }
    
    /// Generate source key for favorite lookup
    private func sourceKey(sourceURL: URL, entryPath: String) -> String {
        return hashString(sourceURL.absoluteString + "::" + entryPath)
    }
    
    /// Get favorite status for an entry
    func getFavoriteStatus(sourceURL: URL, entryPath: String, contentHash: String?) -> FavoriteStatus {
        let sKey = sourceKey(sourceURL: sourceURL, entryPath: entryPath)
        
        favoritesLock.lock()
        let isDirect = favoritesBySource.contains(sKey)
        let isInherited = contentHash != nil && favoritesByContent.contains(contentHash!)
        favoritesLock.unlock()
        
        if isDirect {
            return .direct
        } else if isInherited {
            return .inherited
        }
        return .none
    }
    
    /// Toggle favorite status for an entry
    /// Returns new status after toggle
    @discardableResult
    func toggleFavorite(sourceURL: URL, entryPath: String, contentHash: String?) -> FavoriteStatus {
        let sKey = sourceKey(sourceURL: sourceURL, entryPath: entryPath)
        
        favoritesLock.lock()
        
        if favoritesBySource.contains(sKey) {
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

    /// Check if entry is directly favorited in this source (not inherited)
    func isDirectFavorite(sourceURL: URL, entryPath: String) -> Bool {
        let sKey = sourceKey(sourceURL: sourceURL, entryPath: entryPath)
        favoritesLock.lock()
        let result = favoritesBySource.contains(sKey)
        favoritesLock.unlock()
        return result
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
    
    // MARK: - Source Settings Management (#54)
    
    /// Load source settings (with migration from legacy last_position.json)
    private func loadSourceSettings() {
        let fm = FileManager.default
        
        // Try new format first
        if fm.fileExists(atPath: sourceSettingsFileURL.path) {
            do {
                let data = try Data(contentsOf: sourceSettingsFileURL)
                settingsLock.lock()
                sourceSettings = try JSONDecoder().decode([String: SourceSettings].self, from: data)
                settingsLock.unlock()
                print("[CacheManager] Loaded source settings with \(sourceSettings.count) entries")
                return
            } catch {
                print("[CacheManager] Failed to load source settings: \(error)")
            }
        }
        
        // Migration from legacy last_position.json
        if fm.fileExists(atPath: lastPositionFileURL.path) {
            do {
                let data = try Data(contentsOf: lastPositionFileURL)
                let legacyPositions = try JSONDecoder().decode([String: Int].self, from: data)
                
                settingsLock.lock()
                sourceSettings = [:]
                for (key, position) in legacyPositions {
                    sourceSettings[key] = SourceSettings(lastPosition: position, readingDirection: nil)
                }
                settingsLock.unlock()
                
                print("[CacheManager] Migrated \(legacyPositions.count) entries from last_position.json")
                saveSourceSettings()
                
                // Remove legacy file after successful migration
                try? fm.removeItem(at: lastPositionFileURL)
                print("[CacheManager] Removed legacy last_position.json")
                return
            } catch {
                print("[CacheManager] Failed to migrate legacy positions: \(error)")
            }
        }
        
        // No settings file
        sourceSettings = [:]
    }
    
    /// Save source settings to disk
    private func saveSourceSettings() {
        settingsLock.lock()
        let currentSettings = sourceSettings
        settingsLock.unlock()
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(currentSettings)
            try data.write(to: sourceSettingsFileURL)
        } catch {
            print("[CacheManager] Failed to save source settings: \(error)")
        }
    }
    
    /// Get settings for a source
    func getSourceSettings(for sourceURL: URL) -> SourceSettings? {
        let key = hashString(sourceURL.path)
        settingsLock.lock()
        let result = sourceSettings[key]
        settingsLock.unlock()
        return result
    }
    
    /// Update settings for a source
    func updateSourceSettings(for sourceURL: URL, update: (inout SourceSettings) -> Void) {
        let key = hashString(sourceURL.path)
        settingsLock.lock()
        var settings = sourceSettings[key] ?? SourceSettings()
        update(&settings)
        
        // Remove if empty
        if settings.isEmpty {
            sourceSettings.removeValue(forKey: key)
        } else {
            sourceSettings[key] = settings
        }
        settingsLock.unlock()
        saveSourceSettings()
    }
    
    // MARK: - Last Position (convenience methods, backward compatible)
    
    /// Get last viewed position for a source
    /// - Parameter sourceURL: The URL of the source (folder or archive)
    /// - Returns: The last viewed index, or nil if not found
    func getLastPosition(for sourceURL: URL) -> Int? {
        return getSourceSettings(for: sourceURL)?.lastPosition
    }
    
    /// Set last viewed position for a source
    /// - Parameters:
    ///   - sourceURL: The URL of the source (folder or archive)
    ///   - index: The current viewed index
    func setLastPosition(for sourceURL: URL, index: Int) {
        updateSourceSettings(for: sourceURL) { settings in
            settings.lastPosition = index
        }
    }
    
    /// Clear last position for a source (optional, for cleanup)
    func clearLastPosition(for sourceURL: URL) {
        updateSourceSettings(for: sourceURL) { settings in
            settings.lastPosition = nil
        }
    }
    
    // MARK: - Reading Direction (#54)
    
    /// Get reading direction for a source (nil = use global default)
    func getReadingDirection(for sourceURL: URL) -> ReadingDirection? {
        return getSourceSettings(for: sourceURL)?.readingDirection
    }
    
    /// Get effective reading direction (per-source if set, otherwise global)
    func getEffectiveReadingDirection(for sourceURL: URL) -> ReadingDirection {
        if let perSource = getReadingDirection(for: sourceURL) {
            return perSource
        }
        return AppSettings.shared.defaultReadingDirection
    }
    
    /// Set reading direction for a source (nil to use global default)
    func setReadingDirection(for sourceURL: URL, direction: ReadingDirection?) {
        updateSourceSettings(for: sourceURL) { settings in
            settings.readingDirection = direction
        }
        print("[CacheManager] Set reading direction for \(sourceURL.lastPathComponent): \(direction?.displayName ?? "global default")")
    }
    
    /// Toggle reading direction for a source
    /// If currently using global default, sets to opposite of global
    /// If already per-source, toggles between ltr/rtl
    /// Returns the new effective direction
    @discardableResult
    func toggleReadingDirection(for sourceURL: URL) -> ReadingDirection {
        let current = getEffectiveReadingDirection(for: sourceURL)
        let new = current.toggled
        setReadingDirection(for: sourceURL, direction: new)
        return new
    }
}
