//
//  AppSettings.swift
//  Erimil
//
//  Application settings with UserDefaults persistence
//

import Foundation
import Combine

/// Selection mode for image marking
enum SelectionMode: String, CaseIterable {
    case exclude = "exclude"  // Mark to exclude (default, safer)
    case keep = "keep"        // Mark to keep
    
    var displayName: String {
        switch self {
        case .exclude: return "除外モード"
        case .keep: return "選出モード"
        }
    }
    
    var description: String {
        switch self {
        case .exclude: return "クリックした画像が除外されます（安全）"
        case .keep: return "クリックした画像だけが残ります"
        }
    }
}

/// Thumbnail size presets
enum ThumbnailSizePreset: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        case .custom: return "カスタム"
        }
    }
    
    var size: CGFloat {
        switch self {
        case .small: return 80
        case .medium: return 120
        case .large: return 180
        case .custom: return 120  // Default for custom, actual value from thumbnailSize
        }
    }
}

/// Favorite scope options
enum FavoriteScope: String, CaseIterable {
    case content = "content"  // Same image anywhere gets ⭐
    case source = "source"    // Per ZIP/folder
    
    var displayName: String {
        switch self {
        case .content: return "コンテンツ単位"
        case .source: return "ソース単位"
        }
    }
    
    var description: String {
        switch self {
        case .content: return "同じ画像なら別の場所でも⭐（画像の中身で識別）"
        case .source: return "ZIP/フォルダごとに独立した⭐（場所で識別）"
        }
    }
}

/// Viewer Mode thumbnail sidebar position
enum ViewerThumbnailPosition: String, CaseIterable {
    case left = "left"
    case bottom = "bottom"
    case hidden = "hidden"
    
    var displayName: String {
        switch self {
        case .left: return "左"
        case .bottom: return "下"
        case .hidden: return "非表示"
        }
    }
    
    /// Cycle to next position (for T key toggle)
    var next: ViewerThumbnailPosition {
        switch self {
        case .left: return .bottom
        case .bottom: return .hidden
        case .hidden: return .left
        }
    }
}

