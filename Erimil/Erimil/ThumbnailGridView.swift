//
//  ThumbnailGridView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//  Updated: S017 (2026-01-24) - Added W/S/↑/↓ key bindings (#53)
//  Updated: S017 (2026-01-24) - Resume last viewed position (#52)
//  Updated: S020 (2026-01-26) - V key for single page marker (#55)
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
    case viewer(index: Int)      // S013: Windowed viewer mode (Reader Mode)
    
    var index: Int? {
        switch self {
        case .none: return nil
        case .quickLook(let i), .slideMode(let i), .viewer(let i): return i
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
    
    var isViewer: Bool {
        if case .viewer = self { return true }
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
    @Binding var shouldReopenViewerMode: Bool   // S016: Reopen Viewer Mode after source switch
    
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

    // #54: Reading direction change trigger
    @State private var readingDirectionVersion: Int = 0
    
    /// Dynamic columns based on thumbnail size
    private var columns: [GridItem] {
        let size = settings.effectiveThumbnailSize
        return [GridItem(.adaptive(minimum: size, maximum: size + 30), spacing: 8)]
    }
    
    /// #52: Last viewed index for this source (for bookmark display)
    private var lastViewedIndex: Int? {
        guard !entries.isEmpty else { return nil }
        if let lastIndex = CacheManager.shared.getLastPosition(for: imageSource.url) {
            return min(lastIndex, entries.count - 1)
        }
        return nil
    }
    /// #54: Effective reading direction for this source
    private var effectiveReadingDirection: ReadingDirection {
        // Reference readingDirectionVersion to trigger re-render
        _ = readingDirectionVersion
        return CacheManager.shared.getEffectiveReadingDirection(for: imageSource.url)
    }

    var body: some View {
        // S013: Viewer Mode - full window image display
        if case .viewer(let viewerIndex) = previewMode {
            ViewerView(
                imageSource: imageSource,
                entries: entries,
                currentIndex: viewerIndex,
                contentHashes: contentHashes,
                favoriteIndices: favoriteIndices,  // #67: Add for SpreadImageViewer
                selectionMode: settings.selectionMode,
                selectedPaths: $selectedPaths,
                favoritesVersion: $favoritesVersion,
                onClose: {
                    previewMode = .none
                },
                onIndexChange: { newIndex in
                    focusedIndex = newIndex
                    previewMode = .viewer(index: newIndex)
                    // #52: Save last position
                    CacheManager.shared.setLastPosition(for: imageSource.url, index: newIndex)
                },
                onEnterSlideMode: { index in
                    // Close Viewer Mode first
                    previewMode = .none
                    
                    // Open Slide Mode directly
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let positionInfo = SourceNavigator.positionInfo(for: imageSource.url)
                        let sourceName = imageSource.url.lastPathComponent
                        let selectedIndices = Set(entries.enumerated().compactMap { idx, entry in
                            selectedPaths.contains(entry.path) ? idx : nil
                        })
                        
                        SlideWindowController.shared.open(
                            imageSource: imageSource,
                            entries: entries,
                            initialIndex: index,
                            favoriteIndices: favoriteIndices,
                            selectedIndices: selectedIndices,
                            sourceName: sourceName,
                            sourcePosition: positionInfo?.position ?? 0,
                            totalSources: positionInfo?.total ?? 0,
                            onClose: {
                                print("[ThumbnailGridView] SlideWindowController closed from ViewerMode")
                            },
                            onIndexChange: { newIndex in
                                focusedIndex = newIndex
                                // #52: Save last position
                                CacheManager.shared.setLastPosition(for: imageSource.url, index: newIndex)
                            },
                            onNextSource: onRequestNextSource,
                            onPreviousSource: onRequestPreviousSource,
                            onToggleFavorite: { [self] idx in
                                guard idx >= 0, idx < entries.count else { return }
                                let entry = entries[idx]
                                let hash = contentHashes[entry.path]
                                _ = CacheManager.shared.toggleFavorite(
                                    sourceURL: imageSource.url,
                                    entryPath: entry.path,
                                    contentHash: hash
                                )
                                favoritesVersion += 1
                            },
                            onToggleSelection: { [self] idx in
                                guard idx >= 0, idx < entries.count else { return }
                                let entry = entries[idx]
                                if selectedPaths.contains(entry.path) {
                                    selectedPaths.remove(entry.path)
                                } else {
                                    selectedPaths.insert(entry.path)
                                }
                            },
                            onExitToViewerMode: {
                                let currentIdx = SlideWindowController.shared.getCurrentIndex
                                previewMode = .viewer(index: currentIdx)
                            }
                        )
                    }
                },
                onRequestNextSource: {
                    shouldReopenViewerMode = true  // 追加
                    onRequestNextSource?()
                },
                onRequestPreviousSource: {
                    shouldReopenViewerMode = true  // 追加
                    onRequestPreviousSource?()
                }
            )
        } else {
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
                                            showProtectedFeedback: protectedFeedbackPath == entry.path,
                                            isLastViewed: index == lastViewedIndex  // #52
                                        )
                                        .id(index)
                                        .onTapGesture(count: 2) {
                                            //openPreview(at: index)
                                            // S010: Double-click opens Slide Mode directly
                                            previewMode = .slideMode(index: index)
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
                                .environment(\.layoutDirection, effectiveReadingDirection.layoutDirection) // #54
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
        .onChange(of: entries) { _, newEntries in
            // S016: Reopen Viewer Mode if flag is set
            if shouldReopenViewerMode && !newEntries.isEmpty {
                // #52: Restore last position when reopening Viewer Mode after source switch
                let startIndex: Int
                if let lastIndex = CacheManager.shared.getLastPosition(for: imageSource.url) {
                    startIndex = min(lastIndex, newEntries.count - 1)
                } else {
                    startIndex = 0
                }
                previewMode = .viewer(index: startIndex)
                shouldReopenViewerMode = false
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
        // S010: Watch for Slide Mode open request from sidebar double-click
        .onChange(of: shouldReopenSlideMode) { _, newValue in
            if newValue && !entries.isEmpty && !SlideWindowController.shared.isOpen {
                print("[ThumbnailGridView] shouldReopenSlideMode triggered, opening Slide Mode")
                shouldReopenSlideMode = false
                let index = focusedIndex ?? 0
                previewMode = .slideMode(index: index)
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
                    
                    // S010: Convert selectedPaths to indices
                    let selectedIndices = Set(entries.enumerated().compactMap { index, entry in
                        selectedPaths.contains(entry.path) ? index : nil
                    })
                    
                    SlideWindowController.shared.open(
                        imageSource: imageSource,
                        entries: entries,
                        initialIndex: index,
                        favoriteIndices: favIndices,
                        selectedIndices: selectedIndices,
                        sourceName: sourceName,
                        sourcePosition: positionInfo?.position ?? 0,
                        totalSources: positionInfo?.total ?? 0,
                        onClose: {
                            print("[ThumbnailGridView] SlideWindowController closed")
                        },
                        onIndexChange: { newIndex in
                            focusedIndex = newIndex
                            // #52: Save last position
                            CacheManager.shared.setLastPosition(for: imageSource.url, index: newIndex)
                        },
                        onNextSource: onRequestNextSource,
                        onPreviousSource: onRequestPreviousSource,
                        onToggleFavorite: { [self] index in
                            // Toggle favorite for entry at index
                            guard index >= 0, index < entries.count else { return }
                            let entry = entries[index]
                            let hash = contentHashes[entry.path]
                            _ = CacheManager.shared.toggleFavorite(
                                sourceURL: imageSource.url,
                                entryPath: entry.path,
                                contentHash: hash
                            )
                            favoritesVersion += 1
                        },
                        onToggleSelection: { [self] index in
                            // Toggle selection for entry at index
                            guard index >= 0, index < entries.count else { return }
                            let entry = entries[index]
                            if selectedPaths.contains(entry.path) {
                                selectedPaths.remove(entry.path)
                            } else {
                                selectedPaths.insert(entry.path)
                            }
                        },
                        onExitToViewerMode: {
                            // Get current index from SlideWindowController and open Viewer Mode
                            let currentIdx = SlideWindowController.shared.getCurrentIndex
                            previewMode = .viewer(index: currentIdx)
                        }
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
        } // end else (Grid view)
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
            
            case .pdf:
                EmptyView()
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
        
        // #52: Filer does not restore last position
        // Last position is restored when entering Viewer/Slide Mode
        if !entries.isEmpty {
            focusedIndex = 0
        }
        
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

                // S010: Convert selectedPaths to indices (empty for new source)
                let selectedIndices: Set<Int> = []

                // Use updateSource to maintain fullscreen state
                SlideWindowController.shared.updateSource(
                    imageSource: imageSource,
                    entries: entries,
                    favoriteIndices: favIndices,
                    selectedIndices: selectedIndices,
                    sourceName: sourceName,
                    sourcePosition: positionInfo?.position ?? 0,
                    totalSources: positionInfo?.total ?? 0,
                    onClose: {
                        print("[ThumbnailGridView] SlideWindowController closed (after source switch)")
                    },
                    onIndexChange: { newIndex in
                        focusedIndex = newIndex
                        // #52: Save last position
                        CacheManager.shared.setLastPosition(for: imageSource.url, index: newIndex)
                    },
                    onNextSource: onRequestNextSource,
                    onPreviousSource: onRequestPreviousSource,
                    onToggleFavorite: { [self] index in
                        guard index >= 0, index < entries.count else { return }
                        let entry = entries[index]
                        let hash = contentHashes[entry.path]
                        _ = CacheManager.shared.toggleFavorite(
                            sourceURL: imageSource.url,
                            entryPath: entry.path,
                            contentHash: hash
                        )
                        favoritesVersion += 1
                    },
                    onToggleSelection: { [self] index in
                        guard index >= 0, index < entries.count else { return }
                        let entry = entries[index]
                        if selectedPaths.contains(entry.path) {
                            selectedPaths.remove(entry.path)
                        } else {
                            selectedPaths.insert(entry.path)
                        }
                    }
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
            if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                moveFocus(by: -1)
            }
            return true
        case 124: // Right arrow
            if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                moveFocus(by: 1)
            }
            return true
        case 126: // Up arrow - S017: added Ctrl+ for source nav
            if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                moveFocus(by: -columnCount)
            }
            return true
        case 125: // Down arrow - S017: added Ctrl+ for source nav
            if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                moveFocus(by: columnCount)
            }
            return true
            
        // Escape
        case 53:
            if previewMode.isPresented {
                previewMode = .none
            } else {
                focusedIndex = nil
            }
            return true
            
        // Return/Enter - #52: Open Slide Mode from bookmark (default)
        case 36:
            if previewMode.isPresented {
                previewMode = .none
            } else {
                // S010: Open Slide Mode from filer
                // #52: Start from bookmark if available
                let startIndex = lastViewedIndex ?? currentIndex
                previewMode = .slideMode(index: startIndex)
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
        // A - previous image, Shift+A - previous source
        case "a":
            if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                moveFocus(by: -1)
            }
            return true

        // D - next image, Shift+D - next source
        case "d":
            if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                moveFocus(by: 1)
            }
            return true
        // S017: W - row up, Ctrl+W - previous source
        case "w":
            if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                moveFocus(by: -columnCount)
            }
            return true
        // S017: S - row down, Ctrl+S - next source
        case "s":
            if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                moveFocus(by: columnCount)
            }
            return true
            
        // X key - toggle selection
        case "x":
            let entry = entries[currentIndex]
            toggleSelection(entry)
            return true
            
        // #55: V key - toggle single page marker (previously: favorite)
        case "v":
            let added = CacheManager.shared.toggleSinglePageMarker(for: imageSource.url, at: currentIndex)
            print("[ThumbnailGridView] Single page marker at \(currentIndex): \(added ? "ON" : "OFF")")
            return true
            
        // F key - open Slide Mode directly (S006)
        // case "f":
        //    previewMode = .slideMode(index: currentIndex)
        //    return true

        // F key - toggle favorite / Ctrl+F = Slide Mode (S010)
        // #52: Ctrl+F opens from current (ignores bookmark)
        case "f":
            let hasControl = event.modifierFlags.contains(.control)
            if hasControl {
                // Ctrl+F = Slide Mode from current (explicit selection)
                if let index = focusedIndex {
                    previewMode = .slideMode(index: index)
                }
            } else {
                // F = Toggle favorite
                if let index = focusedIndex, index < entries.count {
                    let entry = entries[index]
                    let hash = contentHashes[entry.path]
                    _ = CacheManager.shared.toggleFavorite(
                        sourceURL: imageSource.url,
                        entryPath: entry.path,
                        contentHash: hash
                    )
                    favoritesVersion += 1
                }
            }
            return true
            
        // S013: R key - open Viewer Mode (Reader Mode)
        // #52: R = open from bookmark (default)
        // #54: Ctrl+R = toggle reading direction (RTL/LTR)
        case "r":
            if event.modifierFlags.contains(.control) {
                // Ctrl+R: Toggle reading direction
                let newDirection = CacheManager.shared.toggleReadingDirection(for: imageSource.url)
                readingDirectionVersion += 1
                print("[Filer] Reading direction toggled to: \(newDirection.displayName)")
            } else {
                // R: Open from bookmark (last viewed), fallback to current
                let startIndex = lastViewedIndex ?? currentIndex
                previewMode = .viewer(index: startIndex)
            }
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
        
        // Clamp to valid range or loop
        if newIndex >= 0 && newIndex < entries.count {
            focusedIndex = newIndex
        } else if settings.loopWithinSource {
            if newIndex < 0 {
                focusedIndex = entries.count - 1  // Loop to last
            } else if newIndex >= entries.count {
                focusedIndex = 0  // Loop to first
            }
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
    let isLastViewed: Bool  // #52: Show bookmark icon for last viewed position
    
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
                
                // Favorite star overlay (top-left) and bookmark (top-right)
                // ★ (yellow) = direct favorite in this source
                // 🔖 (bookmark) = last viewed position (#52)
                VStack {
                    HStack {
                        // Left: Favorite star
                        switch favoriteStatus {
                        case .direct:
                            Image(systemName: "star.fill")
                                .font(size < 100 ? .caption : .body)
                                .foregroundStyle(.yellow)
                                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        case .inherited, .none:
                            EmptyView()
                        }
                        
                        Spacer()
                        
                        // Right: Bookmark for last viewed position (#52)
                        if isLastViewed {
                            Image(systemName: "bookmark.fill")
                                .font(size < 100 ? .caption : .body)
                                .foregroundStyle(.orange)
                                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        }
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
// MARK: - S014: ThumbnailSidebarView
//
// Note: Spread thumbnail display is deferred to a future issue.
// Currently displays all thumbnails as single items.
// The main image area (SpreadImageViewer) handles spread display.
//

struct ThumbnailSidebarView: View {
    let imageSource: any ImageSource
    let entries: [ImageEntry]
    let currentIndex: Int
    let contentHashes: [String: String]
    let selectedPaths: Set<String>
    let favoritesVersion: Int
    let selectionMode: SelectionMode
    let orientation: SidebarOrientation
    var onSelect: (Int) -> Void
    
    enum SidebarOrientation {
        case vertical    // left sidebar
        case horizontal  // bottom bar
    }
    
    private let thumbnailSize: CGFloat = 80
    private let sidebarWidth: CGFloat = 100
    private let sidebarHeight: CGFloat = 100
    
    var body: some View {
        ScrollViewReader { proxy in
            if orientation == .vertical {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        thumbnailItems
                    }
                    .padding(.vertical, 8)
                }
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.8))
                .onChange(of: currentIndex) { _, newIndex in
                    scrollToIndex(newIndex, proxy: proxy)
                }
                .onAppear {
                    if currentIndex < entries.count {
                        scrollToIndex(currentIndex, proxy: proxy)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 4) {
                        thumbnailItems
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: sidebarHeight)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.8))
                .onChange(of: currentIndex) { _, newIndex in
                    scrollToIndex(newIndex, proxy: proxy)
                }
                .onAppear {
                    if currentIndex < entries.count {
                        scrollToIndex(currentIndex, proxy: proxy)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var thumbnailItems: some View {
        ForEach(Array(entries.enumerated()), id: \.element.path) { index, entry in
            ThumbnailItemView(
                imageSource: imageSource,
                entry: entry,
                index: index,
                isCurrent: index == currentIndex,
                favoriteStatus: getFavoriteStatus(entry),
                isSelected: selectedPaths.contains(entry.path),
                selectionMode: selectionMode,
                size: thumbnailSize,
                onTap: { onSelect(index) }
            )
            .id("\(index)-\(favoritesVersion)-\(selectedPaths.contains(entry.path))")
        }
    }
    
    private func scrollToIndex(_ index: Int, proxy: ScrollViewProxy) {
        guard index >= 0, index < entries.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo("\(index)-\(favoritesVersion)-\(selectedPaths.contains(entries[index].path))", anchor: .center)
        }
    }
    
    private func getFavoriteStatus(_ entry: ImageEntry) -> CacheManager.FavoriteStatus {
        let hash = contentHashes[entry.path]
        return CacheManager.shared.getFavoriteStatus(
            sourceURL: imageSource.url,
            entryPath: entry.path,
            contentHash: hash
        )
    }
}

struct ThumbnailItemView: View {
    let imageSource: any ImageSource
    let entry: ImageEntry
    let index: Int
    let isCurrent: Bool
    let favoriteStatus: CacheManager.FavoriteStatus
    let isSelected: Bool
    let selectionMode: SelectionMode
    let size: CGFloat
    var onTap: () -> Void
    
    @State private var thumbnail: NSImage? = nil
    
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
    
    var body: some View {
        ZStack {
            // Thumbnail image
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(.white)
                    }
            }
            
            // Selection overlay (center icon)
            if isSelected {
                Color.black.opacity(0.4)
                Image(systemName: overlayIcon)
                    .font(.title2)
                    .foregroundStyle(.white, overlayColor)
            }
            
            // Favorite star (top-left) - only show direct favorites
            VStack {
                HStack {
                    if favoriteStatus == .direct {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                    }
                    Spacer()
                }
                .padding(3)
                Spacer()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isCurrent ? Color.blue : (isSelected ? overlayColor : Color.clear), lineWidth: 3)
        )
        .onTapGesture { onTap() }
        .onAppear { loadThumbnail() }
    }
    
    private func loadThumbnail() {
        DispatchQueue.global(qos: .utility).async {
            let image = imageSource.thumbnail(for: entry, maxSize: size * 2)
            DispatchQueue.main.async {
                thumbnail = image
            }
        }
    }
}

// MARK: - ViewerView (S021: Refactored for SpreadImageViewer #67)
//
// This replaces the ViewerView struct in ThumbnailGridView.swift (lines 1549-2075)
// Changes:
// - Added favoriteIndices parameter for SpreadImageViewer
// - Replaced single image display with SpreadImageViewer
// - Added @State viewerIndex for SpreadImageViewer binding
// - Navigation uses SpreadNavigationHelper
// - Removed displayedImage, isLoading, prefetcher (SpreadImageViewer handles these)
//

struct ViewerView: View {
    let imageSource: any ImageSource
    let entries: [ImageEntry]
    let currentIndex: Int
    let contentHashes: [String: String]
    let favoriteIndices: Set<Int>  // #67: Added for SpreadImageViewer
    let selectionMode: SelectionMode
    @Binding var selectedPaths: Set<String>
    @Binding var favoritesVersion: Int
    
    var onClose: () -> Void
    var onIndexChange: (Int) -> Void
    var onEnterSlideMode: (Int) -> Void
    var onRequestNextSource: (() -> Void)?
    var onRequestPreviousSource: (() -> Void)?
    
    @ObservedObject private var settings = AppSettings.shared
    
    // #67: Local index state for SpreadImageViewer binding
    @State private var viewerIndex: Int = 0
    @State private var spreadUpdateTrigger: Bool = false  // #67: For V key updates
    @State private var isShowingSpread: Bool = false  // #67: Track if currently showing spread
    @State private var couldBeSpreadWithPrevious: Bool = false  // #67: Could form spread with prev
    
    // #67: Navigation correction for backward spread
    @State private var preNavIndex: Int = 0  // Index before navigation
    @State private var navDirection: Int = 0  // 0=none, -1=backward, 1=forward
    
    // #67: Removed - now handled by SpreadImageViewer
    // @State private var displayedImage: NSImage? = nil
    // @State private var isLoading: Bool = true
    // @State private var prefetcher = ImagePrefetcher()
    
    @State private var previousViewerIndex: Int = 0
    @State private var currentSourceURL: URL?
    
    /// #54: Effective reading direction for this source
    private var effectiveReadingDirection: ReadingDirection {
        CacheManager.shared.getEffectiveReadingDirection(for: imageSource.url)
    }

    private var currentEntry: ImageEntry? {
        guard viewerIndex >= 0, viewerIndex < entries.count else { return nil }
        return entries[viewerIndex]
    }
    
    private var isCurrentFavorite: Bool {
        guard let entry = currentEntry else { return false }
        let hash = contentHashes[entry.path]
        let status = CacheManager.shared.getFavoriteStatus(
            sourceURL: imageSource.url,
            entryPath: entry.path,
            contentHash: hash
        )
        return status == .direct
    }
    
    private var isCurrentSelected: Bool {
        guard let entry = currentEntry else { return false }
        return selectedPaths.contains(entry.path)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Main content area with thumbnail sidebar
                switch settings.viewerThumbnailPosition {
                case .left:
                    HStack(spacing: 0) {
                        ThumbnailSidebarView(
                            imageSource: imageSource,
                            entries: entries,
                            currentIndex: viewerIndex,
                            contentHashes: contentHashes,
                            selectedPaths: selectedPaths,
                            favoritesVersion: favoritesVersion,
                            selectionMode: selectionMode,
                            orientation: .vertical,
                            onSelect: { index in navigateTo(index) }
                        )
                        mainContentView
                    }
                    
                case .bottom:
                    VStack(spacing: 0) {
                        mainContentView
                        ThumbnailSidebarView(
                            imageSource: imageSource,
                            entries: entries,
                            currentIndex: viewerIndex,
                            contentHashes: contentHashes,
                            selectedPaths: selectedPaths,
                            favoritesVersion: favoritesVersion,
                            selectionMode: selectionMode,
                            orientation: .horizontal,
                            onSelect: { index in navigateTo(index) }
                        )
                    }
                    .environment(\.layoutDirection, effectiveReadingDirection.layoutDirection)
                    
                case .hidden:
                    mainContentView
                }
            }
            
            // Key event handler (transparent overlay)
            ViewerKeyEventHandler { event in
                handleKeyEvent(event)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            if currentSourceURL != imageSource.url {
                currentSourceURL = imageSource.url
            }
            viewerIndex = currentIndex
            previousViewerIndex = currentIndex
        }
        .onChange(of: currentIndex) { oldValue, newValue in
            // External index change (from parent)
            previousViewerIndex = oldValue
            viewerIndex = newValue
        }
        .onChange(of: viewerIndex) { oldValue, newValue in
            // Internal index change (from SpreadImageViewer or navigation)
            if newValue != currentIndex {
                previousViewerIndex = oldValue
                onIndexChange(newValue)
            }
        }
        .onChange(of: isShowingSpread) { _, _ in
            // #67: Correct backward navigation if needed
            correctBackwardSpread()
        }
        .onChange(of: couldBeSpreadWithPrevious) { _, newValue in
            // #67: If could form spread with previous, and navigating backward, go back more
            if newValue {
                correctBackwardSpread()
            }
        }
    }
    
    // MARK: - Main Content View (#67: Now using SpreadImageViewer)
    
    @ViewBuilder
    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar
            
            // #67: Main image area - now using SpreadImageViewer
            ZStack {
                SpreadImageViewer(
                    imageSource: imageSource,
                    entries: entries,
                    currentIndex: $viewerIndex,
                    favoriteIndices: favoriteIndices,
                    reloadTrigger: spreadUpdateTrigger,
                    isShowingSpread: $isShowingSpread,
                    couldBeSpreadWithPrevious: $couldBeSpreadWithPrevious
                )
                
                // Navigation hints (left/right edges) - #67: Spread-aware
                HStack {
                    // Left arrow area
                    if viewerIndex > 0 {
                        Button {
                            goToPrevious()
                        } label: {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 60)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    // Right arrow area
                    if viewerIndex < entries.count - 1 {
                        Button {
                            goToNext()
                        } label: {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 60)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Footer with keyboard hints
            footerBar
        }
    }
    
    // MARK: - Header Bar
    
    @ViewBuilder
    private var headerBar: some View {
        HStack {
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("閉じる (Esc/Q)")
            
            Spacer()
            
            // Thumbnail position indicator
            Button {
                settings.viewerThumbnailPosition = settings.viewerThumbnailPosition.next
            } label: {
                Image(systemName: thumbnailPositionIcon)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("サムネイル位置: \(settings.viewerThumbnailPosition.displayName) (T)")
            
            Spacer()
            
            // Favorite indicator
            if isCurrentFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
            
            // Selection indicator
            if isCurrentSelected {
                Image(systemName: selectionMode == .exclude ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(selectionMode == .exclude ? .red : .green)
            }
            
            // File name
            if let entry = currentEntry {
                Text(entry.name)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Position indicator
            Text("\(viewerIndex + 1) / \(entries.count)")
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
            
            // Fullscreen button
            Button {
                onEnterSlideMode(viewerIndex)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("全画面表示 (Enter)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
    }
    
    private var thumbnailPositionIcon: String {
        switch settings.viewerThumbnailPosition {
        case .left: return "sidebar.left"
        case .bottom: return "sidebar.bottom"
        case .hidden: return "sidebar.squares.leading"
        }
    }
    
    // MARK: - Footer Bar
    
    @ViewBuilder
    private var footerBar: some View {
        HStack {
            Text("←→: ページ")
            Text("Ctrl+←→: ソース")
            Text("F: ★")
            Text("X: 選択")
            Text("T: サムネイル")
            // #55: Show V key hint only when spread mode is enabled
            if AppSettings.shared.isSpreadModeEnabled {
                Text("V: 単独")
            }
            Text("Enter: 全画面")
            Text("Esc: 閉じる")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.5))
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
    }
    
    // MARK: - Navigation (#67: Spread-aware using isShowingSpread)
    
    private func navigateTo(_ index: Int) {
        guard index >= 0, index < entries.count else { return }
        print("[ViewerView] navigateTo: \(viewerIndex) → \(index)")
        previousViewerIndex = viewerIndex
        viewerIndex = index
    }
    
    private func goToPrevious() {
        print("[ViewerView] goToPrevious called, current: \(viewerIndex), isShowingSpread: \(isShowingSpread)")
        
        guard viewerIndex > 0 || settings.loopWithinSource else { return }
        
        // #67 Phase 3: Try to determine step using cached aspect ratios
        if viewerIndex >= 2 {
            let prevIndex = viewerIndex - 2
            // Check if page at prevIndex would form a spread
            let wouldBeSingle = SpreadNavigationHelper.shouldShowSinglePage(
                for: imageSource.url,
                at: prevIndex,
                totalCount: entries.count,
                entries: entries
            )
            
            if !wouldBeSingle {
                // Previous spread starts at prevIndex, skip 2
                print("[ViewerView] goToPrevious: cached spread at \(prevIndex), stepping -2")
                preNavIndex = viewerIndex
                navDirection = 0  // No correction needed
                navigateTo(prevIndex)
                return
            }
        }
        
        // Fallback: step -1 and let correction handle if needed
        preNavIndex = viewerIndex
        navDirection = -1  // backward, may need correction
        
        if viewerIndex > 0 {
            navigateTo(viewerIndex - 1)
        } else if settings.loopWithinSource {
            navDirection = 0  // Loop is jump, not backward - no correction needed
            navigateTo(entries.count - 1)
        }
    }
    
    private func goToNext() {
        print("[ViewerView] goToNext called, current: \(viewerIndex), isShowingSpread: \(isShowingSpread)")
        preNavIndex = viewerIndex
        navDirection = 1  // forward
        
        // If showing spread, skip the right page (it's already visible)
        let step = isShowingSpread ? 2 : 1
        let nextIndex = viewerIndex + step
        
        if nextIndex < entries.count {
            navigateTo(nextIndex)
        } else if settings.loopWithinSource {
            navigateTo(0)
        } else if viewerIndex < entries.count - 1 {
            // If step would overshoot but there's still a page, go to last page
            navigateTo(entries.count - 1)
        }
    }
    
    /// #67: Correct backward navigation when landing on spread that includes previous page
    /// or when current page could form spread with previous
    private func correctBackwardSpread() {
        guard navDirection == -1 else {
            navDirection = 0
            return
        }
        
        if isShowingSpread {
            // Spread表示で、右ページが元いた場所なら、さらに1つ戻る
            if preNavIndex == viewerIndex + 1 && viewerIndex > 0 {
                print("[ViewerView] Correcting backward spread (showing spread): \(viewerIndex) → \(viewerIndex - 1)")
                preNavIndex = viewerIndex
                viewerIndex -= 1
                return  // Keep navDirection for chained corrections
            }
        } else if couldBeSpreadWithPrevious {
            // 単独表示だが、前のページとspreadになれる可能性がある → 戻ってみる
            if viewerIndex > 0 {
                print("[ViewerView] Correcting backward spread (could be spread): \(viewerIndex) → \(viewerIndex - 1)")
                preNavIndex = viewerIndex
                viewerIndex -= 1
                return  // Keep navDirection for chained corrections
            }
        }
        
        navDirection = 0
    }
    
    // MARK: - Key Event Handling (#67: Spread-aware navigation)
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        // Escape
        case 53:
            onIndexChange(viewerIndex)
            onClose()
            return true
            
        // Return/Enter - go to Slide Mode
        case 36:
            onEnterSlideMode(viewerIndex)
            return true
            
        // Left arrow
        case 123:
            if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                goToPrevious()
            }
            return true
            
        // Right arrow
        case 124:
            if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                goToNext()
            }
            return true
        
        // Up arrow (same as Left) - S017
        case 126:
            if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                goToPrevious()
            }
            return true
            
        // Down arrow (same as Right) - S017
        case 125:
            if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                goToNext()
            }
            return true

        // F key (keyCode 3) - Ctrl+F = Slide Mode
        case 3:
            print("[ViewerView] keyCode 3 detected, control: \(event.modifierFlags.contains(.control))")
            if event.modifierFlags.contains(.control) {
                print("[ViewerView] Ctrl+F → entering Slide Mode")
                onEnterSlideMode(viewerIndex)
                return true
            }
            // Plain F handled in character switch below
            break
            
        default:
            break
        }
        
        // Character keys
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        
        switch characters {
        // Q - close
        case "q":
            onIndexChange(viewerIndex)
            onClose()
            return true
            
        // A - previous (Ctrl+A = previous source)
        case "a":
            if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                goToPrevious()
            }
            return true
            
        // D - next (Ctrl+D = next source)
        case "d":
            if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                goToNext()
            }
            return true
        
        // S017: W - previous (Ctrl+W = previous source)
        case "w":
            if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                goToPrevious()
            }
            return true
            
        // S017: S - next (Ctrl+S = next source)
        case "s":
            if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                goToNext()
            }
            return true

        // F - toggle favorite
        case "f":
            if event.modifierFlags.contains(.control) {
                print("[ViewerView] Ctrl+F (char) → entering Slide Mode")
                onEnterSlideMode(viewerIndex)
            } else {
                guard let entry = currentEntry else { return true }
                let hash = contentHashes[entry.path]
                _ = CacheManager.shared.toggleFavorite(
                    sourceURL: imageSource.url,
                    entryPath: entry.path,
                    contentHash: hash
                )
                favoritesVersion += 1
            }
            return true
        
        // R - exit to Filer (close Viewer Mode)
        // #54: Ctrl+R = toggle reading direction
        case "r":
            if event.modifierFlags.contains(.control) {
                // Ctrl+R: Toggle reading direction
                let newDirection = CacheManager.shared.toggleReadingDirection(for: imageSource.url)
                print("[ViewerView] Reading direction toggled to: \(newDirection.displayName)")
                spreadUpdateTrigger.toggle()  // #67: Trigger SpreadImageViewer refresh
            } else {
                // R: Exit to Filer
                onIndexChange(viewerIndex)
                onClose()
            }
            return true

        // X - toggle selection
        case "x":
            guard let entry = currentEntry else { return true }
            if selectedPaths.contains(entry.path) {
                selectedPaths.remove(entry.path)
            } else {
                selectedPaths.insert(entry.path)
            }
            return true
            
        // T - toggle thumbnail position
        case "t":
            settings.viewerThumbnailPosition = settings.viewerThumbnailPosition.next
            return true
        
        // #55/#67: V - toggle single page marker
        case "v":
            let added = CacheManager.shared.toggleSinglePageMarker(for: imageSource.url, at: viewerIndex)
            print("[ViewerView] Single page marker at \(viewerIndex): \(added ? "ON" : "OFF")")
            spreadUpdateTrigger.toggle()  // #67: Trigger SpreadImageViewer refresh
            return true
            
        default:
            return false
        }
    }
}

// MARK: - ViewerKeyEventHandler (unchanged)

struct ViewerKeyEventHandler: NSViewRepresentable {
    var onKeyEvent: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> ViewerKeyEventView {
        let view = ViewerKeyEventView()
        view.onKeyEvent = onKeyEvent
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: ViewerKeyEventView, context: Context) {
        nsView.onKeyEvent = onKeyEvent
        if nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
    
    class ViewerKeyEventView: NSView {
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

#Preview {
    ThumbnailGridView(
        imageSource: ArchiveManager(zipURL: URL(fileURLWithPath: "/tmp/test.zip")),
        selectedPaths: .constant([]),
        onExportSuccess: nil,
        shouldReopenSlideMode: .constant(false),
        shouldReopenViewerMode: .constant(false)
    )
}
