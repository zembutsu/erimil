//
//  ThumbnailGridView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Key Event Handler (NSViewRepresentable)

struct KeyEventHandlerView: NSViewRepresentable {
    var onKeyEvent: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> KeyEventView {
        let view = KeyEventView()
        view.onKeyEvent = onKeyEvent
        // Become first responder after a brief delay
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: KeyEventView, context: Context) {
        nsView.onKeyEvent = onKeyEvent
        // Re-acquire first responder if needed
        if nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
    
    class KeyEventView: NSView {
        var onKeyEvent: ((NSEvent) -> Bool)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            if let handler = onKeyEvent, handler(event) {
                // Event consumed
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Preview Mode

/// Preview display mode
enum PreviewMode: Equatable {
    case none
    case quickLook(index: Int)   // Window-based preview
    case slideMode(index: Int)   // Fullscreen presentation
    
    var index: Int? {
        switch self {
        case .none: return nil
        case .quickLook(let i), .slideMode(let i): return i
        }
    }
    
    var isPresented: Bool {
        self != .none
    }
    
    var isQuickLook: Bool {
        if case .quickLook = self { return true }
        return false
    }
    
    var isSlideMode: Bool {
        if case .slideMode = self { return true }
        return false
    }
}

struct ThumbnailGridView: View {
    let imageSource: any ImageSource
    @Binding var selectedPaths: Set<String>  // Changed: Binding from parent
    var onExportSuccess: (() -> Void)?
    var onRequestNextSource: (() -> Void)?      // S005: Source navigation
    var onRequestPreviousSource: (() -> Void)?  // S005: Source navigation
    @Binding var shouldReopenSlideMode: Bool    // S005: Reopen after source switch
    
    @ObservedObject private var settings = AppSettings.shared
    
    @State private var entries: [ImageEntry] = []
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var previewMode: PreviewMode = .none  // Changed: enum for Quick Look vs Slide Mode
    @State private var showExportSuccess = false
    @State private var showExportError = false
    @State private var showDeleteConfirm = false
    @State private var exportMessage = ""
    
    // Keyboard navigation
    @State private var focusedIndex: Int? = nil
    @State private var columnCount: Int = 4
    
    // Generation ID to invalidate stale async results
    @State private var loadID: UUID = UUID()
    // Track current source URL for change detection
    @State private var currentSourceURL: URL?
    // Content hashes for favorite lookup (path → contentHash)
    @State private var contentHashes: [String: String] = [:]
    // Trigger for favorite state changes (increment to force re-render)
    @State private var favoritesVersion: Int = 0
    // Temporary feedback when trying to select protected item
    @State private var protectedFeedbackPath: String? = nil
    
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
                GeometryReader { geometry in
                    ZStack {
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                        ThumbnailCell(
                                            entry: entry,
                                            thumbnail: thumbnails[entry.path],
                                            isSelected: selectedPaths.contains(entry.path),
                                            isFocused: focusedIndex == index,
                                            favoriteStatus: getFavoriteStatus(entry),
                                            selectionMode: settings.selectionMode,
                                            size: settings.effectiveThumbnailSize,
                                            showProtectedFeedback: protectedFeedbackPath == entry.path
                                        )
                                        .id(index)
                                        .onTapGesture(count: 2) {
                                            openPreview(at: index)
                                        }
                                        .onTapGesture(count: 1) {
                                            focusedIndex = index
                                            toggleSelection(entry)
                                        }
                                        .onAppear {
                                            loadThumbnailIfNeeded(for: entry)
                                        }
                                    }
                                }
                                .padding()
                            }
                            .onChange(of: focusedIndex) { _, newIndex in
                                if let index = newIndex {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        scrollProxy.scrollTo(index, anchor: .center)
                                    }
                                }
                            }
                        }
                        
                        // Key event handler overlay (transparent, captures keys)
                        KeyEventHandlerView { event in
                            handleKeyEvent(event)
                        }
                        .allowsHitTesting(false)  // Let clicks pass through to grid
                    }
                    .onAppear {
                        updateColumnCount(for: geometry.size.width)
                        // Initialize focus
                        if focusedIndex == nil && !entries.isEmpty {
                            focusedIndex = 0
                        }
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        updateColumnCount(for: newWidth)
                    }
                    .onChange(of: settings.effectiveThumbnailSize) { _, _ in
                        updateColumnCount(for: geometry.size.width)
                    }
                }
            }
            
            // フッター（選択がある場合のみ表示）
            if !selectedPaths.isEmpty {
                Divider()
                footerView
            }
        }
        .onChange(of: imageSource.url) { oldURL, newURL in
            print("[ThumbnailGridView] onChange(url): \(oldURL.lastPathComponent) → \(newURL.lastPathComponent)")
            if currentSourceURL != newURL {
                loadSource()
            }
        }
        .onAppear {
            print("[ThumbnailGridView] onAppear: \(imageSource.url.lastPathComponent)")
            print("[ThumbnailGridView] currentSourceURL: \(currentSourceURL?.lastPathComponent ?? "nil")")
            // Always load if URL changed or first appearance
            if currentSourceURL != imageSource.url {
                loadSource()
            }
        }
        // Quick Look mode (sheet)
        .sheet(isPresented: Binding(
            get: { previewMode.isQuickLook },
            set: { if !$0 { previewMode = .none } }
        )) {
            if let index = previewMode.index {
                ImagePreviewView(
                    imageSource: imageSource,
                    entries: entries,
                    initialIndex: index,
                    favoriteIndices: favoriteIndices,
                    onClose: { previewMode = .none },
                    onToggleFullScreen: {
                        print("[ThumbnailGridView] onToggleFullScreen called")
                        print("[ThumbnailGridView] Current previewMode: \(previewMode)")
                        // Switch from Quick Look to Slide Mode
                        if let idx = previewMode.index {
                            print("[ThumbnailGridView] Setting previewMode to .slideMode(index: \(idx))")
                            previewMode = .slideMode(index: idx)
                        } else {
                            print("[ThumbnailGridView] ERROR: previewMode.index is nil")
                        }
                    }
                )
            }
        }
        // Slide Mode - opens separate fullscreen window
        .onChange(of: previewMode) { oldMode, newMode in
            print("[ThumbnailGridView] previewMode changed: \(oldMode) → \(newMode)")
            
            if case .slideMode(let index) = newMode {
                print("[ThumbnailGridView] Slide Mode requested at index \(index)")
                // Capture favoriteIndices before closing sheet
                let favIndices = favoriteIndices
                // Close sheet first, then open Slide window
                previewMode = .none
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("[ThumbnailGridView] Opening SlideWindowController...")
                    
                    // S010: Get source position info
                    let positionInfo = SourceNavigator.positionInfo(for: imageSource.url)
                    let sourceName = imageSource.url.lastPathComponent
                    
                    SlideWindowController.shared.open(
                        imageSource: imageSource,
                        entries: entries,
                        initialIndex: index,
                        favoriteIndices: favIndices,
                        sourceName: sourceName,
                        sourcePosition: positionInfo?.position ?? 0,
                        totalSources: positionInfo?.total ?? 0,
                        onClose: {
                            print("[ThumbnailGridView] SlideWindowController closed")
                            // Slide window closed - could optionally return to Quick Look
                        },
                        onIndexChange: { newIndex in
                            // Sync focusedIndex with Slide Mode navigation
                            focusedIndex = newIndex
                        },
                        onNextSource: onRequestNextSource,
                        onPreviousSource: onRequestPreviousSource
                    )
                }
                
                
            }
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
        let protectedCount = protectedFavoriteCount
        
        var summary = "出力: \(keepCount)件 / 除外: \(removeCount)件"
        if protectedCount > 0 {
            summary += " (⭐\(protectedCount)件保護)"
        }
        return summary
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
    
    /// Paths that will be excluded/removed (favorites are excluded from removal)
    private var pathsToRemove: Set<String> {
        let allPaths = Set(entries.map { $0.path })
        var toRemove: Set<String>
        switch settings.selectionMode {
        case .exclude:
            toRemove = selectedPaths
        case .keep:
            toRemove = allPaths.subtracting(selectedPaths)
        }
        // Remove direct favorites from the removal set
        return toRemove.subtracting(directFavoritePaths)
    }
    
    /// Paths that are directly favorited in this source (for delete protection)
    private var directFavoritePaths: Set<String> {
        Set(entries.filter { isDirectFavorite($0) }.map { $0.path })
    }
    
    /// Count of direct favorites that would be removed (for warning)
    private var protectedFavoriteCount: Int {
        let allPaths = Set(entries.map { $0.path })
        var wouldRemove: Set<String>
        switch settings.selectionMode {
        case .exclude:
            wouldRemove = selectedPaths
        case .keep:
            wouldRemove = allPaths.subtracting(selectedPaths)
        }
        return wouldRemove.intersection(directFavoritePaths).count
    }
    
    // MARK: - Data Loading
    
    private func loadSource() {
        // Generate new load ID to invalidate any pending async operations
        let newLoadID = UUID()
        loadID = newLoadID
        currentSourceURL = imageSource.url
        
        print("[ThumbnailGridView] loadSource called for: \(imageSource.url.lastPathComponent)")
        print("[ThumbnailGridView] imageSource type: \(type(of: imageSource))")
        print("[ThumbnailGridView] imageSource.url: \(imageSource.url.path)")
        print("[ThumbnailGridView] New loadID: \(newLoadID)")
        
        thumbnails = [:]
        contentHashes = [:]  // Clear content hashes when source changes
        selectedPaths = []  // Clear selections when source changes
        focusedIndex = nil  // Reset focus when source changes
        previewMode = .none  // Close preview when source changes
        entries = imageSource.listImageEntries()
        
        print("[ThumbnailGridView] Loaded \(entries.count) entries:")
        for (index, entry) in entries.prefix(10).enumerated() {
            print("  [\(index)] \(entry.name) - path: \(entry.path)")
        }
        if entries.count > 10 {
            print("  ... and \(entries.count - 10) more")
        }
        
        // S005: Reopen Slide Mode if flag is set (after source navigation)
        if shouldReopenSlideMode && !entries.isEmpty {
            print("[ThumbnailGridView] Reopening Slide Mode after source switch")
            shouldReopenSlideMode = false
            
            // Delay slightly to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let favIndices = favoriteIndices
                
                // S010: Get source position info
                let positionInfo = SourceNavigator.positionInfo(for: imageSource.url)
                let sourceName = imageSource.url.lastPathComponent

                // Use updateSource to maintain fullscreen state
                SlideWindowController.shared.updateSource(
                    imageSource: imageSource,
                    entries: entries,
                    favoriteIndices: favIndices,
                    sourceName: sourceName,
                    sourcePosition: positionInfo?.position ?? 0,
                    totalSources: positionInfo?.total ?? 0,
                    onClose: {
                        print("[ThumbnailGridView] SlideWindowController closed (after source switch)")
                    },
                    onIndexChange: { newIndex in
                        focusedIndex = newIndex
                    },
                    onNextSource: onRequestNextSource,
                    onPreviousSource: onRequestPreviousSource
                )
            }
        }
    }
    
    private func loadThumbnailIfNeeded(for entry: ImageEntry) {
        // CRITICAL: Check if this call is from a stale View instance
        // SwiftUI may trigger onAppear from old View instances with old imageSource
        guard imageSource.url == currentSourceURL else {
            print("[loadThumbnail] SKIP stale View call: \(entry.name) (imageSource: \(imageSource.url.lastPathComponent), current: \(currentSourceURL?.lastPathComponent ?? "nil"))")
            return
        }
        
        guard thumbnails[entry.path] == nil else { return }
        
        let maxSize = max(settings.effectiveThumbnailSize, 180)
        
        // Capture current state for validation
        let capturedLoadID = loadID
        let capturedSourceURL = imageSource.url
        let currentSource = imageSource
        let entryPath = entry.path
        let entryName = entry.name
        
        // Calculate the full path for CacheManager lookup
        let fullPath: String
        if imageSource is ArchiveManager {
            fullPath = imageSource.url.path + "/" + entry.path
        } else {
            fullPath = entry.path  // FolderManager already has full path
        }
        
        print("[loadThumbnail] Starting for \(entryName) from \(capturedSourceURL.lastPathComponent), loadID: \(capturedLoadID)")
        
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // FIRST: Check validity on main thread BEFORE expensive operation
            var stillValid = false
            DispatchQueue.main.sync {
                stillValid = (capturedLoadID == loadID && capturedSourceURL == currentSourceURL)
                if !stillValid {
                    print("[loadThumbnail] SKIP async stale: \(entryName)")
                }
            }
            
            guard stillValid else { return }
            
            // Now generate thumbnail
            guard let thumbnail = currentSource.thumbnail(for: entry, maxSize: maxSize) else {
                print("[loadThumbnail] Failed for: \(entryName) from \(capturedSourceURL.lastPathComponent)")
                return
            }
            
            // Get content hash from CacheManager (it was registered during thumbnail generation)
            let contentHash = CacheManager.shared.getContentHashForPath(fullPath)
            
            DispatchQueue.main.async {
                // Re-check validity after thumbnail generated
                guard capturedLoadID == loadID else {
                    print("[loadThumbnail] Discarding stale thumbnail: \(entryName) (loadID mismatch)")
                    return
                }
                
                guard capturedSourceURL == currentSourceURL else {
                    print("[loadThumbnail] Discarding stale thumbnail: \(entryName) (URL mismatch)")
                    return
                }
                
                guard entries.contains(where: { $0.path == entryPath }) else {
                    print("[loadThumbnail] Discarding thumbnail for removed entry: \(entryName)")
                    return
                }
                
                thumbnails[entryPath] = thumbnail
                
                // Store content hash for favorite lookup
                if let hash = contentHash {
                    contentHashes[entryPath] = hash
                }
                
                print("[loadThumbnail] Success: \(entryName)")
            }
        }
    }
    
    // MARK: - Keyboard Navigation
    
    private func updateColumnCount(for width: CGFloat) {
        let size = settings.effectiveThumbnailSize
        let itemWidth = size + 8  // size + spacing
        let padding: CGFloat = 32  // padding on both sides
        let availableWidth = width - padding
        let count = max(1, Int(availableWidth / itemWidth))
        columnCount = count
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !entries.isEmpty else { return false }
        
        // Initialize focus if not set
        if focusedIndex == nil {
            focusedIndex = 0
            return true
        }
        
        guard let currentIndex = focusedIndex else { return false }
        
        // Check for special keys
        switch event.keyCode {
        // Arrow keys
        case 123: // Left arrow
            moveFocus(by: -1)
            return true
        case 124: // Right arrow
            moveFocus(by: 1)
            return true
        case 126: // Up arrow
            moveFocus(by: -columnCount)
            return true
        case 125: // Down arrow
            moveFocus(by: columnCount)
            return true
            
        // Escape
        case 53:
            if previewMode.isPresented {
                previewMode = .none
            } else {
                focusedIndex = nil
            }
            return true
            
        // Return/Enter
        case 36:
            if previewMode.isPresented {
                previewMode = .none
            }
            return true
            
        // Space
        case 49:
            if previewMode.isPresented {
                previewMode = .none
            } else {
                openPreview(at: currentIndex)
            }
            return true
            
        default:
            break
        }
        
        // Check for character keys
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        
        switch characters {
        // WASD keys
        case "a":
            moveFocus(by: -1)
            return true
        case "d":
            moveFocus(by: 1)
            return true
        case "w":
            moveFocus(by: -columnCount)
            return true
        case "s":
            moveFocus(by: columnCount)
            return true
            
        // X key - toggle selection
        case "x":
            let entry = entries[currentIndex]
            toggleSelection(entry)
            return true
            
        // V key - toggle favorite
        case "v":
            let entry = entries[currentIndex]
            toggleFavorite(entry)
            return true
            
        // F key - open Slide Mode directly (S006)
        case "f":
            previewMode = .slideMode(index: currentIndex)
            return true
            
        default:
            return false
        }
    }
    
    private func moveFocus(by offset: Int) {
        guard let current = focusedIndex else {
            focusedIndex = 0
            return
        }
        
        let newIndex = current + offset
        
        // Clamp to valid range
        if newIndex >= 0 && newIndex < entries.count {
            focusedIndex = newIndex
        }
    }
    
    // MARK: - User Actions
    
    private func toggleSelection(_ entry: ImageEntry) {
        // In exclude mode, prevent selecting direct favorites (they're protected)
        if settings.selectionMode == .exclude && isDirectFavorite(entry) {
            print("[toggleSelection] Blocked: \(entry.name) is direct favorited (protected)")
            showProtectedFeedback(for: entry)
            return
        }
        
        if selectedPaths.contains(entry.path) {
            selectedPaths.remove(entry.path)
        } else {
            selectedPaths.insert(entry.path)
        }
    }
    
    /// Show temporary "PROTECTED" feedback
    private func showProtectedFeedback(for entry: ImageEntry) {
        withAnimation(.easeInOut(duration: 0.2)) {
            protectedFeedbackPath = entry.path
        }
        
        // Clear after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                if protectedFeedbackPath == entry.path {
                    protectedFeedbackPath = nil
                }
            }
        }
    }
    
    /// Get favorite status for an entry
    private func getFavoriteStatus(_ entry: ImageEntry) -> CacheManager.FavoriteStatus {
        // Reference favoritesVersion to create SwiftUI dependency
        _ = favoritesVersion
        
        let contentHash = contentHashes[entry.path]
        return CacheManager.shared.getFavoriteStatus(
            sourceURL: imageSource.url,
            entryPath: entry.path,
            contentHash: contentHash
        )
    }
    
    /// Get indices of all favorited entries (for z/c navigation)
    private var favoriteIndices: Set<Int> {
        // Reference favoritesVersion to create SwiftUI dependency
        _ = favoritesVersion
        
        var indices = Set<Int>()
        for (index, entry) in entries.enumerated() {
            let status = getFavoriteStatus(entry)
            if status != .none {
                indices.insert(index)
            }
        }
        return indices
    }
    
    /// Check if entry is directly favorited (for delete protection)
    private func isDirectFavorite(_ entry: ImageEntry) -> Bool {
        // Reference favoritesVersion to create SwiftUI dependency
        _ = favoritesVersion
        
        return CacheManager.shared.isDirectFavorite(
            sourceURL: imageSource.url,
            entryPath: entry.path
        )
    }
    
    private func toggleFavorite(_ entry: ImageEntry) {
        let contentHash = contentHashes[entry.path]
        _ = CacheManager.shared.toggleFavorite(
            sourceURL: imageSource.url,
            entryPath: entry.path,
            contentHash: contentHash
        )
        favoritesVersion += 1  // Trigger re-render
    }
    
    private func openPreview(at index: Int) {
        guard index >= 0 && index < entries.count else { return }
        print("[openPreview] Opening preview at index: \(index) - \(entries[index].name)")
        previewMode = .quickLook(index: index)
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
    let isFocused: Bool
    let favoriteStatus: CacheManager.FavoriteStatus
    let selectionMode: SelectionMode
    let size: CGFloat
    let showProtectedFeedback: Bool  // Temporary feedback when trying to select protected item
    
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
    
    /// Border color based on state
    private var borderColor: Color {
        if isFocused {
            return .accentColor  // Blue focus ring
        } else if isSelected {
            return overlayColor
        } else {
            return .clear
        }
    }
    
    /// Border width based on state
    private var borderWidth: CGFloat {
        if isFocused {
            return 3
        } else if isSelected {
            return 3
        } else {
            return 0
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Thumbnail image
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                } else {
                    ProgressView()
                        .frame(width: size, height: size)
                }
                
                // Selection overlay
                if isSelected {
                    Color.black.opacity(0.4)
                    Image(systemName: overlayIcon)
                        .font(iconSize)
                        .foregroundStyle(.white, overlayColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Favorite star overlay (top-left)
                // ★ (yellow) = direct favorite in this source
                // ☆ (gray/white) = inherited from other source
                VStack {
                    HStack {
                        switch favoriteStatus {
                        case .direct:
                            Image(systemName: "star.fill")
                                .font(size < 100 ? .caption : .body)
                                .foregroundStyle(.yellow)
                                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        case .inherited:
                            Image(systemName: "star")
                                .font(size < 100 ? .caption : .body)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 1)
                        case .none:
                            EmptyView()
                        }
                        Spacer()
                    }
                    .padding(4)
                    
                    Spacer()
                    
                    // PROTECTED label - shown temporarily when trying to select protected item
                    if showProtectedFeedback {
                        Text("PROTECTED")
                            .font(.system(size: size < 100 ? 8 : 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.9))
                            .cornerRadius(3)
                            .padding(.bottom, 4)
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: size, height: size)
            .background(isFocused ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            
            Text(entry.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size)
                .foregroundStyle(isFocused ? .primary : .secondary)
        }
    }
}

#Preview {
    ThumbnailGridView(
        imageSource: ArchiveManager(zipURL: URL(fileURLWithPath: "/tmp/test.zip")),
        selectedPaths: .constant([]),
        onExportSuccess: nil,
        shouldReopenSlideMode: .constant(false)
    )
}