/// Centralized app settings with UserDefaults
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Keys
    private enum Keys {
        static let defaultOutputFolder = "defaultOutputFolder"
        static let selectionMode = "selectionMode"
        static let useDefaultOutputFolder = "useDefaultOutputFolder"
        static let thumbnailSizePreset = "thumbnailSizePreset"
        static let thumbnailSize = "thumbnailSize"
        static let favoriteScope = "favoriteScope"
        static let lastOpenedFolder = "lastOpenedFolder"
        static let viewerThumbnailPosition = "viewerThumbnailPosition"
        static let prefetchCount = "prefetchCount"
    }
    
    // MARK: - Published Properties
    
    /// Default output folder URL (nil = same as source)
    @Published var defaultOutputFolder: URL? {
        didSet {
            if let url = defaultOutputFolder {
                defaults.set(url.path, forKey: Keys.defaultOutputFolder)
            } else {
                defaults.removeObject(forKey: Keys.defaultOutputFolder)
            }
        }
    }
    
    /// Whether to use default output folder
    @Published var useDefaultOutputFolder: Bool {
        didSet {
            defaults.set(useDefaultOutputFolder, forKey: Keys.useDefaultOutputFolder)
        }
    }
    
    /// Default selection mode
    @Published var selectionMode: SelectionMode {
        didSet {
            defaults.set(selectionMode.rawValue, forKey: Keys.selectionMode)
        }
    }
    
    /// Thumbnail size preset
    @Published var thumbnailSizePreset: ThumbnailSizePreset {
        didSet {
            defaults.set(thumbnailSizePreset.rawValue, forKey: Keys.thumbnailSizePreset)
            if thumbnailSizePreset != .custom {
                thumbnailSize = thumbnailSizePreset.size
            }
        }
    }
    
    /// Custom thumbnail size (used when preset is .custom)
    @Published var thumbnailSize: CGFloat {
        didSet {
            defaults.set(thumbnailSize, forKey: Keys.thumbnailSize)
        }
    }
    
    /// Favorite scope (content-based or source-based)
    @Published var favoriteScope: FavoriteScope {
        didSet {
            defaults.set(favoriteScope.rawValue, forKey: Keys.favoriteScope)
        }
    }
    
    /// Viewer Mode thumbnail position
    @Published var viewerThumbnailPosition: ViewerThumbnailPosition {
        didSet {
            defaults.set(viewerThumbnailPosition.rawValue, forKey: Keys.viewerThumbnailPosition)
        }
    }
    
    /// Prefetch count: number of images to preload in each direction (0-5)
    @Published var prefetchCount: Int {
        didSet {
            defaults.set(prefetchCount, forKey: Keys.prefetchCount)
        }
    }
    
    /// Last opened folder URL (for restoration on launch)
    /// Uses Security-Scoped Bookmarks to maintain access across app launches
    @Published var lastOpenedFolderURL: URL? {
        didSet {
            if let url = lastOpenedFolderURL {
                saveSecurityScopedBookmark(for: url)
            } else {
                defaults.removeObject(forKey: Keys.lastOpenedFolder)
            }
        }
    }
    
    // Track if we're currently accessing a security-scoped resource
    private var isAccessingSecurityScopedResource = false
    private var securityScopedURL: URL?
    
    // MARK: - File-based Bookmark Storage (more reliable than UserDefaults in sandbox)
    
    private var bookmarkFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let erimil = appSupport.appendingPathComponent("Erimil")
        try? FileManager.default.createDirectory(at: erimil, withIntermediateDirectories: true)
        return erimil.appendingPathComponent("last_folder_bookmark.data")
    }
    
    /// Save URL as security-scoped bookmark to file
    private func saveSecurityScopedBookmark(for url: URL) {
        print("[AppSettings] saveSecurityScopedBookmark called for: \(url.path)")
        print("[AppSettings] Saving to file: \(bookmarkFileURL.path)")
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            print("[AppSettings] Created bookmark data, size: \(bookmarkData.count) bytes")
            
            // Save to file instead of UserDefaults
            try bookmarkData.write(to: bookmarkFileURL)
            
            // Verify save
            let verifyExists = FileManager.default.fileExists(atPath: bookmarkFileURL.path)
            print("[AppSettings] Verify after save - file exists: \(verifyExists)")
            
            print("[AppSettings] Saved security-scoped bookmark for: \(url.path)")
        } catch {
            print("[AppSettings] Failed to save bookmark: \(error)")
        }
    }
    
    /// Restore URL from security-scoped bookmark file and start accessing
    func restoreAndAccessLastOpenedFolder() -> URL? {
        print("[AppSettings] Attempting to restore last opened folder...")
        print("[AppSettings] Looking for file: \(bookmarkFileURL.path)")
        
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: bookmarkFileURL.path)
        print("[AppSettings] Bookmark file exists: \(fileExists)")
        
        guard fileExists else {
            print("[AppSettings] No bookmark file found")
            return nil
        }
        
        do {
            let bookmarkData = try Data(contentsOf: bookmarkFileURL)
            print("[AppSettings] Loaded bookmark data, size: \(bookmarkData.count) bytes")
            
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            print("[AppSettings] Resolved bookmark to: \(url.path), isStale: \(isStale)")
            
            if isStale {
                print("[AppSettings] Bookmark is stale, will re-save")
                saveSecurityScopedBookmark(for: url)
            }
            
            // Start accessing the security-scoped resource
            if url.startAccessingSecurityScopedResource() {
                print("[AppSettings] Started accessing security-scoped resource: \(url.path)")
                securityScopedURL = url
                isAccessingSecurityScopedResource = true
                return url
            } else {
                print("[AppSettings] Failed to start accessing security-scoped resource")
            }
        } catch {
            print("[AppSettings] Failed to restore bookmark: \(error)")
        }
        
        return nil
    }
    
    /// Stop accessing the security-scoped resource (call when done or switching folders)
    func stopAccessingLastOpenedFolder() {
        if isAccessingSecurityScopedResource, let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
            print("[AppSettings] Stopped accessing security-scoped resource")
            isAccessingSecurityScopedResource = false
            securityScopedURL = nil
        }
    }
    
    // MARK: - Computed Properties
    
    /// Effective thumbnail size (preset or custom)
    var effectiveThumbnailSize: CGFloat {
        if thumbnailSizePreset == .custom {
            return thumbnailSize
        }
        return thumbnailSizePreset.size
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved values
        if let path = defaults.string(forKey: Keys.defaultOutputFolder) {
            self.defaultOutputFolder = URL(fileURLWithPath: path)
        } else {
            self.defaultOutputFolder = nil
        }
        
        self.useDefaultOutputFolder = defaults.bool(forKey: Keys.useDefaultOutputFolder)
        
        if let modeString = defaults.string(forKey: Keys.selectionMode),
           let mode = SelectionMode(rawValue: modeString) {
            self.selectionMode = mode
        } else {
            self.selectionMode = .exclude  // Default: safer mode
        }
        
        if let presetString = defaults.string(forKey: Keys.thumbnailSizePreset),
           let preset = ThumbnailSizePreset(rawValue: presetString) {
            self.thumbnailSizePreset = preset
        } else {
            self.thumbnailSizePreset = .medium  // Default: 120px
        }
        
        let savedSize = defaults.double(forKey: Keys.thumbnailSize)
        self.thumbnailSize = savedSize > 0 ? savedSize : 120  // Default: 120px
        
        if let scopeString = defaults.string(forKey: Keys.favoriteScope),
           let scope = FavoriteScope(rawValue: scopeString) {
            self.favoriteScope = scope
        } else {
            self.favoriteScope = .content  // Default: content-based
        }
        
        if let posString = defaults.string(forKey: Keys.viewerThumbnailPosition),
           let pos = ViewerThumbnailPosition(rawValue: posString) {
            self.viewerThumbnailPosition = pos
        } else {
            self.viewerThumbnailPosition = .left  // Default: left sidebar
        }
        
        let savedPrefetchCount = defaults.integer(forKey: Keys.prefetchCount)
        self.prefetchCount = savedPrefetchCount > 0 ? min(savedPrefetchCount, 5) : 2
        
        // lastOpenedFolderURL is restored via restoreAndAccessLastOpenedFolder()
        // to properly handle security-scoped bookmarks
        self.lastOpenedFolderURL = nil
    }
    
    // MARK: - Helper Methods
    
    /// Get output directory for a given source URL
    func outputDirectory(for sourceURL: URL) -> URL {
        if useDefaultOutputFolder, let folder = defaultOutputFolder {
            return folder
        }
        return sourceURL.deletingLastPathComponent()
    }
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        defaultOutputFolder = nil
        useDefaultOutputFolder = false
        selectionMode = .exclude
        thumbnailSizePreset = .medium
        thumbnailSize = 120
        prefetchCount = 2
        favoriteScope = .content
        viewerThumbnailPosition = .left
        lastOpenedFolderURL = nil
    }
}
