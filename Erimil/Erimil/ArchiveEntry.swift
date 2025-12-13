//
//  ArchiveEntry.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import Foundation
import AppKit

struct ArchiveEntry: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let name: String
    let size: UInt64
    let isImage: Bool
    
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"
    ]
    
    init(path: String, size: UInt64) {
        self.path = path
        self.name = (path as NSString).lastPathComponent
        self.size = size
        
        let ext = (path as NSString).pathExtension.lowercased()
        self.isImage = Self.imageExtensions.contains(ext)
    }
}
