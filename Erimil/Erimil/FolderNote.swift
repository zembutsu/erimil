//
//  FolderNote.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import Foundation

struct FolderNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let isZip: Bool
    let isPdf: Bool
    var children: [FolderNode]?
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        self.isZip = url.pathExtension.lowercased() == "zip"
        self.isPdf = url.pathExtension.lowercased() == "pdf"
        
        if isDirectory {
            self.children = FolderNode.loadChildren(of: url)
        } else {
            self.children = nil
        }
    }
    
    static func loadChildren(of url: URL) -> [FolderNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        return contents
            .filter { item in
                // ディレクトリまたはZIPファイルのみ
                var isDir: ObjCBool = false
                fm.fileExists(atPath: item.path, isDirectory: &isDir)
                return isDir.boolValue || item.pathExtension.lowercased() == "zip" || item.pathExtension.lowercased() == "pdf"
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { FolderNode(url: $0) }
    }
}
