//
//  ArchiveManager.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import Foundation
import ZIPFoundation
import AppKit

class ArchiveManager {
    let zipURL: URL
    private var archive: Archive?
    
    init(zipURL: URL) {
        self.zipURL = zipURL
        // Note: Using deprecated initializer until ZIPFoundation stabilizes new API
        self.archive = Archive(url: zipURL, accessMode: .read)
    }
    
    /// ZIPに含まれる画像エントリ一覧を取得
    func listImageEntries() -> [ArchiveEntry] {
        guard let archive = archive else { return [] }
        
        return archive.compactMap { entry -> ArchiveEntry? in
            // ディレクトリはスキップ
            guard entry.type == .file else { return nil }
            
            let archiveEntry = ArchiveEntry(
                path: entry.path,
                size: entry.uncompressedSize
            )
            
            // 画像のみ返す
            return archiveEntry.isImage ? archiveEntry : nil
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    
    /// 指定エントリのサムネイルを生成
    func thumbnail(for entry: ArchiveEntry, maxSize: CGFloat = 120) -> NSImage? {
        guard let archive = archive,
              let archiveEntry = archive[entry.path] else {
            return nil
        }
        
        var imageData = Data()
        do {
            _ = try archive.extract(archiveEntry) { data in
                imageData.append(data)
            }
        } catch {
            print("Failed to extract \(entry.path): \(error)")
            return nil
        }
        
        guard let image = NSImage(data: imageData) else {
            return nil
        }
        
        // サムネイルサイズにリサイズ
        return resizedImage(image, maxSize: maxSize)
    }
    
    /// フルサイズ画像を取得
    func fullImage(for entry: ArchiveEntry) -> NSImage? {
        guard let archive = archive,
              let archiveEntry = archive[entry.path] else {
            return nil
        }
        
        var imageData = Data()
        do {
            _ = try archive.extract(archiveEntry) { data in
                imageData.append(data)
            }
        } catch {
            return nil
        }
        
        return NSImage(data: imageData)
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
}
