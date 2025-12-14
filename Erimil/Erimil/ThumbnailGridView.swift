//
//  ThumbnailGridView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailGridView: View {
    let imageSource: any ImageSource
    @Binding var excludedPaths: Set<String>
    var onExportSuccess: (() -> Void)?
    
    @State private var entries: [ImageEntry] = []
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var previewEntry: ImageEntry?
    @State private var previewImage: NSImage?
    @State private var showExportSuccess = false
    @State private var showExportError = false
    @State private var showDeleteConfirm = false
    @State private var exportMessage = ""
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 8)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text(imageSource.displayName)
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
                    description: Text("このフォルダには画像ファイルが含まれていません")
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
                footerView
            }
        }
        .onChange(of: imageSource.url) { _, _ in
            loadSource()
        }
        .onAppear {
            loadSource()
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
        .alert("ゴミ箱に移動", isPresented: $showDeleteConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                performDelete()
            }
        } message: {
            Text("\(excludedPaths.count) 件のファイルをゴミ箱に移動しますか？")
        }
    }
    
    // MARK: - Footer (dynamic based on source type)
    
    @ViewBuilder
    private var footerView: some View {
        HStack {
            Button("選択をクリア") {
                excludedPaths.removeAll()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            switch imageSource.sourceType {
            case .archive:
                Button("確定 → _opt.zip") {
                    confirmExportArchive()
                }
                .buttonStyle(.borderedProminent)
                
            case .folder:
                Button("削除（ゴミ箱）") {
                    showDeleteConfirm = true
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                
                Button("ZIP化") {
                    confirmCreateZip()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
    
    // MARK: - Data Loading
    
    private func loadSource() {
        thumbnails = [:]
        previewEntry = nil
        previewImage = nil
        entries = imageSource.listImageEntries()
    }
    
    private func loadThumbnailIfNeeded(for entry: ImageEntry) {
        guard thumbnails[entry.path] == nil else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let thumbnail = imageSource.thumbnail(for: entry, maxSize: 120) {
                DispatchQueue.main.async {
                    thumbnails[entry.path] = thumbnail
                }
            }
        }
    }
    
    // MARK: - User Actions
    
    private func toggleExclusion(_ entry: ImageEntry) {
        if excludedPaths.contains(entry.path) {
            excludedPaths.remove(entry.path)
        } else {
            excludedPaths.insert(entry.path)
        }
    }
    
    private func openPreview(_ entry: ImageEntry) {
        print("openPreview called for: \(entry.name)")
        
        if let image = imageSource.fullImage(for: entry) {
            print("Full image loaded: \(image.size)")
            previewImage = image
            previewEntry = entry
        } else {
            print("Failed to load full image")
        }
    }
    
    // MARK: - Archive Export
    
    private func confirmExportArchive() {
        guard let archiveManager = imageSource as? ArchiveManager else { return }
        
        let originalName = archiveManager.url.deletingPathExtension().lastPathComponent
        let outputName = "\(originalName)_opt.zip"
        
        let savePanel = NSSavePanel()
        savePanel.title = "最適化ZIPの保存先"
        savePanel.nameFieldStringValue = outputName
        savePanel.allowedContentTypes = [.zip]
        savePanel.directoryURL = archiveManager.url.deletingLastPathComponent()
        
        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return
        }
        
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            try archiveManager.exportOptimized(excluding: excludedPaths, to: outputURL)
            exportMessage = "\(outputURL.lastPathComponent) を作成しました\n除外: \(excludedPaths.count) ファイル"
            showExportSuccess = true
            excludedPaths.removeAll()
            onExportSuccess?()
        } catch {
            print("Export error: \(error)")
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }
    
    // MARK: - Folder Operations
    
    private func confirmCreateZip() {
        guard let folderManager = imageSource as? FolderManager else { return }
        
        let outputName = "\(folderManager.displayName).zip"
        
        let savePanel = NSSavePanel()
        savePanel.title = "ZIPファイルの保存先"
        savePanel.nameFieldStringValue = outputName
        savePanel.allowedContentTypes = [.zip]
        savePanel.directoryURL = folderManager.url.deletingLastPathComponent()
        
        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return
        }
        
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            try folderManager.createZip(excluding: excludedPaths, to: outputURL)
            let includedCount = entries.count - excludedPaths.count
            exportMessage = "\(outputURL.lastPathComponent) を作成しました\n含む: \(includedCount) ファイル"
            showExportSuccess = true
            excludedPaths.removeAll()
            onExportSuccess?()
        } catch {
            print("ZIP creation error: \(error)")
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }
    
    private func performDelete() {
        guard let folderManager = imageSource as? FolderManager else { return }
        
        do {
            let count = try folderManager.moveToTrash(paths: excludedPaths)
            exportMessage = "\(count) 件のファイルをゴミ箱に移動しました"
            showExportSuccess = true
            excludedPaths.removeAll()
            loadSource()  // Refresh the list
            onExportSuccess?()
        } catch {
            print("Delete error: \(error)")
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }
}

// MARK: - ThumbnailCell

struct ThumbnailCell: View {
    let entry: ImageEntry
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
    ThumbnailGridView(
        imageSource: ArchiveManager(zipURL: URL(fileURLWithPath: "/tmp/test.zip")),
        excludedPaths: .constant([]),
        onExportSuccess: nil
    )
}
