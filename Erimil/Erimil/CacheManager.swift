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
import os

/// Per-source settings (#54, #56)
struct SourceSettings: Codable {
    var lastPosition: Int?
    var readingDirection: ReadingDirection?  // nil = use global default
    var singlePageIndices: Set<Int>?         // #56: Manual single page markers
    var deskewEnabled: Bool?                 // #101: nil = off (default off)
    
    /// Check if settings are empty (can be removed)
    var isEmpty: Bool {
        lastPosition == nil && readingDirection == nil && (singlePageIndices == nil || singlePageIndices!.isEmpty) && deskewEnabled == nil
    }
}

/// Bookmark (栞) - Section marker within a source (#62)
struct Bookmark: Codable, Identifiable {
    let id: UUID
    var imageIndex: Int      // Section starts at this image
    var name: String         // Section name (default: filename)
    var createdAt: Date
}

/// Options for metadata carry-over on export (#105)
struct MetadataCarryOverOptions {
    var favorites: Bool = true
    var bookmarks: Bool = true
    var readingDirection: Bool = true
    var singlePageMarkers: Bool = true
    
    static let all = MetadataCarryOverOptions()
    static let none = MetadataCarryOverOptions(favorites: false, bookmarks: false, readingDirection: false, singlePageMarkers: false)
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
    
    /// ~/Library/Application Support/Erimil/bookmarks.json (#62)
    private let bookmarksFileURL: URL
    
    /// ~/Library/Application Support/Erimil/deskew_angles.json (#101)
    private let deskewAnglesFileURL: URL
    
    // MARK: - Cache Format
    
    /// Magic bytes for .ecache format ("ERIM" header)
    private static let ecacheMagic = Data([0x45, 0x52, 0x49, 0x4D])
    
    // MARK: - In-Memory Cache
    
    /// pathHash → contentHash mapping (loaded from index.json)
    private var pathIndex: [String: String] = [:]
    private let indexLock = NSLock()
    
    /// #134 P4: path → pathHash cache (SHA256 is deterministic, avoid recomputation)
    /// In-memory only, no persistence needed.
    private var pathHashCache: [String: String] = [:]
    private let pathHashLock = NSLock()
    
    /// contentHash → thumbnail (memory cache, thread-safe)
    private let thumbnailCache = NSCache<NSString, NSImage>()
    
    /// contentHash → full-size image (memory cache, thread-safe)
    /// #134: Prevents redundant fullImage decode when SwiftUI body re-evaluates
    private let fullImageCache = NSCache<NSString, NSImage>()
    
    /// Favorites lock for thread-safety
    private let favoritesLock = NSLock()
    
    /// Source settings per source (#54, replaces lastPositions)
    private var sourceSettings: [String: SourceSettings] = [:]
    private let settingsLock = NSLock()
    
    /// Aspect ratio cache for spread detection (#67 Phase 3)
    /// In-memory only - no persistence needed
    /// Key: sourceURL.path + "/" + entryPath
    private var aspectRatioCache: [String: CGFloat] = [:]
    private let aspectRatioLock = NSLock()
    
    /// Bookmarks per source (#62)
    /// Key: sourceHash, Value: sorted array of Bookmark
    private var bookmarksBySource: [String: [Bookmark]] = [:]
    private let bookmarksLock = NSLock()
    
    /// Deskew angles per source, per page (#101)
    /// Key: sourceHash, Value: [pageEntryPath: angle in radians]
    private var deskewAnglesBySource: [String: [String: CGFloat]] = [:]
    private let deskewLock = NSLock()
    
    // MARK: - Async Write Infrastructure (#87)
    
    /// Serial background queue for all JSON writes (prevents UI blocking)
    private let writeQueue = DispatchQueue(label: "jp.pocketstudio.zem.Erimil.CacheManager.write", qos: .utility)
    
    /// Debounce interval for coalescing rapid successive writes
    private let debounceInterval: TimeInterval = 0.5
    
    /// Pending write work items (one per JSON file, for cancel/reschedule)
    private var indexSaveWorkItem: DispatchWorkItem?
    private var favoritesSaveWorkItem: DispatchWorkItem?
    private var settingsSaveWorkItem: DispatchWorkItem?
    private var bookmarksSaveWorkItem: DispatchWorkItem?
    private var deskewSaveWorkItem: DispatchWorkItem?   // #101
    private let writeLock = NSLock()
    
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
        bookmarksFileURL = baseDirectory.appendingPathComponent("bookmarks.json")
        deskewAnglesFileURL = baseDirectory.appendingPathComponent("deskew_angles.json")  // #101
        
