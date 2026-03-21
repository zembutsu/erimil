//
//  AppSettings.swift
//  Erimil
//
//  Application settings with UserDefaults persistence
//  Updated: S018 (2026-01-24) - Added ReadingDirection (#54)
//

import Foundation
import Combine
import SwiftUI  // For LayoutDirection
import os

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
    case extraLarge = "extraLarge"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        case .extraLarge: return "特大"
        case .custom: return "カスタム"
        }
    }
    
    var size: CGFloat {
        switch self {
        case .small: return 80
        case .medium: return 120
        case .large: return 180
        case .extraLarge: return 250
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
    
    /// Cycle to next position (for Ctrl+T key toggle)
    var next: ViewerThumbnailPosition {
        switch self {
        case .left: return .bottom
        case .bottom: return .hidden
        case .hidden: return .left
        }
    }
}

/// Reading direction for manga/book viewing (#54)
enum ReadingDirection: String, CaseIterable, Codable {
    case ltr = "ltr"  // Left-to-Right (Western books, default)
    case rtl = "rtl"  // Right-to-Left (Japanese manga, vertical text books)
    
    var displayName: String {
        switch self {
        case .ltr: return "左→右 (LTR)"
        case .rtl: return "右→左 (RTL)"
        }
    }
    
    var shortName: String {
        switch self {
        case .ltr: return "LTR"
        case .rtl: return "RTL"
        }
    }
    
    /// SwiftUI LayoutDirection for environment
    var layoutDirection: LayoutDirection {
        switch self {
        case .ltr: return .leftToRight
        case .rtl: return .rightToLeft
        }
    }
    
    /// Toggle to opposite direction
    var toggled: ReadingDirection {
        switch self {
        case .ltr: return .rtl
        case .rtl: return .ltr
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
        static let loopWithinSource = "loopWithinSource"
        static let defaultReadingDirection = "defaultReadingDirection"  // #54
        static let isSpreadModeEnabled = "isSpreadModeEnabled"      // #55
        static let spreadThreshold = "spreadThreshold"              // #55
        static let metadataFavorites = "metadataCarryOverFavorites"          // #105
        static let metadataBookmarks = "metadataCarryOverBookmarks"          // #105
        static let metadataReadingDirection = "metadataCarryOverDirection"   // #105
        static let metadataSinglePageMarkers = "metadataCarryOverMarkers"   // #105
        static let navigationStepCount = "navigationStepCount"             // #143
        static let autoSlideIntervalNormal = "autoSlideIntervalNormal"     // #172
        static let autoSlideIntervalFast   = "autoSlideIntervalFast"       // #172
        static let autoSlideIntervalTurbo  = "autoSlideIntervalTurbo"      // #172
        static let autoSlideLoops          = "autoSlideLoops"              // #172
        static let gridSpacing             = "gridSpacing"                 // #212
        static let lastSelectedSourcePath  = "lastSelectedSourcePath"      // S091
        static let lastSelectedSourceType  = "lastSelectedSourceType"      // S091
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
    
    /// Loop navigation within source (last→first, first→last)
    @Published var loopWithinSource: Bool {
        didSet {
            defaults.set(loopWithinSource, forKey: Keys.loopWithinSource)
        }
    }
    
    /// Default reading direction for new sources (#54)
    @Published var defaultReadingDirection: ReadingDirection {
        didSet {
            defaults.set(defaultReadingDirection.rawValue, forKey: Keys.defaultReadingDirection)
            Logger.appSettings.debug("Default reading direction changed to: \(self.defaultReadingDirection.displayName, privacy: .public)")
        }
    }
    
    /// Spread (two-page) mode enabled (#55)
    @Published var isSpreadModeEnabled: Bool {
        didSet {
            defaults.set(isSpreadModeEnabled, forKey: Keys.isSpreadModeEnabled)
            Logger.appSettings.debug("Spread mode: \(self.isSpreadModeEnabled ? "ON" : "OFF")")
        }
    }
    
    /// Threshold for auto-detecting spread scans (#55)
    /// Images with aspect ratio (width/height) > this value are shown as single page
    @Published var spreadThreshold: Double {
        didSet {
            defaults.set(spreadThreshold, forKey: Keys.spreadThreshold)
            Logger.appSettings.debug("Spread threshold: \(self.spreadThreshold, privacy: .public)")
        }
    }
    
    // MARK: - Metadata Carry-Over Defaults (#105)
    
    /// Copy ★ favorites on export
    @Published var metadataCarryOverFavorites: Bool {
        didSet { defaults.set(metadataCarryOverFavorites, forKey: Keys.metadataFavorites) }
    }
    
    /// Copy 栞 bookmarks on export
    @Published var metadataCarryOverBookmarks: Bool {
        didSet { defaults.set(metadataCarryOverBookmarks, forKey: Keys.metadataBookmarks) }
    }
    
    /// Copy reading direction on export
    @Published var metadataCarryOverDirection: Bool {
        didSet { defaults.set(metadataCarryOverDirection, forKey: Keys.metadataReadingDirection) }
    }
    
    /// Copy single page markers on export
    @Published var metadataCarryOverMarkers: Bool {
        didSet { defaults.set(metadataCarryOverMarkers, forKey: Keys.metadataSinglePageMarkers) }
    }
    
    /// Navigation step count for Ctrl+Option+key N-step navigation (#143)
    /// Default: 10, range: 2-50
    @Published var navigationStepCount: Int {
        didSet {
            defaults.set(navigationStepCount, forKey: Keys.navigationStepCount)
        }
    }
    
    /// Auto-Slide interval for Normal mode in seconds (#172)
    @Published var autoSlideIntervalNormal: Double {
        didSet { defaults.set(autoSlideIntervalNormal, forKey: Keys.autoSlideIntervalNormal) }
    }
    
    /// Auto-Slide interval for Fast mode in seconds (#172)
    @Published var autoSlideIntervalFast: Double {
        didSet { defaults.set(autoSlideIntervalFast, forKey: Keys.autoSlideIntervalFast) }
    }
    
    /// Auto-Slide interval for Turbo mode in seconds (#172)
    @Published var autoSlideIntervalTurbo: Double {
        didSet { defaults.set(autoSlideIntervalTurbo, forKey: Keys.autoSlideIntervalTurbo) }
    }

    /// Auto-Slide loops at end of source (#172, default: true = display/kiosk use)
    @Published var autoSlideLoops: Bool {
        didSet { defaults.set(autoSlideLoops, forKey: Keys.autoSlideLoops) }
    }
    
    /// Grid spacing between thumbnails in pixels (#212)
    /// Default: 8, range: 0-24
    @Published var gridSpacing: CGFloat {
        didSet { defaults.set(Double(gridSpacing), forKey: Keys.gridSpacing) }
    }
    
    /// Build MetadataCarryOverOptions from current settings
    var defaultMetadataOptions: MetadataCarryOverOptions {
        MetadataCarryOverOptions(
            favorites: metadataCarryOverFavorites,
            bookmarks: metadataCarryOverBookmarks,
            readingDirection: metadataCarryOverDirection,
            singlePageMarkers: metadataCarryOverMarkers
        )
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

    // MARK: - S091: Last Selected Source (not @Published — save-only, no UI binding)
    
    /// Last selected source path (absolute path string)
    var lastSelectedSourcePath: String? {
        get { defaults.string(forKey: Keys.lastSelectedSourcePath) }
        set {
            if let path = newValue {
                defaults.set(path, forKey: Keys.lastSelectedSourcePath)
            } else {
                defaults.removeObject(forKey: Keys.lastSelectedSourcePath)
            }
        }
    }
    
    /// Last selected source type (ImageSourceType raw value)
    var lastSelectedSourceType: String? {
        get { defaults.string(forKey: Keys.lastSelectedSourceType) }
        set {
            if let type = newValue {
                defaults.set(type, forKey: Keys.lastSelectedSourceType)
            } else {
                defaults.removeObject(forKey: Keys.lastSelectedSourceType)
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
        Logger.appSettings.debug("saveSecurityScopedBookmark called for: \(url.path)")
        Logger.appSettings.debug("Saving to file: \(self.bookmarkFileURL.path)")
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            Logger.appSettings.info("Created bookmark data, size: \(bookmarkData.count, privacy: .public) bytes")
            
            // Save to file instead of UserDefaults
            try bookmarkData.write(to: bookmarkFileURL)
            
            // Verify save
            let verifyExists = FileManager.default.fileExists(atPath: bookmarkFileURL.path)
            Logger.appSettings.debug("Verify after save - file exists: \(verifyExists, privacy: .public)")
            
            Logger.appSettings.info("Saved security-scoped bookmark for: \(url.path)")
        } catch {
            Logger.appSettings.error("Failed to save bookmark: \(error, privacy: .public)")
        }
    }
    
    /// Restore URL from security-scoped bookmark file and start accessing
    func restoreAndAccessLastOpenedFolder() -> URL? {
        Logger.appSettings.info("Attempting to restore last opened folder...")
        Logger.appSettings.debug("Looking for file: \(self.bookmarkFileURL.path)")
        
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: bookmarkFileURL.path)
        Logger.appSettings.debug("Bookmark file exists: \(fileExists, privacy: .public)")
        
        guard fileExists else {
            Logger.appSettings.debug("No bookmark file found")
            return nil
        }
        
        do {
            let bookmarkData = try Data(contentsOf: bookmarkFileURL)
            Logger.appSettings.info("Loaded bookmark data, size: \(bookmarkData.count, privacy: .public) bytes")
            
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            Logger.appSettings.info("Resolved bookmark to: \(url.path), isStale: \(isStale, privacy: .public)")
            
            if isStale {
                Logger.appSettings.debug("Bookmark is stale, will re-save")
                saveSecurityScopedBookmark(for: url)
            }
            
            // Start accessing the security-scoped resource
            if url.startAccessingSecurityScopedResource() {
                Logger.appSettings.info("Started accessing security-scoped resource: \(url.path)")
                securityScopedURL = url
                isAccessingSecurityScopedResource = true
                return url
            } else {
                Logger.appSettings.error("Failed to start accessing security-scoped resource")
            }
        } catch {
            Logger.appSettings.error("Failed to restore bookmark: \(error, privacy: .public)")
        }
        
        return nil
    }
    
    /// Stop accessing the security-scoped resource (call when done or switching folders)
    func stopAccessingLastOpenedFolder() {
        if isAccessingSecurityScopedResource, let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
            Logger.appSettings.info("Stopped accessing security-scoped resource")
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
    
    /// #207: Effective thumbnail size accounting for Retina display scale.
    /// Cached at launch on main thread — safe to read from any thread
    private(set) lazy var displayScaleFactor: CGFloat = {
        NSScreen.main?.backingScaleFactor ?? 2.0
    }()

    var effectiveRetinaThumbnailSize: CGFloat {
        return effectiveThumbnailSize * displayScaleFactor
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
        
        // #54: Reading direction
        if let dirString = defaults.string(forKey: Keys.defaultReadingDirection),
           let dir = ReadingDirection(rawValue: dirString) {
            self.defaultReadingDirection = dir
        } else {
            self.defaultReadingDirection = .ltr  // Default: Left-to-Right
        }
        
        // #55: Spread mode (default ON)
        self.isSpreadModeEnabled = defaults.object(forKey: Keys.isSpreadModeEnabled) == nil ? true : defaults.bool(forKey: Keys.isSpreadModeEnabled)
        
        // #55: Spread threshold (default 1.2)
        let savedThreshold = defaults.double(forKey: Keys.spreadThreshold)
        self.spreadThreshold = savedThreshold > 0 ? savedThreshold : 1.2
        
        // lastOpenedFolderURL is restored via restoreAndAccessLastOpenedFolder()
        // to properly handle security-scoped bookmarks
        self.lastOpenedFolderURL = nil
        
        // loopWithinSource: default is ON
        self.loopWithinSource = defaults.object(forKey: Keys.loopWithinSource) == nil ? true : defaults.bool(forKey: Keys.loopWithinSource)
        
        // #105: Metadata carry-over defaults (all ON by default)
        self.metadataCarryOverFavorites = defaults.object(forKey: Keys.metadataFavorites) == nil ? true : defaults.bool(forKey: Keys.metadataFavorites)
        self.metadataCarryOverBookmarks = defaults.object(forKey: Keys.metadataBookmarks) == nil ? true : defaults.bool(forKey: Keys.metadataBookmarks)
        self.metadataCarryOverDirection = defaults.object(forKey: Keys.metadataReadingDirection) == nil ? true : defaults.bool(forKey: Keys.metadataReadingDirection)
        self.metadataCarryOverMarkers = defaults.object(forKey: Keys.metadataSinglePageMarkers) == nil ? true : defaults.bool(forKey: Keys.metadataSinglePageMarkers)
        
        // #143: Navigation step count (default 10)
        let savedStepCount = defaults.integer(forKey: Keys.navigationStepCount)
        self.navigationStepCount = savedStepCount > 0 ? min(max(savedStepCount, 2), 50) : 10
        
        // #172: Auto-Slide intervals
        let savedNormal = defaults.double(forKey: Keys.autoSlideIntervalNormal)
        self.autoSlideIntervalNormal = savedNormal > 0 ? savedNormal : 5.0
        let savedFast = defaults.double(forKey: Keys.autoSlideIntervalFast)
        self.autoSlideIntervalFast = savedFast > 0 ? savedFast : 0.5
        let savedTurbo = defaults.double(forKey: Keys.autoSlideIntervalTurbo)
        self.autoSlideIntervalTurbo = savedTurbo > 0 ? savedTurbo : 1.5
        self.autoSlideLoops = defaults.object(forKey: Keys.autoSlideLoops) == nil ? true : defaults.bool(forKey: Keys.autoSlideLoops)
        
        // #212: Grid spacing (default 8)
        self.gridSpacing = defaults.object(forKey: Keys.gridSpacing) != nil ? CGFloat(defaults.double(forKey: Keys.gridSpacing)) : 8
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
        loopWithinSource = true
        defaultReadingDirection = .ltr  // #54
        isSpreadModeEnabled = true      // #55
        spreadThreshold = 1.2           // #55
        metadataCarryOverFavorites = true    // #105
        metadataCarryOverBookmarks = true    // #105
        metadataCarryOverDirection = true    // #105
        metadataCarryOverMarkers = true      // #105
        navigationStepCount = 10                 // #143
        autoSlideIntervalNormal = 5.0            // #172
        autoSlideIntervalFast   = 0.5            // #172
        autoSlideIntervalTurbo  = 1.5            // #172
        autoSlideLoops          = true           // #172
        gridSpacing             = 8              // #212
        lastSelectedSourcePath  = nil            // S091
        lastSelectedSourceType  = nil            // S091
    }
}
