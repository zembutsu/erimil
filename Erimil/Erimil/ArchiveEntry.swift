//
//  ArchiveEntry.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import Foundation
import ZIPFoundation

struct ArchiveEntry: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let name: String
    let size: UInt64
    let isImage: Bool
    let index: Int  // エントリのインデックス
    
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"
    ]
    
    init(entry: Entry, index: Int) {
        self.path = entry.path
        self.name = (entry.path as NSString).lastPathComponent
        self.size = entry.uncompressedSize
        self.index = index
        
        let ext = (entry.path as NSString).pathExtension.lowercased()
        
        // メタデータファイルを除外
        let isMetadata = entry.path.contains("__MACOSX/") || self.name.hasPrefix("._")
        
        self.isImage = Self.imageExtensions.contains(ext) && !isMetadata
    }
    
    static func == (lhs: ArchiveEntry, rhs: ArchiveEntry) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
