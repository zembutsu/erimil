//
//  ThumbnailGridView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//  Updated: S017 (2026-01-24) - Added W/S/↑/↓ key bindings (#53)
//  Updated: S017 (2026-01-24) - Resume last viewed position (#52)
//  Updated: S020 (2026-01-26) - V key for single page marker (#55)
//  Updated: S026 (2026-01-30) - RTL navigation key inversion (#76)
//  Updated: S031 (2026-02-03) - Consolidated key handling (#72): 
//      - Grid mode: ←/→/A/D now RTL-aware, added Z/C favorite navigation
//      - ViewerView: ↑/↓/W/S now RTL-aware, added Z/C favorite navigation
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

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
    case slideMode(index: Int)   // Fullscreen presentation
    case viewer(index: Int)      // S013: Windowed viewer mode (Reader Mode)
    
    var index: Int? {
        switch self {
        case .none: return nil
        case .slideMode(let i), .viewer(let i): return i
        }
    }
    
    var isPresented: Bool {
        self != .none
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

// MARK: - Export Type (#103: deferred export after favorite confirmation)

private enum ExportType {
    case archive, folderZip, pdf, png, pngZip
}

struct ThumbnailGridView: View {
    let imageSource: any ImageSource
    @Binding var selectedPaths: Set<String>  // Changed: Binding from parent
    var onExportSuccess: (() -> Void)?
    var onRequestNextSource: (() -> Void)?      // S005: Source navigation
    var onRequestPreviousSource: (() -> Void)?  // S005: Source navigation
    var onRequestSourceJump: ((Int) -> Void)?   // #143: N-step source navigation
    @Binding var shouldReopenSlideMode: Bool    // S005: Reopen after source switch
    @Binding var shouldReopenViewerMode: Bool   // S016: Reopen Viewer Mode after source switch
    @Binding var isInViewerMode: Bool            // S051: Report Viewer Mode state to parent
    var consumePrefetchedEntries: (() -> [ImageEntry]?)?  // S050: Prefetch from SourceSelection
    
    @ObservedObject private var settings = AppSettings.shared
    
    @State private var entries: [ImageEntry] = []
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var previewMode: PreviewMode = .none  // Changed: enum for Quick Look vs Slide Mode
    @State private var showExportSuccess = false
    @State private var showExportError = false
    @State private var showDeleteConfirm = false
    @State private var showFavoriteExportConfirm = false  // #103
    @State private var pendingExportType: ExportType? = nil  // #103
    @State private var exportMetadataOptions = MetadataCarryOverOptions()  // #105
    @State private var exportMessage = ""
    
    // Keyboard navigation
    @State private var focusedIndex: Int? = nil
    @State private var columnCount: Int = 4
    @State private var isKeyRepeat: Bool = false  // #158: suppress scroll animation during key repeat
    
    // Generation ID to invalidate stale async results
    @State private var loadID: UUID = UUID()
    // Track current source URL for change detection
    @State private var currentSourceURL: URL?
    // Content hashes for favorite lookup (path → contentHash)
    @State private var contentHashes: [String: String] = [:]
    // Trigger for favorite state changes (increment to force re-render)
    @State private var favoritesVersion: Int = 0
    // #62: Trigger for bookmark state changes
    @State private var bookmarksVersion: Int = 0
    // #62 Phase 5: Bookmark list overlay state
    @State private var showBookmarkList: Bool = false
    @State private var bookmarkListCursor: Int = 0
    // Temporary feedback when trying to select protected item
    @State private var protectedFeedbackPath: String? = nil

    // #54: Reading direction change trigger
    @State private var readingDirectionVersion: Int = 0
    @State private var isLoadingSource: Bool = true
    @State private var showLoadingSpinner: Bool = false
    
    // #134 P8: Batch prefetch — OperationQueue to limit concurrent thumbnail generation.
        // Per-cell onAppear dispatch caused thread pool saturation (298 concurrent tasks).
        // maxConcurrentOperationCount=4 keeps CPU busy without flooding GCD.
        @State private var thumbnailQueue: OperationQueue = {
            let q = OperationQueue()
            q.maxConcurrentOperationCount = 4
            q.qualityOfService = .userInitiated
            q.name = "jp.pocketstudio.zem.Erimil.thumbnailLoad"
            return q
        }()
        /// entryPath → Operation mapping for cancel-on-source-switch
        @State private var pendingOperations: [String: Operation] = [:]

    // #138 Coalesced thumbnail buffer — batch assign to reduce body re-evaluation
    private let thumbnailCoalescer = ThumbnailCoalescer()

    private class ThumbnailCoalescer {
        private let lock = NSLock()
        private var buffer: [(path: String, image: NSImage, contentHash: String?)] = []
        private var flushScheduled = false
        
        func append(_ item: (path: String, image: NSImage, contentHash: String?)) -> Bool {
            lock.lock()
            buffer.append(item)
            let needsSchedule = !flushScheduled
            if needsSchedule { flushScheduled = true }
            lock.unlock()
            return needsSchedule
        }
        
        func flush() -> [(path: String, image: NSImage, contentHash: String?)] {
            lock.lock()
            let batch = buffer
            buffer.removeAll()
            flushScheduled = false
            lock.unlock()
            return batch
        }
        
        func clear() {
            lock.lock()
            buffer.removeAll()
            flushScheduled = false
            lock.unlock()
        }
    }
    
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
    
    /// #72: Check if RTL mode for navigation key inversion (Grid mode)
    private var isRTL: Bool {
        effectiveReadingDirection == .rtl
    }

    var body: some View {
        // S051: Guard against stale entries during source switch (#121)
        // When imageSource changes, body re-evaluates BEFORE onChange fires loadSource().
        // Without this guard, ViewerView/ThumbnailSidebarView would render with
        // new imageSource + old entries for one frame, causing "Entry not found" errors.
        let entriesAreStale = currentSourceURL != nil && currentSourceURL != imageSource.url
        let _ = Logger.thumbnailGrid.debug("body: stale=\(entriesAreStale), preview=\(String(describing: previewMode)), reopen=\(shouldReopenViewerMode), loading=\(isLoadingSource), entries=\(entries.count)")
        Group {
            if entriesAreStale {
                // Transient state: source changed, loadSource() pending from onChange
                Color.black.ignoresSafeArea()
            } else if case .viewer(let viewerIndex) = previewMode {
                // S013: Viewer Mode - full window image display
                viewerModeView(index: viewerIndex)
            } else if shouldReopenViewerMode {
                // #122: Suppress Grid flash while waiting for Viewer Mode restoration
                Color.black.ignoresSafeArea()
            } else {
                thumbnailBrowserView
            } // end else (Grid view)
        }
        .onChange(of: imageSource.url) { oldURL, newURL in
            if currentSourceURL != newURL {
                loadSource()
            }
        }
        .onChange(of: entries) { _, newEntries in
            handleEntriesChange(newEntries)
        }
        .onChange(of: previewMode) { _, newMode in
            isInViewerMode = newMode.isViewer
        }
        .onAppear {
            if currentSourceURL != imageSource.url {
                loadSource()
            }
        }
    }
    
    // MARK: - Viewer Mode

    @ViewBuilder
    private func viewerModeView(index viewerIndex: Int) -> some View {
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
                            Logger.thumbnailGrid.info("SlideWindowController closed from ViewerMode")
                        },
                        onIndexChange: { newIndex in
                            focusedIndex = newIndex
                            // #52: Save last position
                            CacheManager.shared.setLastPosition(for: imageSource.url, index: newIndex)
                        },
                        onNextSource: onRequestNextSource,
                        onPreviousSource: onRequestPreviousSource,
                        onSourceJump: onRequestSourceJump,
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
                shouldReopenViewerMode = true
                onRequestNextSource?()
            },
            onRequestPreviousSource: {
                shouldReopenViewerMode = true
                onRequestPreviousSource?()
            },
            onRequestSourceJump: { steps in
                shouldReopenViewerMode = true
                onRequestSourceJump?(steps)
            }
        )
    }

    // MARK: - Thumbnail Browser

    @ViewBuilder
    private var thumbnailBrowserView: some View {
        thumbnailBrowserContent
            .overlay {
                if showBookmarkList {
                    BookmarkListOverlayView(
                        bookmarks: CacheManager.shared.getBookmarks(for: imageSource.url),
                        selectedCursor: bookmarkListCursor,
                        onSelect: { imageIndex in
                            showBookmarkList = false
                            focusedIndex = min(imageIndex, entries.count - 1)
                            Logger.folder.debug("Bookmark list click → jump to \(imageIndex, privacy: .public)")
                        },
                        onClose: { showBookmarkList = false }
                    )
                }
            }
            .onChange(of: shouldReopenSlideMode) { _, newValue in
                handleSlideModeReopen(newValue)
            }
            .onChange(of: previewMode) { oldMode, newMode in
                handlePreviewModeChange(oldMode: oldMode, newMode: newMode)
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
                if affectedFavoriteCount > 0 {
                    Text("\(pathsToRemoveForDelete.count) 件のファイルをゴミ箱に移動しますか？\n（⭐\(affectedFavoriteCount)件は保護されます）")
                } else {
                    Text("\(pathsToRemoveForDelete.count) 件のファイルをゴミ箱に移動しますか？")
                }
            }
            .sheet(isPresented: $showFavoriteExportConfirm) {
                ExportConfirmationView(
                    affectedFavoriteCount: affectedFavoriteCount,
                    selectionMode: settings.selectionMode,
                    options: $exportMetadataOptions,
                    onCancel: {
                        pendingExportType = nil
                        showFavoriteExportConfirm = false
                    },
                    onExport: {
                        showFavoriteExportConfirm = false
                        executePendingExport()
                    }
                )
            }
    }

    private var thumbnailBrowserContent: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            gridContentView
            if !selectedPaths.isEmpty {
                Divider()
                footerView
            }
        }
    }


    private func handleEntriesChange(_ newEntries: [ImageEntry]) {
        if shouldReopenViewerMode && !newEntries.isEmpty {
            let startIndex: Int
            if let lastIndex = CacheManager.shared.getLastPosition(for: imageSource.url) {
                startIndex = min(lastIndex, newEntries.count - 1)
            } else {
                startIndex = 0
            }
            previewMode = .viewer(index: startIndex)
            shouldReopenViewerMode = false
        } else if shouldReopenViewerMode && newEntries.isEmpty {
            // #131: Clear flag on empty source to avoid Color.black stuck
            shouldReopenViewerMode = false
        }
    }

    private func handleSlideModeReopen(_ newValue: Bool) {
        if newValue && !entries.isEmpty && !SlideWindowController.shared.isOpen {
            Logger.thumbnailGrid.debug("shouldReopenSlideMode triggered, opening Slide Mode")
            shouldReopenSlideMode = false
            let index = focusedIndex ?? 0
            previewMode = .slideMode(index: index)
        } else if newValue && entries.isEmpty {
            // #131: Clear flag on empty source
            shouldReopenSlideMode = false
        }
    }

    private func handlePreviewModeChange(oldMode: PreviewMode, newMode: PreviewMode) {
        Logger.thumbnailGrid.debug("previewMode changed: \(String(describing: oldMode), privacy: .public) → \(String(describing: newMode), privacy: .public)")
        
        if case .slideMode(let index) = newMode {
            Logger.thumbnailGrid.debug("Slide Mode requested at index \(index, privacy: .public)")
            let favIndices = favoriteIndices
            previewMode = .none
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                openSlideWindow(at: index, favoriteIndices: favIndices)
            }
        }
    }

    private func openSlideWindow(at index: Int, favoriteIndices favIndices: Set<Int>) {
        Logger.thumbnailGrid.debug("Opening SlideWindowController...")
        
        let positionInfo = SourceNavigator.positionInfo(for: imageSource.url)
        let sourceName = imageSource.url.lastPathComponent
        let selectedIndices = Set(entries.enumerated().compactMap { idx, entry in
            selectedPaths.contains(entry.path) ? idx : nil
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
                Logger.thumbnailGrid.info("SlideWindowController closed")
            },
            onIndexChange: { newIndex in
                focusedIndex = newIndex
                CacheManager.shared.setLastPosition(for: imageSource.url, index: newIndex)
            },
            onNextSource: onRequestNextSource,
            onPreviousSource: onRequestPreviousSource,
            onSourceJump: onRequestSourceJump,
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
            },
            onExitToViewerMode: {
                let currentIdx = SlideWindowController.shared.getCurrentIndex
                previewMode = .viewer(index: currentIdx)
            }
        )
    }

    // MARK: - Grid Content

    @ViewBuilder
    private var gridContentView: some View {
        ZStack {
            if isLoadingSource {
                if showLoadingSpinner {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("読み込み中…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if entries.isEmpty {
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
                                LazyVGrid(columns: columns, spacing: 8, pinnedViews: [.sectionHeaders]) {
                                    ForEach(gridSections) { section in
                                        Section {
                                            ForEach(section.items) { item in
                                                ThumbnailCell(
                                                    entry: item.entry,
                                                    thumbnail: thumbnails[item.entry.path],
                                                    isSelected: selectedPaths.contains(item.entry.path),
                                                    isFocused: focusedIndex == item.index,
                                                    favoriteStatus: getFavoriteStatus(item.entry),
                                                    selectionMode: settings.selectionMode,
                                                    size: settings.effectiveThumbnailSize,
                                                    showProtectedFeedback: protectedFeedbackPath == item.entry.path,
                                                    isLastViewed: item.index == lastViewedIndex  // #52
                                                )
                                                .id(item.index)
                                                .onTapGesture {
                                                    focusedIndex = item.index
                                                }
                                                .onAppear {
                                                    loadThumbnailIfNeeded(for: item.entry)
                                                }
                                            }
                                        } header: {
                                            if let bookmark = section.bookmark {
                                                BookmarkDividerView(
                                                    bookmark: bookmark,
                                                    sourceURL: imageSource.url,
                                                    isRTL: isRTL,
                                                    onNameChanged: { bookmarksVersion += 1 }
                                                )
                                            }
                                        }
                                    }
                                }
                                .padding()
                                .environment(\.layoutDirection, effectiveReadingDirection.layoutDirection) // #54
                            }
                            .onChange(of: focusedIndex) { _, newIndex in
                                if let index = newIndex {
                                    if isKeyRepeat {
                                        // #158: No animation during key repeat — immediate scroll
                                        scrollProxy.scrollTo(index, anchor: .center)
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            scrollProxy.scrollTo(index, anchor: .center)
                                        }
                                    }
                                }
                            }
                            // #193: Viewer Mode → Grid復帰時のスクロール復元
                            // GridはViewer Modeで置き換えられるため再マウントされる。
                            // focusedIndexは既に設定済みだが .onChange は値変化時のみ発火するので
                            // onAppearで明示的にスクロールする。
                            .onAppear {
                                if let index = focusedIndex {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        scrollProxy.scrollTo(index, anchor: .center)
                                    }
                                }
                            }
                        }
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
            
            // Key event handler — always present, survives branch switches
            KeyEventHandlerView { event in
                handleKeyEvent(event)
            }
            .allowsHitTesting(false)
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
                
                // #103: Select all favorites in keep mode
                if settings.selectionMode == .keep && !directFavoritePaths.isEmpty {
                    Button {
                        if directFavoritePaths.isSubset(of: selectedPaths) {
                            selectedPaths.subtract(directFavoritePaths)
                        } else {
                            selectedPaths.formUnion(directFavoritePaths)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: directFavoritePaths.isSubset(of: selectedPaths) ? "checkmark.square.fill" : "square")
                            Text("★をすべて選出")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.1))
                        .foregroundStyle(.orange)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("★付きアイテムをすべて選出に追加")
                }
                
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
                Menu {
                    Button("PNGとして出力...") {
                        confirmExportPNG()
                    }
                    Button("PNGで出力（ZIP）...") {
                        confirmExportPNGZip()
                    }
                } label: {
                    Text("確定 → _opt.pdf")
                } primaryAction: {
                    confirmExportPDF()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
    
    private var footerSummary: String {
        let keepCount = pathsToKeep.count
        let removeCount = pathsToRemove.count
        let favoriteCount = affectedFavoriteCount
        
        var summary = "出力: \(keepCount)件 / 除外: \(removeCount)件"
        if favoriteCount > 0 {
            summary += " (含★\(favoriteCount)件)"
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
    
    /// Paths that will be excluded/removed (#103: no favorite auto-protection for export)
    private var pathsToRemove: Set<String> {
        let allPaths = Set(entries.map { $0.path })
        switch settings.selectionMode {
        case .exclude:
            return selectedPaths
        case .keep:
            return allPaths.subtracting(selectedPaths)
        }
    }
    
    /// Paths that are directly favorited in this source (for delete protection)
    private var directFavoritePaths: Set<String> {
        Set(entries.filter { isDirectFavorite($0) }.map { $0.path })
    }
    
    /// Paths to remove for delete operations (favorites protected) (#103)
    private var pathsToRemoveForDelete: Set<String> {
        pathsToRemove.subtracting(directFavoritePaths)
    }
    
    /// Count of direct favorites in the removal set (#103)
    private var affectedFavoriteCount: Int {
        pathsToRemove.intersection(directFavoritePaths).count
    }
    
    // MARK: - Data Loading
    
    private func loadSource() {
        SourceSwitchTiming.mark("load.start")
        // #134 P8: Cancel all pending thumbnail operations on source switch.
        // Prevents stale work from consuming thread pool for the old source.
        thumbnailQueue.cancelAllOperations()
        pendingOperations.removeAll()
        thumbnailCoalescer.clear()
        // Generate new load ID to invalidate any pending async operations
        let newLoadID = UUID()
        loadID = newLoadID
        currentSourceURL = imageSource.url
        
        // Clear UI state immediately on main thread
        thumbnails = [:]
        contentHashes = [:]
        selectedPaths = []
        focusedIndex = nil
        previewMode = .none
        entries = []
        isLoadingSource = true
        showLoadingSpinner = false
        
        Logger.thumbnailGrid.debug("loadSource: shouldReopenViewerMode=\(shouldReopenViewerMode), previewMode=\(String(describing: previewMode))")
        // S050: Try prefetched entries first (NO timer needed)
        if let prefetched = consumePrefetchedEntries?() {
            SourceSwitchTiming.mark("prefetch.hit")
            
            entries = prefetched
            isLoadingSource = false
            
            SourceSwitchTiming.end("load.done(prefetch)")
            
            if !entries.isEmpty {
                focusedIndex = 0
            }
            
            // #122: Restore Viewer Mode immediately in same synchronous block
            // Avoids 1+ frame gap via onChange(of: entries) → handleEntriesChange
            if shouldReopenViewerMode && !entries.isEmpty {
                let startIndex: Int
                if let lastIndex = CacheManager.shared.getLastPosition(for: imageSource.url) {
                    startIndex = min(lastIndex, entries.count - 1)
                } else {
                    startIndex = 0
                }
                previewMode = .viewer(index: startIndex)
                shouldReopenViewerMode = false
            } else if shouldReopenViewerMode && entries.isEmpty {
                // #131: Clear flag on empty source to avoid Color.black stuck
                shouldReopenViewerMode = false
            }
            
            if shouldReopenSlideMode {
                // #131: Update Slide Mode even for empty entries (shows emptySourceView)
                shouldReopenSlideMode = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    reopenSlideModeAfterSwitch()
                }
            }
            return
        }
        Logger.thumbnailGrid.debug("loadSource: prefetch MISS — consumePrefetchedEntries returned nil")
        
        // S050: Prefetch not ready — fallback to async load
        SourceSwitchTiming.mark("prefetch.miss")
        
        // Show spinner only if async load takes >100ms
        let spinnerTimer = DispatchWorkItem {
            guard loadID == newLoadID, isLoadingSource else { return }
            showLoadingSpinner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: spinnerTimer)
        
        // Capture source reference for background work
        let source = imageSource

        // Run listImageEntries off main thread (#91)
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedEntries = source.listImageEntries()
            
            DispatchQueue.main.async {
                spinnerTimer.cancel()
                // Stale check: discard if source changed during loading
                guard loadID == newLoadID else { return }
                
                entries = loadedEntries
                isLoadingSource = false
                showLoadingSpinner = false
                
                SourceSwitchTiming.end("load.done")
                
                if !entries.isEmpty {
                    focusedIndex = 0
                }
                
                // S005: Reopen Slide Mode if flag is set
                // #131: Update even for empty entries (shows emptySourceView)
                if shouldReopenSlideMode {
                    shouldReopenSlideMode = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        reopenSlideModeAfterSwitch()
                    }
                }
                
                // #131: Clear Viewer Mode flag on empty source
                if shouldReopenViewerMode && entries.isEmpty {
                    shouldReopenViewerMode = false
                }
            }
        }
    }
   
    
    // S050: Extracted from loadSource() — reopen Slide Mode after source switch
    private func reopenSlideModeAfterSwitch() {
            let favIndices = favoriteIndices
            let positionInfo = SourceNavigator.positionInfo(for: imageSource.url)
            let sourceName = imageSource.url.lastPathComponent
            let selectedIndices: Set<Int> = []
            
            SlideWindowController.shared.updateSource(
                imageSource: imageSource,
                entries: entries,
                favoriteIndices: favIndices,
                selectedIndices: selectedIndices,
                sourceName: sourceName,
                sourcePosition: positionInfo?.position ?? 0,
                totalSources: positionInfo?.total ?? 0,
                onClose: {
                    Logger.thumbnailGrid.info("SlideWindowController closed (after source switch)")
                },
                onIndexChange: { newIndex in
                    focusedIndex = newIndex
                    CacheManager.shared.setLastPosition(for: imageSource.url, index: newIndex)
                },
                onNextSource: onRequestNextSource,
                onPreviousSource: onRequestPreviousSource,
                onSourceJump: onRequestSourceJump,
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
    
    private func loadThumbnailIfNeeded(for entry: ImageEntry) {
        // CRITICAL: Check if this call is from a stale View instance
        // SwiftUI may trigger onAppear from old View instances with old imageSource
        guard imageSource.url == currentSourceURL else {
            Logger.thumbnailGrid.debug("SKIP stale View call: \(entry.name) (imageSource: \(imageSource.url.lastPathComponent), current: \(currentSourceURL?.lastPathComponent ?? "nil"))")
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
        if imageSource is FolderManager {
            fullPath = entry.path  // FolderManager already has full path
        } else {
            // ArchiveManager and PDFManager both use url.path + "/" + entry.path
            fullPath = imageSource.url.path + "/" + entry.path
        }
        
        // #134 P1: Synchronous memory cache check — avoid async dispatch + ProgressView flash
        let cache = CacheManager.shared
        let pathHash = cache.pathHash(for: fullPath)
        if let contentHash = cache.getContentHash(for: pathHash),
           let cached = cache.getThumbnailFromMemory(for: contentHash) {
            thumbnails[entryPath] = cached
            // #134 P4: Reuse already-resolved contentHash (was calling getContentHashForPath → redundant SHA256)
            contentHashes[entryPath] = contentHash
            Logger.thumbnailGrid.debug("★PERF★ SYNC memory hit: \(entryName)")
            return
        }
        
        Logger.thumbnailGrid.debug("Starting for \(entryName) from \(capturedSourceURL.lastPathComponent), loadID: \(capturedLoadID, privacy: .public)")
        
        let tDispatch = CFAbsoluteTimeGetCurrent()
                
                // #134 P8: Cancel any duplicate pending operation for same entry
                if let existing = pendingOperations[entryPath] {
                    existing.cancel()
                    pendingOperations.removeValue(forKey: entryPath)
                }
                
                let operation = BlockOperation()
                weak var weakOp = operation
                
                operation.addExecutionBlock { [self] in
                    guard let op = weakOp, !op.isCancelled else { return }
                    
                    let tBgStart = CFAbsoluteTimeGetCurrent()
                    let dispatchLatencyMs = (tBgStart - tDispatch) * 1000
                    
                    // #134 P2: No main.sync validity check (priority inversion removed in S054).
                    
                    let tGenStart = CFAbsoluteTimeGetCurrent()
                    
                    guard !op.isCancelled else { return }
                    
                    // Generate thumbnail
                    guard let thumbnail = currentSource.thumbnail(for: entry, maxSize: maxSize) else {
                        Logger.thumbnailGrid.error("Failed for: \(entryName) from \(capturedSourceURL.lastPathComponent)")
                        return
                    }
                    
                    
                    // #144: Cache aspect ratio for spread detection
                    CacheManager.shared.setAspectRatio(for: capturedSourceURL, path: entryPath, ratio: thumbnail.size.width / thumbnail.size.height)
                    
                    guard !op.isCancelled else { return }
                    
                    let tGenEnd = CFAbsoluteTimeGetCurrent()
                    let genMs = (tGenEnd - tGenStart) * 1000
                    
                    // Get content hash from CacheManager (registered during thumbnail generation)
                    let contentHash = CacheManager.shared.getContentHashForPath(fullPath)
                    
                    DispatchQueue.main.async {
                        let tMainStart = CFAbsoluteTimeGetCurrent()
                        
                        // Validate before buffering (lightweight checks on background thread)
                        guard capturedLoadID == self.loadID else {
                            Logger.thumbnailGrid.debug("Discarding stale thumbnail: \(entryName) (loadID mismatch)")
                            return
                        }

                        // Buffer for coalesced flush
                        let needsSchedule = self.thumbnailCoalescer.append((path: entryPath, image: thumbnail, contentHash: contentHash))

                        if needsSchedule {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                                self.flushThumbnailBuffer()
                            }
                        }

                        let tBuffered = CFAbsoluteTimeGetCurrent()
                        let mainDispatchMs = (tBuffered - tGenEnd) * 1000
                        let totalMs = (tBuffered - tDispatch) * 1000
                        Logger.thumbnailGrid.info("★PERF★ \(entryName): dispatch=\(String(format: "%.1f", dispatchLatencyMs))ms gen=\(String(format: "%.1f", genMs))ms buffered=\(String(format: "%.1f", mainDispatchMs))ms TOTAL=\(String(format: "%.1f", totalMs))ms")
                    }
                }
                
                pendingOperations[entryPath] = operation
                thumbnailQueue.addOperation(operation)    }
    
    private func flushThumbnailBuffer() {
        let batch = thumbnailCoalescer.flush()
        guard !batch.isEmpty else { return }
        
        var assignedCount = 0
        for item in batch {
            guard entries.contains(where: { $0.path == item.path }) else { continue }
            thumbnails[item.path] = item.image
            if let hash = item.contentHash {
                contentHashes[item.path] = hash
            }
            pendingOperations.removeValue(forKey: item.path)
            assignedCount += 1
        }
        
        Logger.thumbnailGrid.info("★PERF★ FLUSH: \(assignedCount)/\(batch.count) thumbnails assigned in single body evaluation")
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
        // #158: Track key repeat for scroll animation control
        isKeyRepeat = event.isARepeat
        
        // #62 Phase 5: Delegate keys to bookmark list overlay when showing
        if showBookmarkList {
            let bookmarks = CacheManager.shared.getBookmarks(for: imageSource.url)
            let action = BookmarkListKeyHandler.handle(event: event, bookmarks: bookmarks, cursor: bookmarkListCursor)
            switch action {
            case .moveCursor(let newCursor):
                bookmarkListCursor = newCursor
            case .selectAndClose(let imageIndex):
                showBookmarkList = false
                focusedIndex = min(imageIndex, entries.count - 1)
                Logger.folder.debug("Bookmark list → jump to \(imageIndex, privacy: .public)")
            case .close:
                showBookmarkList = false
            case .consumed:
                break
            }
            return true
        }
        
        // Source navigation works even with empty entries
        if let chars = event.charactersIgnoringModifiers?.lowercased() {
            let hasControl = event.modifierFlags.contains(.control)
            if hasControl {
                switch chars {
                case "w":
                    onRequestPreviousSource?()
                    return true
                case "s":
                    onRequestNextSource?()
                    return true
                default:
                    break
                }
            }
        }
        let hasControlArrow = event.modifierFlags.contains(.control)
        if hasControlArrow {
            switch event.keyCode {
            case 123, 126: // Left/Up arrow + Ctrl
                onRequestPreviousSource?()
                return true
            case 124, 125: // Right/Down arrow + Ctrl
                onRequestNextSource?()
                return true
            default:
                break
            }
        }
        
        // #131: Allow Viewer/Slide Mode entry on empty source (show feedback)
        if entries.isEmpty {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "r" where !event.modifierFlags.contains(.control):
                    previewMode = .viewer(index: 0)
                    return true
                case "f" where event.modifierFlags.contains(.control):
                    previewMode = .slideMode(index: 0)
                    return true
                default:
                    break
                }
            }
            if event.keyCode == 36 { // Enter
                previewMode = .slideMode(index: 0)
                return true
            }
            return false
        }
        
        // Initialize focus if not set
        if focusedIndex == nil {
            focusedIndex = 0
            return true
        }
        
        guard let currentIndex = focusedIndex else { return false }
        
        // Check for special keys
        switch event.keyCode {
        // Arrow keys
        case 123: // Left arrow - #72: RTL-aware
            moveFocus(by: isRTL ? 1 : -1)
            return true
        case 124: // Right arrow - #72: RTL-aware
            moveFocus(by: isRTL ? -1 : 1)
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
            
        default:
            break
        }
        
        // Check for character keys
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        
        // #169: Grid-specific pre-parser handling
        // W/S without modifiers = vertical (column-based) navigation — bypass CommonKeyParser
        if characters == "w" && !event.modifierFlags.contains(.control) {
            moveFocus(by: -columnCount)
            return true
        }
        if characters == "s"
            && !event.modifierFlags.contains(.control)
            && !event.modifierFlags.contains(.shift) {
            moveFocus(by: columnCount)
            return true
        }
        // b without Shift: consume silently (preserve existing behavior)
        if characters == "b" && !event.modifierFlags.contains(.shift) {
            return true
        }
        
        // Route remaining character keys through CommonKeyParser
        guard let action = CommonKeyParser.parseNavigationKey(event) else {
            return false
        }
        return executeGridAction(action, currentIndex: currentIndex)
    }
    
    /// Dispatch a parsed KeyAction in Grid View context (#169)
    /// Called from handleKeyEvent after CommonKeyParser recognition.
    @discardableResult
    private func executeGridAction(_ action: KeyAction, currentIndex: Int) -> Bool {
        switch action {
        
        case .navigate(let direction):
            // Horizontal navigation (A/D): RTL-aware, step by 1
            moveFocus(by: direction == .forward ? (isRTL ? -1 : 1) : (isRTL ? 1 : -1))
            
        case .navigateNStep(let direction):
            // Ctrl+Opt+A/D: N-step navigation (RTL-aware)
            let step = AppSettings.shared.navigationStepCount
            moveFocus(by: direction == .forward ? (isRTL ? -step : step) : (isRTL ? step : -step))
            
        case .jumpToStart:
            let target = isRTL ? entries.count - 1 : 0
            focusedIndex = target
            Logger.folder.debug("Ctrl+A → \(isRTL ? "end" : "start")")
            
        case .jumpToEnd:
            let target = isRTL ? 0 : entries.count - 1
            focusedIndex = target
            Logger.folder.debug("Ctrl+D → \(isRTL ? "start" : "end")")
            
        case .jumpToPercent(let keyNum):
            // Cmd+1–5: RTL-aware percent jump
            let ltrPercents = [1: 0, 2: 25, 3: 50, 4: 75, 5: 100]
            let ltrPercent = ltrPercents[keyNum] ?? 50
            let percent = (isRTL && ltrPercent != 50) ? 100 - ltrPercent : ltrPercent
            focusedIndex = NavigationHelper.indexForPercent(percent, totalCount: entries.count)
            Logger.folder.debug("Cmd+\(keyNum) → \(percent, privacy: .public)%")
            
        case .navigateBookmark(let direction):
            // Shift+A/D: navigate to previous/next bookmark (RTL-aware)
            if let target = NavigationHelper.navigateBookmark(
                direction: direction, from: currentIndex,
                sourceURL: imageSource.url, isRTL: isRTL,
                wrap: settings.loopWithinSource
            ) {
                focusedIndex = target
                Logger.folder.debug("Shift+\(direction == .backward ? "A" : "D") → bookmark at \(target, privacy: .public)")
            }
            
        case .addOrDeleteBookmark:
            // Shift+S: add or delete bookmark at current position
            let entry = entries[currentIndex]
            let defaultName = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
            BookmarkDialogHelper.handleShiftS(
                sourceURL: imageSource.url,
                imageIndex: currentIndex,
                defaultName: defaultName,
                window: NSApp.keyWindow,
                onChanged: { bookmarksVersion += 1 }
            )
            
        case .showBookmarkList:
            // Shift+B: show bookmark list overlay
            let bookmarks = CacheManager.shared.getBookmarks(for: imageSource.url)
            showBookmarkList = true
            if let nearest = bookmarks.enumerated().min(by: {
                abs($0.element.imageIndex - currentIndex) < abs($1.element.imageIndex - currentIndex)
            }) {
                bookmarkListCursor = nearest.offset
            } else {
                bookmarkListCursor = 0
            }
            Logger.folder.debug("Shift+B → bookmark list (\(bookmarks.count, privacy: .public) bookmarks)")
            
        case .toggleFavorite:
            // F: toggle favorite for focused item
            guard currentIndex < entries.count else { return true }
            let favEntry = entries[currentIndex]
            let hash = contentHashes[favEntry.path]
            _ = CacheManager.shared.toggleFavorite(
                sourceURL: imageSource.url,
                entryPath: favEntry.path,
                contentHash: hash
            )
            favoritesVersion += 1
            
        case .enterSlideMode:
            // Ctrl+F: open Slide Mode from current index
            previewMode = .slideMode(index: currentIndex)
            
        case .exitToFiler:
            // R: in Grid context, open Viewer Mode (R = "read" = enter viewer)
            previewMode = .viewer(index: currentIndex)
            
        case .toggleReadingDirection:
            // Ctrl+R: toggle reading direction
            let newDirection = CacheManager.shared.toggleReadingDirection(for: imageSource.url)
            readingDirectionVersion += 1
            Logger.folder.debug("Reading direction toggled to: \(newDirection.displayName, privacy: .public)")
            
        case .toggleSelection:
            // X: toggle selection for focused item
            let selEntry = entries[currentIndex]
            toggleSelection(selEntry)
            
        case .toggleSinglePageMarker:
            // V: toggle single page marker
            let added = CacheManager.shared.toggleSinglePageMarker(for: imageSource.url, at: currentIndex)
            Logger.thumbnailGrid.debug("Single page marker at \(currentIndex, privacy: .public): \(added ? "ON" : "OFF")")
            
        case .selectAll:
            // Cmd+A: select all / deselect all (toggle)
            if selectedPaths.count == entries.count {
                selectedPaths.removeAll()
            } else {
                selectedPaths = Set(entries.map { $0.path })
            }
            
        case .navigateFavorite(let direction):
            // Z/C: navigate favorites (RTL-aware)
            let targetIndex = direction == .backward
                ? (isRTL
                    ? NavigationHelper.nextFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: settings.loopWithinSource)
                    : NavigationHelper.previousFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: settings.loopWithinSource))
                : (isRTL
                    ? NavigationHelper.previousFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: settings.loopWithinSource)
                    : NavigationHelper.nextFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: settings.loopWithinSource))
            if let target = targetIndex {
                focusedIndex = target
                Logger.folder.debug("\(direction == .backward ? "Z" : "C") → favorite at \(target, privacy: .public)")
            }
            
        case .jumpToFavoriteEdge(let direction):
            // Ctrl+Z/C: jump to first/last favorite (RTL-aware)
            let adjusted = NavigationHelper.adjustForRTL(direction, isRTL: isRTL)
            let targetFav = adjusted == .backward ? favoriteIndices.min() : favoriteIndices.max()
            if let fav = targetFav {
                focusedIndex = fav
                Logger.folder.debug("Ctrl+\(direction == .backward ? "Z" : "C") → \(adjusted == .backward ? "first" : "last", privacy: .public) favorite at \(fav, privacy: .public)")
            }
            
        case .navigateFavoriteNStep(let direction):
            // Ctrl+Option+Z/C: N-step favorite navigation
            if let target = NavigationHelper.navigateFavoriteNStep(
                direction: direction, from: currentIndex,
                favoriteIndices: favoriteIndices,
                stepCount: AppSettings.shared.navigationStepCount,
                isRTL: isRTL
            ) {
                focusedIndex = target
            }
            
        default:
            return false
        }
        return true
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
    
    /// #62: Build grid sections divided by bookmarks
    private var gridSections: [GridSection] {
        // Reference bookmarksVersion to trigger re-render
        _ = bookmarksVersion
        
        let bookmarks = CacheManager.shared.getBookmarks(for: imageSource.url)
        guard !entries.isEmpty else { return [] }
        
        // No bookmarks: single section with all entries
        if bookmarks.isEmpty {
            return [GridSection(
                id: "section-all",
                bookmark: nil,
                items: entries.enumerated().map { GridSection.GridEntry(index: $0, entry: $1) }
            )]
        }
        
        // Get valid breakpoints sorted by imageIndex
        let sortedBookmarks = bookmarks.filter { $0.imageIndex >= 0 && $0.imageIndex < entries.count }
            .sorted { $0.imageIndex < $1.imageIndex }
        let breakpoints = sortedBookmarks.map { $0.imageIndex }
        
        // If no valid breakpoints, single section
        if breakpoints.isEmpty {
            return [GridSection(
                id: "section-all",
                bookmark: nil,
                items: entries.enumerated().map { GridSection.GridEntry(index: $0, entry: $1) }
            )]
        }
        
        // Build section ranges
        var sections: [GridSection] = []
        
        // Entries before first bookmark (no header)
        if let firstBreak = breakpoints.first, firstBreak > 0 {
            let items = (0..<firstBreak).map { GridSection.GridEntry(index: $0, entry: entries[$0]) }
            sections.append(GridSection(id: "section-pre", bookmark: nil, items: items))
        }
        
        // Each bookmark starts a section
        for (i, bookmark) in sortedBookmarks.enumerated() {
            let start = bookmark.imageIndex
            let end = i + 1 < sortedBookmarks.count ? sortedBookmarks[i + 1].imageIndex : entries.count
            if start < end {
                let items = (start..<end).map { GridSection.GridEntry(index: $0, entry: entries[$0]) }
                sections.append(GridSection(id: "section-\(bookmark.id)", bookmark: bookmark, items: items))
            }
        }
        
        return sections
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
    
    // MARK: - Archive Export
    
    private func confirmExportArchive() {
        exportMetadataOptions = settings.defaultMetadataOptions
        pendingExportType = .archive
        showFavoriteExportConfirm = true
    }
    
    private func executeExportArchive() {
        guard let archiveManager = imageSource as? ArchiveManager else { return }
        
        // #163: Block export when all items are excluded
        if pathsToKeep.isEmpty {
            exportMessage = "出力するファイルがありません（すべて除外されています）"
            showExportError = true
            return
        }
        
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
        
        // #161: Block if destination already exists
        if let reason = ExportUtilities.guardDestination(outputURL) {
            exportMessage = reason
            showExportError = true
            return
        }
        
        do {
            try archiveManager.exportOptimized(excluding: pathsToRemove, to: outputURL)
            // #105: Copy metadata to exported file
            CacheManager.shared.copyMetadata(
                from: archiveManager.url, to: outputURL,
                entries: entries, pathsToRemove: pathsToRemove,
                contentHashes: contentHashes,
                options: exportMetadataOptions
            )
            exportMessage = "\(outputURL.lastPathComponent) を作成しました\n含む: \(pathsToKeep.count) ファイル / 除外: \(pathsToRemove.count) ファイル"
            showExportSuccess = true
            selectedPaths.removeAll()  // Clear selections after success
            onExportSuccess?()
        } catch {
            Logger.thumbnailGrid.error("Export error: \(error, privacy: .public)")
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }
    
    // MARK: - Folder Operations
    
    private func confirmCreateZip() {
        // #105: Initialize metadata options from settings
        exportMetadataOptions = settings.defaultMetadataOptions
        // #103: Show confirmation if favorites would be excluded
        if affectedFavoriteCount > 0 {
            pendingExportType = .folderZip
            showFavoriteExportConfirm = true
            return
        }
        executeCreateZip()
    }
    
    private func executeCreateZip() {
        guard let folderManager = imageSource as? FolderManager else { return }
        
        // #163: Block export when all items are excluded
        if pathsToKeep.isEmpty {
            exportMessage = "出力するファイルがありません（すべて除外されています）"
            showExportError = true
            return
        }
        
        let outputName = "\(folderManager.displayName).zip"
        
        let savePanel = NSSavePanel()
        savePanel.title = "ZIPファイルの保存先"
        savePanel.nameFieldStringValue = outputName
        savePanel.allowedContentTypes = [.zip]
        savePanel.directoryURL = settings.outputDirectory(for: folderManager.url)
        
        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return
        }
        
        // #161: Block if destination already exists
        if let reason = ExportUtilities.guardDestination(outputURL) {
            exportMessage = reason
            showExportError = true
            return
        }
        
        do {
            try folderManager.createZip(excluding: pathsToRemove, to: outputURL)
            // #105: Copy metadata to exported file
            CacheManager.shared.copyMetadata(
                from: folderManager.url, to: outputURL,
                entries: entries, pathsToRemove: pathsToRemove,
                contentHashes: contentHashes,
                options: exportMetadataOptions
            )
            exportMessage = "\(outputURL.lastPathComponent) を作成しました\n含む: \(pathsToKeep.count) ファイル"
            showExportSuccess = true
            selectedPaths.removeAll()  // Clear selections after success
            onExportSuccess?()
        } catch {
            Logger.thumbnailGrid.error("ZIP creation error: \(error, privacy: .public)")
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }
    
    private func performDelete() {
        guard let folderManager = imageSource as? FolderManager else { return }
        
        do {
            let count = try folderManager.moveToTrash(paths: pathsToRemoveForDelete)
            exportMessage = "\(count) 件のファイルをゴミ箱に移動しました"
            showExportSuccess = true
            selectedPaths.removeAll()  // Clear selections after success
            loadSource()  // Refresh the list
            onExportSuccess?()
        } catch {
            Logger.thumbnailGrid.error("Delete error: \(error, privacy: .public)")
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }
    
    // MARK: - PDF Export (#100)
    
    private func confirmExportPDF() {
        exportMetadataOptions = settings.defaultMetadataOptions
        pendingExportType = .pdf
        showFavoriteExportConfirm = true
    }
    
    private func executeExportPDF() {
        guard let pdfManager = imageSource as? PDFManager else { return }
        
        // #163: Block export when all pages are excluded
        if pathsToKeep.isEmpty {
            exportMessage = "出力するページがありません（すべて除外されています）"
            showExportError = true
            return
        }
        
        let originalName = pdfManager.url.deletingPathExtension().lastPathComponent
        let outputName = "\(originalName)_opt.pdf"
        
        let savePanel = NSSavePanel()
        savePanel.title = "最適化PDFの保存先"
        savePanel.nameFieldStringValue = outputName
        savePanel.allowedContentTypes = [.pdf]
        savePanel.directoryURL = settings.outputDirectory(for: pdfManager.url)
        
        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return
        }
        
        // #161: Block if destination already exists
        if let reason = ExportUtilities.guardDestination(outputURL) {
            exportMessage = reason
            showExportError = true
            return
        }
        
        do {
            try pdfManager.exportOptimizedPDF(excluding: pathsToRemove, to: outputURL)
            // #105: Copy metadata with PDF page index remapping
            let pathRemapper = entries.first.map { CacheManager.pdfEntryPathRemapper(samplePath: $0.path) }
            CacheManager.shared.copyMetadata(
                from: pdfManager.url, to: outputURL,
                entries: entries, pathsToRemove: pathsToRemove,
                contentHashes: contentHashes,
                newPathForSurvivingIndex: pathRemapper,
                options: exportMetadataOptions
            )
            exportMessage = "\(outputURL.lastPathComponent) を作成しました\n含む: \(pathsToKeep.count) ページ / 除外: \(pathsToRemove.count) ページ"
            showExportSuccess = true
            selectedPaths.removeAll()
            onExportSuccess?()
        } catch {
            Logger.thumbnailGrid.error("PDF export error: \(error, privacy: .public)")
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }
    
    private func confirmExportPNG() {
        exportMetadataOptions = settings.defaultMetadataOptions
        pendingExportType = .png
        showFavoriteExportConfirm = true
    }
    
    private func executeExportPNG() {
        guard let pdfManager = imageSource as? PDFManager else { return }
        
        // #163: Block export when all pages are excluded
        if pathsToKeep.isEmpty {
            exportMessage = "出力するページがありません（すべて除外されています）"
            showExportError = true
            return
        }
        
        let openPanel = NSOpenPanel()
        openPanel.title = "PNG出力先フォルダを選択"
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.directoryURL = settings.outputDirectory(for: pdfManager.url)
        
        guard openPanel.runModal() == .OK, let outputDir = openPanel.url else {
            return
        }
        
        do {
            let count = try pdfManager.exportPagesAsPNG(excluding: pathsToRemove, to: outputDir)
            let folderName = "\(pdfManager.url.deletingPathExtension().lastPathComponent)_pages"
            // #100: Metadata carry-over — remap PDF page paths to PNG filenames in folder
            let folderURL = outputDir.appendingPathComponent(folderName, isDirectory: true)
            let pathRemapper: (Int, String) -> String = { _, originalPath in
                originalPath + ".png"
            }
            CacheManager.shared.copyMetadata(
                from: pdfManager.url, to: folderURL,
                entries: entries, pathsToRemove: pathsToRemove,
                contentHashes: contentHashes,
                newPathForSurvivingIndex: pathRemapper,
                options: exportMetadataOptions
            )
            exportMessage = "\(folderName)/ に \(count) ページを出力しました"
            showExportSuccess = true
            selectedPaths.removeAll()
            onExportSuccess?()
        } catch {
            Logger.thumbnailGrid.error("PNG export error: \(error, privacy: .public)")
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }
    
    // MARK: - Deferred Export Execution (#103)
    
    private func confirmExportPNGZip() {
        exportMetadataOptions = settings.defaultMetadataOptions
        pendingExportType = .pngZip
        showFavoriteExportConfirm = true
    }
    
    private func executeExportPNGZip() {
        guard let pdfManager = imageSource as? PDFManager else { return }
        
        // #163: Block export when all pages are excluded
        if pathsToKeep.isEmpty {
            exportMessage = "出力するページがありません（すべて除外されています）"
            showExportError = true
            return
        }
        
        let originalName = pdfManager.url.deletingPathExtension().lastPathComponent
        let outputName = "\(originalName)_png.zip"
        
        let savePanel = NSSavePanel()
        savePanel.title = "PNG ZIP の保存先"
        savePanel.nameFieldStringValue = outputName
        savePanel.allowedContentTypes = [.zip]
        savePanel.directoryURL = settings.outputDirectory(for: pdfManager.url)
        
        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return
        }
        
        // #161: Block if destination already exists
        if let reason = ExportUtilities.guardDestination(outputURL) {
            exportMessage = reason
            showExportError = true
            return
        }
        
        do {
            let count = try pdfManager.exportPagesAsPNGZip(excluding: pathsToRemove, to: outputURL)
            // #100: Metadata carry-over — remap PDF page paths to PNG filenames in ZIP
            let pathRemapper: (Int, String) -> String = { _, originalPath in
                originalPath + ".png"
            }
            CacheManager.shared.copyMetadata(
                from: pdfManager.url, to: outputURL,
                entries: entries, pathsToRemove: pathsToRemove,
                contentHashes: contentHashes,
                newPathForSurvivingIndex: pathRemapper,
                options: exportMetadataOptions
            )
            exportMessage = "\(outputURL.lastPathComponent) を作成しました\n含む: \(count) ページ"
            showExportSuccess = true
            selectedPaths.removeAll()
            onExportSuccess?()
        } catch {
            Logger.thumbnailGrid.error("PNG ZIP export error: \(error, privacy: .public)")
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }
    
    private func executePendingExport() {
        guard let exportType = pendingExportType else { return }
        pendingExportType = nil
        switch exportType {
        case .archive: executeExportArchive()
        case .folderZip: executeCreateZip()
        case .pdf: executeExportPDF()
        case .png: executeExportPNG()
        case .pngZip: executeExportPNGZip()
        }
    }
}

#Preview {
    ThumbnailGridView(
        imageSource: ArchiveManager(zipURL: URL(fileURLWithPath: "/tmp/test.zip")),
        selectedPaths: .constant([]),
        onExportSuccess: nil,
        shouldReopenSlideMode: .constant(false),
        shouldReopenViewerMode: .constant(false),
        isInViewerMode: .constant(false),
        consumePrefetchedEntries: nil
    )
}
