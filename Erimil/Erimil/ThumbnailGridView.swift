//
//  ThumbnailGridView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailGridView: View {
    let zipURL: URL
    
    @State private var entries: [ArchiveEntry] = []
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var archiveManager: ArchiveManager?
    @State private var excludedPaths: Set<String> = []
    @State private var previewEntry: ArchiveEntry?
    @State private var previewImage: NSImage?
    @State private var showExportSuccess = false
    @State private var showExportError = false
    @State private var exportMessage = ""
    
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
                            .onTapGesture(count: 2) {
                                openPreview(entry)
                            }
                            .onTapGesture(count: 1) {
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
            
            // フッター（除外がある場合のみ表示）
            if !excludedPaths.isEmpty {
                Divider()
                
                HStack {
                    Button("選択をクリア") {
                        excludedPaths.removeAll()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("確定 → _opt.zip") {
                        confirmExport()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .onChange(of: zipURL) { _, newValue in
            loadArchive(url: newValue)
        }
        .onAppear {
            loadArchive(url: zipURL)
        }
        .sheet(item: $previewEntry) { entry in
            VStack(spacing: 20) {
                Text("Preview: \(entry.name)")
                    .font(.headline)
                
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 500, maxHeight: 400)
                } else {
                    Text("No image")
                }
                
                Button("Close") {
                    previewEntry = nil
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .frame(width: 600, height: 500)
        }
        .alert("エクスポート完了", isPresented: $showExportSuccess) {
            Button("OK") { }
        } message: {
            Text(exportMessage)
        }
        .alert("エラー", isPresented: $showExportError) {
            Button("OK") { }
        } message: {
            Text(exportMessage)
        }
    }
    
    
    
    private func loadArchive(url: URL) {
        excludedPaths = []
        thumbnails = [:]
        previewEntry = nil
        previewImage = nil
        
        let manager = ArchiveManager(zipURL: url)
        archiveManager = manager
        entries = manager.listImageEntries()
    }
    
    private func loadThumbnailIfNeeded(for entry: ArchiveEntry) {
        guard thumbnails[entry.path] == nil,
              let manager = archiveManager else {
            return
        }
        
        // 既にロード中/失敗済みをマーク（重複防止）
        thumbnails[entry.path] = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let thumbnail = manager.thumbnail(for: entry)
            DispatchQueue.main.async {
                if let thumbnail = thumbnail {
                    thumbnails[entry.path] = thumbnail
                }
                // 失敗した場合はnilのまま（再試行しない）
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
    
    private func openPreview(_ entry: ArchiveEntry) {
        print("openPreview called for: \(entry.name)")
        guard let manager = archiveManager else {
            print("archiveManager is nil")
            return
        }
        
        // 先に画像を取得してからsheetを開く
        if let image = manager.fullImage(for: entry) {
            print("Full image loaded: \(image.size)")
            previewImage = image
            previewEntry = entry  // これがnon-nilになるとsheetが開く
        } else {
            print("Failed to load full image")
        }
    }
    
    private func confirmExport() {
        guard let manager = archiveManager else { return }
        
        // 出力ファイル名: {元名}_opt.zip
        let originalName = zipURL.deletingPathExtension().lastPathComponent
        let outputName = "\(originalName)_opt.zip"
        
        // NSSavePanelで保存先を選択
        let savePanel = NSSavePanel()
        savePanel.title = "最適化ZIPの保存先"
        savePanel.nameFieldStringValue = outputName
        savePanel.allowedContentTypes = [.zip]
        savePanel.directoryURL = zipURL.deletingLastPathComponent()
        
        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return  // キャンセル
        }
        
        // 既存ファイルがあれば削除（SavePanelが確認済み）
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            try manager.exportOptimized(excluding: excludedPaths, to: outputURL)
            exportMessage = "\(outputURL.lastPathComponent) を作成しました\n除外: \(excludedPaths.count) ファイル"
            showExportSuccess = true
            excludedPaths.removeAll()
        } catch {
            print("Export error: \(error)")
            exportMessage = error.localizedDescription
            showExportError = true
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
