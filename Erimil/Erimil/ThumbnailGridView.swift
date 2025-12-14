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
    @Binding var selectedPaths: Set<String>  // Changed: Binding from parent
    var onExportSuccess: (() -> Void)?
    
    @ObservedObject private var settings = AppSettings.shared
    
    @State private var entries: [ImageEntry] = []
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var previewEntry: ImageEntry?
    @State private var previewImage: NSImage?
    @State private var showExportSuccess = false
    @State private var showExportError = false
    @State private var showDeleteConfirm = false
    @State private var exportMessage = ""
    
    /// Dynamic columns based on thumbnail size
    private var columns: [GridItem] {
        let size = settings.effectiveThumbnailSize
        return [GridItem(.adaptive(minimum: size, maximum: size + 30), spacing: 8)]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            headerView
            
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
                                isSelected: selectedPaths.contains(entry.path),
                                selectionMode: settings.selectionMode,
                                size: settings.effectiveThumbnailSize
                            )
                            .onTapGesture(count: 2) {
                                openPreview(entry)
                            }
                            .onTapGesture(count: 1) {
                                toggleSelection(entry)
                            }
                            .onAppear {
                                loadThumbnailIfNeeded(for: entry)
                            }
                        }
                    }
                    .padding()
                }
            }
            
            // フッター（選択がある場合のみ表示）
            if !selectedPaths.isEmpty {
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
            ImagePreviewView(
                image: previewImage ?? NSImage(),
                entryName: entry.name,
                onClose: { previewEntry = nil }
            )
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
            Text("\(pathsToRemove.count) 件のファイルをゴミ箱に移動しますか？")
        }
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Text(imageSource.displayName)
                    .font(.headline)
                
                Spacer()
                
                // Mode toggle button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.selectionMode = (settings.selectionMode == .exclude) ? .keep : .exclude
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: settings.selectionMode == .exclude ? "xmark.circle" : "checkmark.circle")
                        Text(settings.selectionMode.displayName)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(settings.selectionMode == .exclude ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .foregroundStyle(settings.selectionMode == .exclude ? .red : .green)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("クリックでモード切替")
                
                Text("\(entries.count) 画像")
                    .foregroundStyle(.secondary)
                
                if !selectedPaths.isEmpty {
                    Text("/ \(selectedPaths.count) 選択")
                        .foregroundStyle(settings.selectionMode == .exclude ? .orange : .green)
                }
            }
            
            // Thumbnail size slider
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Slider(
                    value: Binding(
                        get: { settings.effectiveThumbnailSize },
                        set: { newValue in
                            settings.thumbnailSizePreset = .custom
                            settings.thumbnailSize = newValue
                        }
                    ),
                    in: 60...300,
                    step: 10
                )
                .frame(width: 120)
                
                Image(systemName: "photo.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("\(Int(settings.effectiveThumbnailSize))px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                    .monospacedDigit()
            }
        }
        .padding()
    }
    
    // MARK: - Footer
    
    @ViewBuilder
    private var footerView: some View {
        HStack {
            Button("選択をクリア") {
                selectedPaths.removeAll()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            // Show what will be exported/deleted
            Text(footerSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            
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
    
    private var footerSummary: String {
        let keepCount = pathsToKeep.count
        let removeCount = pathsToRemove.count
        
        switch settings.selectionMode {
        case .exclude:
            return "出力: \(keepCount)件 / 除外: \(removeCount)件"
        case .keep:
            return "出力: \(keepCount)件 / 除外: \(removeCount)件"
        }
    }
    
    /// Paths that will be included in output
    private var pathsToKeep: Set<String> {
        let allPaths = Set(entries.map { $0.path })
        switch settings.selectionMode {
        case .exclude:
            return allPaths.subtracting(selectedPaths)
        case .keep:
            return selectedPaths
        }
    }
    
    /// Paths that will be excluded/removed
    private var pathsToRemove: Set<String> {
        let allPaths = Set(entries.map { $0.path })
        switch settings.selectionMode {
        case .exclude:
            return selectedPaths
        case .keep:
            return allPaths.subtracting(selectedPaths)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadSource() {
        thumbnails = [:]
        selectedPaths = []  // Clear selections when source changes
        previewEntry = nil
        previewImage = nil
        entries = imageSource.listImageEntries()
    }
    
    private func loadThumbnailIfNeeded(for entry: ImageEntry) {
        guard thumbnails[entry.path] == nil else { return }
        
        let maxSize = max(settings.effectiveThumbnailSize, 180)  // Load at least 180px for quality
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let thumbnail = imageSource.thumbnail(for: entry, maxSize: maxSize) {
                DispatchQueue.main.async {
                    thumbnails[entry.path] = thumbnail
                }
            }
        }
    }
    
    // MARK: - User Actions
    
    private func toggleSelection(_ entry: ImageEntry) {
        if selectedPaths.contains(entry.path) {
            selectedPaths.remove(entry.path)
        } else {
            selectedPaths.insert(entry.path)
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
        savePanel.directoryURL = settings.outputDirectory(for: archiveManager.url)
        
        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return
        }
        
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            try archiveManager.exportOptimized(excluding: pathsToRemove, to: outputURL)
            exportMessage = "\(outputURL.lastPathComponent) を作成しました\n含む: \(pathsToKeep.count) ファイル / 除外: \(pathsToRemove.count) ファイル"
            showExportSuccess = true
            selectedPaths.removeAll()  // Clear selections after success
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
        savePanel.directoryURL = settings.outputDirectory(for: folderManager.url)
        
        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return
        }
        
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            try folderManager.createZip(excluding: pathsToRemove, to: outputURL)
            exportMessage = "\(outputURL.lastPathComponent) を作成しました\n含む: \(pathsToKeep.count) ファイル"
            showExportSuccess = true
            selectedPaths.removeAll()  // Clear selections after success
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
            let count = try folderManager.moveToTrash(paths: pathsToRemove)
            exportMessage = "\(count) 件のファイルをゴミ箱に移動しました"
            showExportSuccess = true
            selectedPaths.removeAll()  // Clear selections after success
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
    let isSelected: Bool
    let selectionMode: SelectionMode
    let size: CGFloat
    
    private var overlayColor: Color {
        switch selectionMode {
        case .exclude:
            return .red
        case .keep:
            return .green
        }
    }
    
    private var overlayIcon: String {
        switch selectionMode {
        case .exclude:
            return "xmark.circle.fill"
        case .keep:
            return "checkmark.circle.fill"
        }
    }
    
    private var iconSize: Font {
        if size < 100 {
            return .title2
        } else if size < 150 {
            return .largeTitle
        } else {
            return .system(size: 48)
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                } else {
                    ProgressView()
                        .frame(width: size, height: size)
                }
                
                if isSelected {
                    Color.black.opacity(0.4)
                    Image(systemName: overlayIcon)
                        .font(iconSize)
                        .foregroundStyle(.white, overlayColor)
                }
            }
            .frame(width: size, height: size)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? overlayColor : Color.clear, lineWidth: 3)
            )
            
            Text(entry.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size)
        }
    }
}

#Preview {
    ThumbnailGridView(
        imageSource: ArchiveManager(zipURL: URL(fileURLWithPath: "/tmp/test.zip")),
        selectedPaths: .constant([]),
        onExportSuccess: nil
    )
}
