//
//  ImageSource.swift
//  Erimil
//
//  Common protocol for image sources (ZIP archives, folders, etc.)
//  Reference: DESIGN.md Decision 8
//

import Foundation
import AppKit

/// Represents an image entry from any source
struct ImageEntry: Identifiable, Hashable {
    let id = UUID()
    let path: String           // Full path within source
    let name: String           // Display name (filename)
    let size: UInt64           // File size in bytes
    
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"
    ]
    
    var isImage: Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
    }
    
    init(path: String, name: String? = nil, size: UInt64 = 0) {
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.size = size
    }
    
    static func == (lhs: ImageEntry, rhs: ImageEntry) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Protocol for browsing images from various sources
protocol ImageSource {
    /// Source URL (ZIP file or folder)
    var url: URL { get }
    
    /// Display name for the source
    var displayName: String { get }
    
    /// Source type for UI customization
    var sourceType: ImageSourceType { get }
    
    /// List all image entries
    func listImageEntries() -> [ImageEntry]
    
    /// Get raw image data for entry (used for hashing and caching)
    func rawImageData(for entry: ImageEntry) -> Data?
    
    /// Generate thumbnail for entry
    func thumbnail(for entry: ImageEntry, maxSize: CGFloat) -> NSImage?
    
    /// Get full-size image for entry
    func fullImage(for entry: ImageEntry) -> NSImage?
    
    /// Unique identifier for the entry (used for cache key)
    func uniquePath(for entry: ImageEntry) -> String
}

/// Source type for determining available actions
enum ImageSourceType {
    case archive    // ZIP, tar.gz, etc.
    case folder     // Directory
}

// Default implementations
extension ImageSource {
    var displayName: String {
        url.lastPathComponent
    }
    
    func thumbnail(for entry: ImageEntry) -> NSImage? {
        thumbnail(for: entry, maxSize: 120)
    }
}
