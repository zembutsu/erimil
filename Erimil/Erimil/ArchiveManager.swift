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
    
    /// 除外リスト以外のエントリを新しいZIPに書き出す
    /// Reference: https://github.com/weichsel/ZIPFoundation#adding-and-removing-entries
    func exportOptimized(excluding excludedPaths: Set<String>, to destinationURL: URL) throws {
        print("exportOptimized called")
        print("Excluded paths: \(excludedPaths)")
        
        guard let sourceArchive = Archive(url: zipURL, accessMode: .read) else {
            print("Failed to open source archive")
            throw ArchiveError.cannotOpenSource
        }
        print("Source archive opened")
        
        guard let destinationArchive = Archive(url: destinationURL, accessMode: .create) else {
            print("Failed to create destination archive at: \(destinationURL.path)")
            throw ArchiveError.cannotCreateDestination
        }
        print("Destination archive created")
        
        // 除外リストにないエントリをコピー
        for entry in sourceArchive {
            // 除外対象はスキップ
            if excludedPaths.contains(entry.path) {
                print("Excluding: \(entry.path)")
                continue
            }
            
            // __MACOSX もスキップ
            if entry.path.contains("__MACOSX/") {
                print("Skipping __MACOSX: \(entry.path)")
                continue
            }
            
            // ディレクトリエントリはスキップ（必要に応じて）
            if entry.type == .directory {
                print("Skipping directory: \(entry.path)")
                continue
            }
            
            print("Copying: \(entry.path)")
            
            // エントリをコピー
            var entryData = Data()
            do {
                _ = try sourceArchive.extract(entry) { data in
                    entryData.append(data)
                }
                print("  Extracted: \(entryData.count) bytes")
            } catch {
                print("  Extract failed: \(error)")
                continue  // このエントリはスキップして続行
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
                continue  // このエントリはスキップして続行
            }
        }
        
        print("Export completed successfully")
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
}
