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
    }
}
