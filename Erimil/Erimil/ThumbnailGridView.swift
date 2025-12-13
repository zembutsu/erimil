//
//  ThumbnailGridView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import SwiftUI

struct ThumbnailGridView: View {
    let zipURL: URL
    
    @State private var entries: [ArchiveEntry] = []
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var archiveManager: ArchiveManager?
    @State private var excludedPaths: Set<String> = []
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 8)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text(zipURL.lastPathComponent)
                    .font(.headline)
                Spacer()
                Text("\(entries.count) 画像")
                    .foregroundStyle(.secondary)
                if !excludedPaths.isEmpty {
                    Text("/ \(excludedPaths.count) 除外")
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            
            Divider()
            
            // サムネイルグリッド
            if entries.isEmpty {
                ContentUnavailableView(
                    "画像がありません",
                    systemImage: "photo",
                    description: Text("このZIPには画像ファイルが含まれていません")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(entries) { entry in
                            ThumbnailCell(
                                entry: entry,
                                thumbnail: thumbnails[entry.path],
                                isExcluded: excludedPaths.contains(entry.path)
                            )
                            .onTapGesture {
                                toggleExclusion(entry)
                            }
                            .onAppear {
                                loadThumbnailIfNeeded(for: entry)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onChange(of: zipURL) { _, newValue in
            loadArchive(url: newValue)
        }
        .onAppear {
            loadArchive(url: zipURL)
        }
    }
    
    private func loadArchive(url: URL) {
        excludedPaths = []
        thumbnails = [:]
        
        let manager = ArchiveManager(zipURL: url)
        archiveManager = manager
        entries = manager.listImageEntries()
    }
    
    private func loadThumbnailIfNeeded(for entry: ArchiveEntry) {
        guard thumbnails[entry.path] == nil,
              let manager = archiveManager else {
            return
        }
        
        // バックグラウンドでサムネイル生成
        DispatchQueue.global(qos: .userInitiated).async {
            if let thumbnail = manager.thumbnail(for: entry) {
                DispatchQueue.main.async {
                    thumbnails[entry.path] = thumbnail
                }
            }
        }
    }
    
    private func toggleExclusion(_ entry: ArchiveEntry) {
        if excludedPaths.contains(entry.path) {
            excludedPaths.remove(entry.path)
        } else {
            excludedPaths.insert(entry.path)
        }
    }
}

struct ThumbnailCell: View {
    let entry: ArchiveEntry
    let thumbnail: NSImage?
    let isExcluded: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                } else {
                    ProgressView()
                        .frame(width: 120, height: 120)
                }
                
                // 除外マーク
                if isExcluded {
                    Color.black.opacity(0.5)
                    Image(systemName: "xmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white, .red)
                }
            }
            .frame(width: 120, height: 120)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isExcluded ? Color.red : Color.clear, lineWidth: 3)
            )
            
            Text(entry.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 120)
        }
    }
}

#Preview {
    ThumbnailGridView(zipURL: URL(fileURLWithPath: "/tmp/test.zip"))
}
