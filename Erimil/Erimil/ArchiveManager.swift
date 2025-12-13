//
//  ArchiveManager.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//
// Reference: https://github.com/weichsel/ZIPFoundation#closure-based-reading-and-writing

import Foundation
import ZIPFoundation
import AppKit

class ArchiveManager {
    let zipURL: URL
    
    init(zipURL: URL) {
        self.zipURL = zipURL
    }
    
    /// ZIPに含まれる画像エントリ一覧を取得
    func listImageEntries() -> [ArchiveEntry] {
        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            print("Failed to open archive: \(zipURL)")
            return []
        }
        
        var results: [ArchiveEntry] = []
        var index = 0
        
        for entry in archive {
            if entry.type == .file {
                let archiveEntry = ArchiveEntry(entry: entry, index: index)
                if archiveEntry.isImage {
                    results.append(archiveEntry)
                }
            }
            index += 1
        }
        
        return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    
    /// 指定エントリのサムネイルを生成
    func thumbnail(for entry: ArchiveEntry, maxSize: CGFloat = 120) -> NSImage? {
        guard let image = extractImage(for: entry) else { return nil }
        return resizedImage(image, maxSize: maxSize)
    }
    
    /// フルサイズ画像を取得
    func fullImage(for entry: ArchiveEntry) -> NSImage? {
        return extractImage(for: entry)
    }
    
    /// 画像を抽出 - 公式ドキュメントの方法に従う
    private func extractImage(for archiveEntry: ArchiveEntry) -> NSImage? {
        // 毎回新しくArchiveを開く（公式の例に近い形）
        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            print("Failed to open archive")
            return nil
        }
        
        // パスで直接アクセス（公式の例: archive["file.txt"]）
        guard let entry = archive[archiveEntry.path] else {
            print("Entry not found: \(archiveEntry.path)")
            return nil
        }
        
        // Consumer closureで抽出（公式の例）
        var imageData = Data()
        do {
            _ = try archive.extract(entry) { data in
                imageData.append(data)
            }
        } catch {
            print("Extract failed for \(archiveEntry.name): \(error)")
            return nil
        }
        
        guard let image = NSImage(data: imageData) else {
            print("Invalid image data for: \(archiveEntry.name), size: \(imageData.count) bytes")
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
}