        // Configure cache
        // #134 P3: Use totalCostLimit (bytes) instead of countLimit for thumbnails.
        // ~180px thumbnails are ~50-100KB each; 100MB holds ~1000-2000 thumbnails,
        // eliminating eviction-driven disk I/O for large sources (e.g. 298-page PDF).
        thumbnailCache.totalCostLimit = 100 * 1024 * 1024  // 100MB
        // #134 P3: Full-size images are ~4-5MB each; 5 is sufficient for Viewer/Slide
        // navigation (current + neighbors). 200 was a memory explosion risk (~940MB).
        fullImageCache.countLimit = 5
        
        // Create directories if needed
        createDirectoriesIfNeeded()
        
        // Load index and favorites
        loadIndex()
        loadFavorites()
        
        // Load source settings (with migration from legacy format)
        loadSourceSettings()
        
        // Load bookmarks (#62)
        loadBookmarks()
        
        // Load deskew angles (#101)
        loadDeskewAngles()
    }
    
    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        
        do {
            if !fm.fileExists(atPath: baseDirectory.path) {
                try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
                Logger.cache.info("Created base directory: \(self.baseDirectory.path)")
            }
            
            if !fm.fileExists(atPath: cacheDirectory.path) {
                try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                Logger.cache.info("Created cache directory: \(self.cacheDirectory.path)")
            }
        } catch {
            Logger.cache.error("Failed to create directories: \(error, privacy: .public)")
        }
    }
    
    // MARK: - Write Flush (#87)
    
    /// Flush all pending debounced writes synchronously.
    /// Call on app termination to prevent data loss.
    func flushPendingWrites() {
        writeLock.lock()
        indexSaveWorkItem?.cancel()
        favoritesSaveWorkItem?.cancel()
        settingsSaveWorkItem?.cancel()
        bookmarksSaveWorkItem?.cancel()
        deskewSaveWorkItem?.cancel()         // #101
        indexSaveWorkItem = nil
        favoritesSaveWorkItem = nil
        settingsSaveWorkItem = nil
        bookmarksSaveWorkItem = nil
        deskewSaveWorkItem = nil             // #101
        writeLock.unlock()
        
        // Perform all saves synchronously on writeQueue
        writeQueue.sync {
            self.performSaveIndex()
            self.performSaveFavorites()
            self.performSaveSourceSettings()
            self.performSaveBookmarks()
            self.performSaveDeskewAngles()   // #101
        }
        Logger.cache.debug("Flushed all pending writes")
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
    
    /// #134 P3: Estimate in-memory bitmap size for NSCache cost accounting.
    /// Returns width × height × 4 (RGBA bytes). Used with totalCostLimit.
    private func estimatedBitmapCost(of image: NSImage) -> Int {
        let size = image.size
        return Int(size.width * size.height) * 4
    }
    
    /// Calculate content hash for image data
    func contentHash(for imageData: Data) -> String {
        return hashData(imageData)
    }
    
    /// Calculate path hash for a file path (cached)
    /// #134 P4: SHA256 is deterministic — cache results to avoid recomputation.
    func pathHash(for path: String) -> String {
        pathHashLock.lock()
        if let cached = pathHashCache[path] {
            pathHashLock.unlock()
            return cached
        }
        pathHashLock.unlock()
        let hash = hashString(path)
        pathHashLock.lock()
        pathHashCache[path] = hash
        pathHashLock.unlock()
        return hash
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
            Logger.cache.info("Loaded index with \(self.pathIndex.count, privacy: .public) entries")
        } catch {
            Logger.cache.error("Failed to load index: \(error, privacy: .public)")
            pathIndex = [:]
        }
    }
    
    private func saveIndex() {
        writeLock.lock()
        indexSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performSaveIndex()
        }
        indexSaveWorkItem = item
        writeQueue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        writeLock.unlock()
    }
    
    private func performSaveIndex() {
        indexLock.lock()
        let currentIndex = pathIndex
        indexLock.unlock()
        
        do {
            let data = try JSONEncoder().encode(currentIndex)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            Logger.cache.error("Failed to save index: \(error, privacy: .public)")
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
        let filename = contentHash.replacingOccurrences(of: "sha256:", with: "") + ".ecache"
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
        
        guard let raw = try? Data(contentsOf: url) else {
            return nil
        }
        
        // Strip ERIM magic header if present (#146)
        let jpegData: Data
        if raw.prefix(4) == Self.ecacheMagic {
            jpegData = Data(raw.dropFirst(4))
        } else {
            jpegData = raw // Legacy format (no header)
        }
        
        // #134 P6: Use materialize to force complete pixel decode.
        guard let image = ImageUtilities.materializedImage(from: jpegData) else {
            // Fallback to NSImage if CGImageSource fails
            guard let fallback = NSImage(data: jpegData) else {
                return nil
            }
            thumbnailCache.setObject(fallback, forKey: contentHash as NSString, cost: estimatedBitmapCost(of: fallback))
            return fallback
        }
        
        // Add to memory cache
        thumbnailCache.setObject(image, forKey: contentHash as NSString, cost: estimatedBitmapCost(of: image))
        
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
        thumbnailCache.setObject(image, forKey: contentHash as NSString, cost: estimatedBitmapCost(of: image))
        
        // Save to disk
        saveThumbnailToDisk(image, for: contentHash)
    }
    
    /// Save thumbnail to memory cache only (tile sheet preload — skips disk I/O)
    func saveThumbnailToMemory(_ image: NSImage, for contentHash: String) {
        thumbnailCache.setObject(image, forKey: contentHash as NSString, cost: estimatedBitmapCost(of: image))
    }
    
    // MARK: - Full Image Memory Cache (#134)
    
    /// Get full-size image from memory cache
    func getFullImageFromMemory(for contentHash: String) -> NSImage? {
        return fullImageCache.object(forKey: contentHash as NSString)
    }
    
    /// Save full-size image to memory cache (no disk persistence)
    func cacheFullImage(_ image: NSImage, for contentHash: String) {
        fullImageCache.setObject(image, forKey: contentHash as NSString)
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
                self.favoritesByContent = Set(hybrid.byContent.keys)
                self.favoritesBySource = Set(hybrid.bySource.keys)
                self.sourceToContent = [:]
                for (sourceKey, metadata) in hybrid.bySource {
                    if let cHash = metadata.contentHash {
                        self.sourceToContent[sourceKey] = cHash
                    }
                }
                favoritesLock.unlock()
                
                Logger.cache.info("Loaded hybrid favorites: \(self.favoritesByContent.count, privacy: .public) by content, \(self.favoritesBySource.count, privacy: .public) by source")
                return
            } catch {
                Logger.cache.error("Failed to load hybrid favorites: \(error, privacy: .public)")
            }
        }
        
        // Legacy format migration
        if fm.fileExists(atPath: favoritesFileURL.path) {
            do {
                let data = try Data(contentsOf: favoritesFileURL)
                let legacyFavorites = try JSONDecoder().decode([String].self, from: data)
                
                favoritesLock.lock()
                self.favoritesByContent = Set(legacyFavorites)
                self.favoritesBySource = []
                self.sourceToContent = [:]
                favoritesLock.unlock()
                
                Logger.cache.debug("Migrated \(legacyFavorites.count, privacy: .public) legacy favorites")
                saveFavorites()  // Save in new format
                return
            } catch {
                Logger.cache.error("Failed to load legacy favorites: \(error, privacy: .public)")
            }
        }
        
        // No favorites file
        self.favoritesByContent = []
        self.favoritesBySource = []
        self.sourceToContent = [:]
    }
    
    private func saveFavorites() {
        writeLock.lock()
        favoritesSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performSaveFavorites()
        }
        favoritesSaveWorkItem = item
        writeQueue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        writeLock.unlock()
    }
    
    private func performSaveFavorites() {
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
            try data.write(to: hybridURL, options: .atomic)
        } catch {
            Logger.cache.error("Failed to save favorites: \(error, privacy: .public)")
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
    
    // MARK: - Metadata Carry-Over (#105)
    
    /// Add a direct favorite without toggling (idempotent)
    func setDirectFavorite(sourceURL: URL, entryPath: String, contentHash: String?) {
        let sKey = sourceKey(sourceURL: sourceURL, entryPath: entryPath)
        favoritesLock.lock()
        let alreadySet = favoritesBySource.contains(sKey)
        if !alreadySet {
            favoritesBySource.insert(sKey)
            if let cHash = contentHash {
                sourceToContent[sKey] = cHash
                favoritesByContent.insert(cHash)
            }
        }
        favoritesLock.unlock()
        if !alreadySet {
            saveFavorites()
        }
    }
    
    /// Copy metadata from source to destination with index remapping (#105)
    ///
    /// - Parameters:
    ///   - sourceURL: Original source URL
    ///   - destinationURL: Exported file URL
    ///   - entries: Original entries list
    ///   - pathsToRemove: Paths excluded from export
    ///   - contentHashes: Path → contentHash mapping
    ///   - newPathForSurvivingIndex: Closure to generate new entry path for PDF (nil = keep original path)
    ///   - options: Which metadata types to carry over
    func copyMetadata(
        from sourceURL: URL,
        to destinationURL: URL,
        entries: [ImageEntry],
        pathsToRemove: Set<String>,
        contentHashes: [String: String],
        newPathForSurvivingIndex: ((_ newIndex: Int, _ originalPath: String) -> String)? = nil,
        options: MetadataCarryOverOptions = .all
    ) {
        // 1. Build index mapping: originalIndex → newIndex
        var indexMapping: [Int: Int] = [:]
        var survivingEntries: [(originalIndex: Int, entry: ImageEntry, newIndex: Int)] = []
        var newIdx = 0
        for (originalIdx, entry) in entries.enumerated() {
            if !pathsToRemove.contains(entry.path) {
                indexMapping[originalIdx] = newIdx
                survivingEntries.append((originalIdx, entry, newIdx))
                newIdx += 1
            }
        }
        
        // 2. Copy favorites
        var favCount = 0
        if options.favorites {
            for item in survivingEntries {
                if isDirectFavorite(sourceURL: sourceURL, entryPath: item.entry.path) {
                    let newPath = newPathForSurvivingIndex?(item.newIndex, item.entry.path) ?? item.entry.path
                    let cHash = contentHashes[item.entry.path]
                    setDirectFavorite(sourceURL: destinationURL, entryPath: newPath, contentHash: nil)
                    favCount += 1
                    Logger.cache.debug("★ copied: \(item.entry.path) → \(newPath)")
                }
            }
        }
        
        // 3. Copy bookmarks (remap indices, drop bookmarks on excluded pages)
        var bookmarkCount = 0
        if options.bookmarks {
            let oldBookmarks = getBookmarks(for: sourceURL)
            for bookmark in oldBookmarks {
                if let newIndex = indexMapping[bookmark.imageIndex] {
                    addBookmark(for: destinationURL, at: newIndex, name: bookmark.name)
                    bookmarkCount += 1
                    Logger.cache.debug("栞 copied: \(bookmark.name) index \(bookmark.imageIndex) → \(newIndex)")
                }
            }
        }
        
        // 4. Copy reading direction
        if options.readingDirection {
            if let direction = getReadingDirection(for: sourceURL) {
                setReadingDirection(for: destinationURL, direction: direction)
            }
        }
        
        // 5. Copy single page markers (remap indices, drop markers on excluded pages)
        if options.singlePageMarkers {
            let oldMarkers = getSinglePageIndices(for: sourceURL)
            if !oldMarkers.isEmpty {
                var newMarkers: Set<Int> = []
                for oldIndex in oldMarkers {
                    if let newIndex = indexMapping[oldIndex] {
                        newMarkers.insert(newIndex)
                    }
                }
                if !newMarkers.isEmpty {
                    updateSourceSettings(for: destinationURL) { settings in
                        settings.singlePageIndices = newMarkers
                    }
                }
            }
        }
        
        Logger.cache.info("Metadata copied: \(sourceURL.lastPathComponent) → \(destinationURL.lastPathComponent) (★:\(favCount) 栞:\(bookmarkCount) dir:\(options.readingDirection) V:\(options.singlePageMarkers)) surviving:\(survivingEntries.count)/\(entries.count)")
    }
    
    /// Detect PDF entry path format and generate new path for remapped index (#105)
    /// Note: newIndex is 0-based (from copyMetadata), but PDF paths are 1-based
    static func pdfEntryPathRemapper(samplePath: String) -> (_ newIndex: Int, _ originalPath: String) -> String {
        // Detect pattern: "page_003" → prefix "page_", padding 3
        if let range = samplePath.range(of: "\\d+$", options: .regularExpression) {
            let prefix = String(samplePath[samplePath.startIndex..<range.lowerBound])
            let digitStr = String(samplePath[range])
            let padding = digitStr.count
            return { newIndex, _ in
                prefix + String(format: "%0\(padding)d", newIndex + 1)  // 0-based → 1-based
            }
        }
        // Fallback
        return { newIndex, _ in "page_\(newIndex + 1)" }
    }
    
    private func saveThumbnailToDisk(_ image: NSImage, for contentHash: String) {
        let url = thumbnailURL(for: contentHash)
        
        // Skip if already exists
        guard !FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        
        // #146: Use CGImageDestination for efficient JPEG encoding with ERIM header
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Logger.cache.error("Failed to get CGImage from thumbnail")
            return
        }
        
        let jpegData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpegData, "public.jpeg" as CFString, 1, nil) else {
            Logger.cache.error("Failed to create CGImageDestination")
            return
        }
        
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.6]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            Logger.cache.error("Failed to finalize CGImageDestination")
            return
        }
        
        // Prepend ERIM magic header
        var output = Self.ecacheMagic
        output.append(jpegData as Data)
        
        do {
            try output.write(to: url, options: .atomic)
        } catch {
            Logger.cache.error("Failed to save thumbnail: \(error, privacy: .public)")
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
        fullImageCache.removeAllObjects()
        pathHashLock.lock()
        pathHashCache.removeAll()
        pathHashLock.unlock()
        Logger.cache.debug("Memory cache cleared")
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
            
            Logger.cache.debug("All cache cleared")
        } catch {
            Logger.cache.error("Failed to clear cache: \(error, privacy: .public)")
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
                Logger.cache.info("Loaded source settings with \(self.sourceSettings.count, privacy: .public) entries")
                return
            } catch {
                Logger.cache.error("Failed to load source settings: \(error, privacy: .public)")
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
                
                Logger.cache.debug("Migrated \(legacyPositions.count, privacy: .public) entries from last_position.json")
                saveSourceSettings()
                
                // Remove legacy file after successful migration
                try? fm.removeItem(at: lastPositionFileURL)
                Logger.cache.debug("Removed legacy last_position.json")
                return
            } catch {
                Logger.cache.error("Failed to migrate legacy positions: \(error, privacy: .public)")
            }
        }
        
        // No settings file
        sourceSettings = [:]
    }
    
    /// Save source settings to disk
    private func saveSourceSettings() {
        writeLock.lock()
        settingsSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performSaveSourceSettings()
        }
        settingsSaveWorkItem = item
        writeQueue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        writeLock.unlock()
    }
    
    private func performSaveSourceSettings() {
        settingsLock.lock()
        let currentSettings = sourceSettings
        settingsLock.unlock()
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(currentSettings)
            try data.write(to: sourceSettingsFileURL, options: .atomic)
        } catch {
            Logger.cache.error("Failed to save source settings: \(error, privacy: .public)")
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
        Logger.cache.debug("Set reading direction for \(sourceURL.lastPathComponent): \(direction?.displayName ?? "global default")")
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
    
    // MARK: - Single Page Markers (#56)
    
    /// Get single page indices for a source
    func getSinglePageIndices(for sourceURL: URL) -> Set<Int> {
        return getSourceSettings(for: sourceURL)?.singlePageIndices ?? []
    }
    
    /// Toggle single page marker for an index
    /// Returns true if marker was added, false if removed
    @discardableResult
    func toggleSinglePageMarker(for sourceURL: URL, at index: Int) -> Bool {
        var added = false
        updateSourceSettings(for: sourceURL) { settings in
            var indices = settings.singlePageIndices ?? []
            if indices.contains(index) {
                indices.remove(index)
                added = false
            } else {
                indices.insert(index)
                added = true
            }
            settings.singlePageIndices = indices.isEmpty ? nil : indices
        }
        Logger.cache.debug("Single page marker at \(index, privacy: .public): \(added ? "added" : "removed")")
        return added
    }
    
    /// Check if index has single page marker
    func hasSinglePageMarker(for sourceURL: URL, at index: Int) -> Bool {
        return getSinglePageIndices(for: sourceURL).contains(index)
    }
    
    /// #111: Resolve the effective toggle target for V key in spread context.
    /// When a spread (N, N+1) is split, the marker lives on N (leading page).
    /// If the user is now on standalone N+1 and presses V, we need to target N to re-combine.
    /// But if N+1 is the leading page of a NEW spread (N+1, N+2), toggle N+1 to split it.
    func spreadAwareToggleTarget(for sourceURL: URL, at index: Int, isInSpread: Bool) -> Int {
        // Own marker exists → remove it
        if hasSinglePageMarker(for: sourceURL, at: index) { return index }
        // Currently in a spread → toggle self to split it
        if isInSpread { return index }
        // Standalone single page, previous has marker → re-combine
        if index > 0 && hasSinglePageMarker(for: sourceURL, at: index - 1) { return index - 1 }
        return index
    }
    
    // MARK: - Aspect Ratio Cache (#67 Phase 3)

    /// Make cache key for aspect ratio
    private func aspectRatioCacheKey(sourceURL: URL, path: String) -> String {
        return "\(sourceURL.path)/\(path)"
    }

    /// Set aspect ratio for an image
    func setAspectRatio(for sourceURL: URL, path: String, ratio: CGFloat) {
        let key = aspectRatioCacheKey(sourceURL: sourceURL, path: path)
        aspectRatioLock.lock()
        aspectRatioCache[key] = ratio
        aspectRatioLock.unlock()
    }

    /// Get cached aspect ratio (nil if not loaded yet)
    func getAspectRatio(for sourceURL: URL, path: String) -> CGFloat? {
        let key = aspectRatioCacheKey(sourceURL: sourceURL, path: path)
        aspectRatioLock.lock()
        let result = aspectRatioCache[key]
        aspectRatioLock.unlock()
        return result
    }

    /// Check if image is wide (nil if aspect ratio not cached yet)
    /// - Parameters:
    ///   - sourceURL: Source URL
    ///   - path: Entry path
    ///   - threshold: Width/height ratio threshold (default 1.3)
    /// - Returns: true if wide, false if portrait, nil if unknown
    func isWideImage(for sourceURL: URL, path: String, threshold: CGFloat = 1.3) -> Bool? {
        guard let ratio = getAspectRatio(for: sourceURL, path: path) else { return nil }
        return ratio >= threshold
    }

    /// Clear aspect ratio cache (call on source change if needed)
    func clearAspectRatioCache() {
        aspectRatioLock.lock()
        aspectRatioCache.removeAll()
        aspectRatioLock.unlock()
        Logger.cache.debug("Aspect ratio cache cleared")
    }
    
    // MARK: - Bookmarks (#62)
    
    /// Load bookmarks from disk
    private func loadBookmarks() {
        guard FileManager.default.fileExists(atPath: bookmarksFileURL.path) else {
            bookmarksBySource = [:]
            return
        }
        
        do {
            let data = try Data(contentsOf: bookmarksFileURL)
            bookmarksLock.lock()
            bookmarksBySource = try JSONDecoder().decode([String: [Bookmark]].self, from: data)
            bookmarksLock.unlock()
            let total = bookmarksBySource.values.reduce(0) { $0 + $1.count }
            Logger.cache.info("Loaded bookmarks: \(total, privacy: .public) across \(self.bookmarksBySource.count, privacy: .public) sources")
        } catch {
            Logger.cache.error("Failed to load bookmarks: \(error, privacy: .public)")
            bookmarksBySource = [:]
        }
    }
    
    private func saveBookmarks() {
        writeLock.lock()
        bookmarksSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performSaveBookmarks()
        }
        bookmarksSaveWorkItem = item
        writeQueue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        writeLock.unlock()
    }
    
    private func performSaveBookmarks() {
        bookmarksLock.lock()
        let current = bookmarksBySource
        bookmarksLock.unlock()
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(current)
            try data.write(to: bookmarksFileURL, options: .atomic)
        } catch {
            Logger.cache.error("Failed to save bookmarks: \(error, privacy: .public)")
        }
    }
    
    /// Get all bookmarks for a source (sorted by imageIndex)
    func getBookmarks(for sourceURL: URL) -> [Bookmark] {
        let key = hashString(sourceURL.path)
        bookmarksLock.lock()
        let result = bookmarksBySource[key] ?? []
        bookmarksLock.unlock()
        return result
    }
    
    /// Get bookmark at a specific image index (nil if none)
    func getBookmark(for sourceURL: URL, at imageIndex: Int) -> Bookmark? {
        return getBookmarks(for: sourceURL).first { $0.imageIndex == imageIndex }
    }
    
    /// Check if a bookmark exists at a specific image index
    func hasBookmark(for sourceURL: URL, at imageIndex: Int) -> Bool {
        return getBookmark(for: sourceURL, at: imageIndex) != nil
    }
    
    /// Add a bookmark at the given image index
    /// - Returns: The created Bookmark, or nil if duplicate imageIndex
    @discardableResult
    func addBookmark(for sourceURL: URL, at imageIndex: Int, name: String) -> Bookmark? {
        let key = hashString(sourceURL.path)
        
        bookmarksLock.lock()
        var bookmarks = bookmarksBySource[key] ?? []
        
        // Duplicate check
        if bookmarks.contains(where: { $0.imageIndex == imageIndex }) {
            bookmarksLock.unlock()
            Logger.cache.debug("Bookmark already exists at index \(imageIndex, privacy: .public)")
            return nil
        }
        
        let bookmark = Bookmark(
            id: UUID(),
            imageIndex: imageIndex,
            name: name,
            createdAt: Date()
        )
        bookmarks.append(bookmark)
        bookmarks.sort { $0.imageIndex < $1.imageIndex }
        bookmarksBySource[key] = bookmarks
        bookmarksLock.unlock()
        
        saveBookmarks()
        Logger.cache.debug("Added bookmark '\(name)' at index \(imageIndex, privacy: .public)")
        return bookmark
    }
    
    /// Remove a bookmark by ID
    /// - Returns: true if removed
    @discardableResult
    func removeBookmark(for sourceURL: URL, id: UUID) -> Bool {
        let key = hashString(sourceURL.path)
        
        bookmarksLock.lock()
        guard var bookmarks = bookmarksBySource[key] else {
            bookmarksLock.unlock()
            return false
        }
        
        let beforeCount = bookmarks.count
        bookmarks.removeAll { $0.id == id }
        
        if bookmarks.isEmpty {
            bookmarksBySource.removeValue(forKey: key)
        } else {
            bookmarksBySource[key] = bookmarks
        }
        bookmarksLock.unlock()
        
        let removed = bookmarks.count < beforeCount
        if removed {
            saveBookmarks()
            Logger.cache.debug("Removed bookmark id=\(id, privacy: .public)")
        }
        return removed
    }
    
    /// Update bookmark name
    func updateBookmarkName(for sourceURL: URL, id: UUID, name: String) {
        let key = hashString(sourceURL.path)
        
        bookmarksLock.lock()
        guard var bookmarks = bookmarksBySource[key],
              let idx = bookmarks.firstIndex(where: { $0.id == id }) else {
            bookmarksLock.unlock()
            return
        }
        
        bookmarks[idx].name = name
        bookmarksBySource[key] = bookmarks
        bookmarksLock.unlock()
        
        saveBookmarks()
        Logger.cache.debug("Updated bookmark name to '\(name)'")
    }
    
    /// Get sorted bookmark indices for a source (for navigation)
    func getBookmarkIndices(for sourceURL: URL) -> [Int] {
        return getBookmarks(for: sourceURL).map { $0.imageIndex }
    }
    
    /// Navigate to next bookmark from current index
    func nextBookmarkIndex(for sourceURL: URL, from currentIndex: Int, wrap: Bool = true) -> Int? {
        let indices = getBookmarkIndices(for: sourceURL)
        guard !indices.isEmpty else { return nil }
        
        if let next = indices.first(where: { $0 > currentIndex }) {
            return next
        } else if wrap, let first = indices.first, first != currentIndex {
            return first
        }
        return nil
    }
    
    /// Navigate to previous bookmark from current index
    func previousBookmarkIndex(for sourceURL: URL, from currentIndex: Int, wrap: Bool = true) -> Int? {
        let indices = getBookmarkIndices(for: sourceURL)
        guard !indices.isEmpty else { return nil }
        
        if let prev = indices.last(where: { $0 < currentIndex }) {
            return prev
        } else if wrap, let last = indices.last, last != currentIndex {
            return last
        }
        return nil
    }
    
    // MARK: - Deskew Angles (#101)
    
    /// Load deskew angles from disk
    private func loadDeskewAngles() {
        guard FileManager.default.fileExists(atPath: deskewAnglesFileURL.path) else {
            deskewAnglesBySource = [:]
            return
        }
        
        do {
            let data = try Data(contentsOf: deskewAnglesFileURL)
            deskewLock.lock()
            deskewAnglesBySource = try JSONDecoder().decode([String: [String: CGFloat]].self, from: data)
            deskewLock.unlock()
            let total = deskewAnglesBySource.values.reduce(0) { $0 + $1.count }
            Logger.cache.info("Loaded deskew angles: \(total, privacy: .public) pages across \(self.deskewAnglesBySource.count, privacy: .public) sources")
        } catch {
            Logger.cache.error("Failed to load deskew angles: \(error, privacy: .public)")
            deskewAnglesBySource = [:]
        }
    }
    
    private func saveDeskewAngles() {
        writeLock.lock()
        deskewSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performSaveDeskewAngles()
        }
        deskewSaveWorkItem = item
        writeQueue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        writeLock.unlock()
    }
    
    private func performSaveDeskewAngles() {
        deskewLock.lock()
        let current = deskewAnglesBySource
        deskewLock.unlock()
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(current)
            try data.write(to: deskewAnglesFileURL, options: .atomic)
        } catch {
            Logger.cache.error("Failed to save deskew angles: \(error, privacy: .public)")
        }
    }
    
    /// Get cached deskew angle for a specific page
    /// - Returns: Angle in radians, or nil if not detected yet
    func getDeskewAngle(for sourceURL: URL, entryPath: String) -> CGFloat? {
        let key = hashString(sourceURL.path)
        deskewLock.lock()
        let result = deskewAnglesBySource[key]?[entryPath]
        deskewLock.unlock()
        return result
    }
    
    /// Check if deskew angle has been detected (even if result was "no correction needed")
    /// We store 0.0 to indicate "detected but no tilt" to avoid re-detection
    func hasDeskewAngle(for sourceURL: URL, entryPath: String) -> Bool {
        let key = hashString(sourceURL.path)
        deskewLock.lock()
        let result = deskewAnglesBySource[key]?[entryPath] != nil
        deskewLock.unlock()
        return result
    }
    
    /// Store detected deskew angle for a page
    /// Store 0.0 for "no correction needed" to prevent re-detection
    func setDeskewAngle(for sourceURL: URL, entryPath: String, angle: CGFloat) {
        let key = hashString(sourceURL.path)
        deskewLock.lock()
        if deskewAnglesBySource[key] == nil {
            deskewAnglesBySource[key] = [:]
        }
        deskewAnglesBySource[key]![entryPath] = angle
        deskewLock.unlock()
        saveDeskewAngles()
        Logger.cache.debug("Stored deskew angle \(angle * 180 / CGFloat.pi, privacy: .public)° for \(entryPath)")
    }
    
    /// Get all cached deskew angles for a source
    func getDeskewAngles(for sourceURL: URL) -> [String: CGFloat] {
        let key = hashString(sourceURL.path)
        deskewLock.lock()
        let result = deskewAnglesBySource[key] ?? [:]
        deskewLock.unlock()
        return result
    }
    
    /// Clear all deskew angles for a source (e.g., user wants fresh re-detection)
    func clearDeskewAngles(for sourceURL: URL) {
        let key = hashString(sourceURL.path)
        deskewLock.lock()
        deskewAnglesBySource.removeValue(forKey: key)
        deskewLock.unlock()
        saveDeskewAngles()
        Logger.cache.debug("Cleared deskew angles for \(sourceURL.lastPathComponent)")
    }
    
    // MARK: - Deskew Toggle (convenience, via SourceSettings) (#101)
    
    /// Check if deskew is enabled for a source (default: false)
    func isDeskewEnabled(for sourceURL: URL) -> Bool {
        return getSourceSettings(for: sourceURL)?.deskewEnabled ?? false
    }
    
    /// Toggle deskew on/off for a source
    /// Returns new state
    @discardableResult
    func toggleDeskew(for sourceURL: URL) -> Bool {
        let current = isDeskewEnabled(for: sourceURL)
        let new = !current
        updateSourceSettings(for: sourceURL) { settings in
            settings.deskewEnabled = new ? true : nil  // nil when off (saves space)
        }
        Logger.cache.debug("Deskew \(new ? "enabled" : "disabled") for \(sourceURL.lastPathComponent)")
        return new
    }
}
