//
//  SourceNavigator.swift
//  Erimil
//
//  Created by Bebop Session S005 on 2025/12/27.
//

import Foundation

/// Handles navigation between sibling sources (ZIP files and image folders)
/// within the same parent directory.
struct SourceNavigator {
    
    /// Returns the next source URL in the same parent folder (loops to first after last)
    /// - Parameter currentURL: The currently selected source URL
    /// - Returns: Next source URL, or nil if no siblings exist
    static func nextSource(from currentURL: URL) -> URL? {
        let siblings = siblingSourcesOf(currentURL)
        guard siblings.count > 1 else { return nil }
        
        guard let currentIndex = siblings.firstIndex(of: currentURL) else {
            return siblings.first
        }
        
        let nextIndex = (currentIndex + 1) % siblings.count
        return siblings[nextIndex]
    }
    
    /// Returns the previous source URL in the same parent folder (loops to last after first)
    /// - Parameter currentURL: The currently selected source URL
    /// - Returns: Previous source URL, or nil if no siblings exist
    static func previousSource(from currentURL: URL) -> URL? {
        let siblings = siblingSourcesOf(currentURL)
        guard siblings.count > 1 else { return nil }
        
        guard let currentIndex = siblings.firstIndex(of: currentURL) else {
            return siblings.last
        }
        
        let prevIndex = (currentIndex - 1 + siblings.count) % siblings.count
        return siblings[prevIndex]
    }
    
    /// Returns the current position and total count for display (e.g., "3/10")
    /// - Parameter currentURL: The currently selected source URL
    /// - Returns: Tuple of (1-based position, total count), or nil if not found
    static func positionInfo(for currentURL: URL) -> (position: Int, total: Int)? {
        let siblings = siblingSourcesOf(currentURL)
        guard !siblings.isEmpty else { return nil }
        
        guard let currentIndex = siblings.firstIndex(of: currentURL) else {
            return nil
        }
        
        return (currentIndex + 1, siblings.count)
    }
    
    // MARK: - Private
    
    /// Lists all sibling sources (ZIPs and directories) in the same parent folder
    /// Uses the same filtering logic as FolderNode.loadChildren for consistency
    private static func siblingSourcesOf(_ url: URL) -> [URL] {
        let parentURL = url.deletingLastPathComponent()
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[SourceNavigator] Failed to list contents of \(parentURL.path)")
            return []
        }
        
        // Filter: directories or ZIP files only (same as FolderNode.loadChildren)
        let sources = contents.filter { item in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            return isDir.boolValue || item.pathExtension.lowercased() == "zip"
        }
        
        // Sort: localized standard compare (same as FolderNode.loadChildren)
        let sorted = sources.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        
        print("[SourceNavigator] Found \(sorted.count) siblings in \(parentURL.lastPathComponent)")
        return sorted
    }
}
