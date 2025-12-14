//
//  ArchiveManager.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//  ImageSource implementation for ZIP archives
//  Reference: https://github.com/weichsel/ZIPFoundation#closure-based-reading-and-writing
//

import Foundation
import ZIPFoundation
import AppKit

class ArchiveManager: ImageSource {
    let url: URL
    let sourceType: ImageSourceType = .archive
    
    // Convenience alias
    var zipURL: URL { url }
    
    init(zipURL: URL) {
        self.url = zipURL
    }
    
    /// List all image entries in the ZIP
    func listImageEntries() -> [ImageEntry] {
        guard let archive = Archive(url: url, accessMode: .read) else {
            print("Failed to open archive: \(url)")
            return []
        }
        
        var results: [ImageEntry] = []
        
        for entry in archive {
            if entry.type == .file {
                let imageEntry = ImageEntry(
                    path: entry.path,
                    size: entry.uncompressedSize
                )
                
                // Filter: images only, exclude __MACOSX metadata
                if imageEntry.isImage && !entry.path.contains("__MACOSX/") && !imageEntry.name.hasPrefix("._") {
                    results.append(imageEntry)
                }
            }
        }
        
        return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    
    /// Generate thumbnail for entry
    func thumbnail(for entry: ImageEntry, maxSize: CGFloat = 120) -> NSImage? {
        guard let image = extractImage(for: entry) else { return nil }
        return resizedImage(image, maxSize: maxSize)
    }
    
    /// Get full-size image
    func fullImage(for entry: ImageEntry) -> NSImage? {
        return extractImage(for: entry)
    }
    
    /// Extract image from ZIP - opens archive fresh each time per official docs
    private func extractImage(for imageEntry: ImageEntry) -> NSImage? {
        guard let archive = Archive(url: url, accessMode: .read) else {
            print("Failed to open archive")
            return nil
        }
        
        guard let entry = archive[imageEntry.path] else {
            print("Entry not found: \(imageEntry.path)")
            return nil
        }
        
        var imageData = Data()
        do {
            _ = try archive.extract(entry) { data in
                imageData.append(data)
            }
        } catch {
            print("Extract failed for \(imageEntry.name): \(error)")
            return nil
        }
        
        guard let image = NSImage(data: imageData) else {
            print("Invalid image data for: \(imageEntry.name), size: \(imageData.count) bytes")
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
    
    // MARK: - Export functionality
    
    /// Export excluding specified paths
    /// Reference: https://github.com/weichsel/ZIPFoundation#adding-and-removing-entries
    func exportOptimized(excluding excludedPaths: Set<String>, to destinationURL: URL) throws {
        print("exportOptimized called")
        print("Excluded paths: \(excludedPaths)")
        
        guard let sourceArchive = Archive(url: url, accessMode: .read) else {
            print("Failed to open source archive")
            throw ArchiveError.cannotOpenSource
        }
        print("Source archive opened")
        
        guard let destinationArchive = Archive(url: destinationURL, accessMode: .create) else {
            print("Failed to create destination archive at: \(destinationURL.path)")
            throw ArchiveError.cannotCreateDestination
        }
        print("Destination archive created")
        
        for entry in sourceArchive {
            if excludedPaths.contains(entry.path) {
                print("Excluding: \(entry.path)")
                continue
            }
            
            if entry.path.contains("__MACOSX/") {
                print("Skipping __MACOSX: \(entry.path)")
                continue
            }
            
            if entry.type == .directory {
                print("Skipping directory: \(entry.path)")
                continue
            }
            
            print("Copying: \(entry.path)")
            
            var entryData = Data()
            do {
                _ = try sourceArchive.extract(entry) { data in
                    entryData.append(data)
                }
                print("  Extracted: \(entryData.count) bytes")
            } catch {
                print("  Extract failed: \(error)")
                continue
            }
            
            do {
                try destinationArchive.addEntry(
                    with: entry.path,
                    type: entry.type,
                    uncompressedSize: Int64(entryData.count),
                    provider: { position, size in
                        let start = Int(position)
                        let end = min(start + size, entryData.count)
                        return entryData.subdata(in: start..<end)
                    }
                )
                print("  Added to destination")
            } catch {
                print("  Add failed: \(error)")
                continue
            }
        }
        
        print("Export completed successfully")
    }
}

enum ArchiveError: Error, LocalizedError {
    case cannotOpenSource
    case cannotCreateDestination
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenSource:
            return "元のZIPファイルを開けません"
        case .cannotCreateDestination:
            return "新しいZIPファイルを作成できません"
        }
    }
}
