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
            .sheet(isPresented: Binding(
                get: { previewMode.isQuickLook },
                set: { if !$0 { previewMode = .none } }
            )) {
                quickLookSheet
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

    @ViewBuilder
    private var quickLookSheet: some View {
        if let index = previewMode.index {
            ImagePreviewView(
                imageSource: imageSource,
                entries: entries,
                initialIndex: index,
                favoriteIndices: favoriteIndices,
                onClose: { previewMode = .none },
                onToggleFullScreen: {
                    Logger.thumbnailGrid.debug("onToggleFullScreen called")
                    Logger.thumbnailGrid.debug("Current previewMode: \(String(describing: previewMode), privacy: .public)")
                    if let idx = previewMode.index {
                        Logger.thumbnailGrid.debug("Setting previewMode to .slideMode(index: \(idx, privacy: .public))")
                        previewMode = .slideMode(index: idx)
                    } else {
                        Logger.thumbnailGrid.error("ERROR: previewMode.index is nil")
                    }
                }
            )
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
                                                    toggleSelection(item.entry)
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
            guard isLoadingSource else { return }
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
        // A - previous image (RTL-aware), Ctrl+A - jump to start/end, #62: Shift+A - prev bookmark
        case "a":
            if event.modifierFlags.contains(.shift) {
                // #62: Shift+A = previous bookmark (RTL-aware)
                if let target = NavigationHelper.navigateBookmark(
                    direction: .backward, from: currentIndex,
                    sourceURL: imageSource.url, isRTL: isRTL,
                    wrap: settings.loopWithinSource
                ) {
                    focusedIndex = target
                    Logger.folder.debug("Shift+A → bookmark at \(target, privacy: .public)")
                }
            } else if event.modifierFlags.contains(.control) {
                // #72: Ctrl+A = jump to start (RTL: end)
                let target = isRTL ? entries.count - 1 : 0
                focusedIndex = target
                Logger.folder.debug("Ctrl+A → \(isRTL ? "end" : "start")")
            } else {
                moveFocus(by: isRTL ? 1 : -1)  // #72: RTL-aware
            }
            return true

        // D - next image (RTL-aware), Ctrl+D - jump to end/start, #62: Shift+D - next bookmark
        case "d":
            if event.modifierFlags.contains(.shift) {
                // #62: Shift+D = next bookmark (RTL-aware)
                if let target = NavigationHelper.navigateBookmark(
                    direction: .forward, from: currentIndex,
                    sourceURL: imageSource.url, isRTL: isRTL,
                    wrap: settings.loopWithinSource
                ) {
                    focusedIndex = target
                    Logger.folder.debug("Shift+D → bookmark at \(target, privacy: .public)")
                }
            } else if event.modifierFlags.contains(.control) {
                // #72: Ctrl+D = jump to end (RTL: start)
                let target = isRTL ? 0 : entries.count - 1
                focusedIndex = target
                Logger.folder.debug("Ctrl+D → \(isRTL ? "start" : "end")")
            } else {
                moveFocus(by: isRTL ? -1 : 1)  // #72: RTL-aware
            }
            return true
        // S017: W - row up (Ctrl+W handled by early source navigation)
        case "w":
            moveFocus(by: -columnCount)
            return true
        // S017: S - row down (Ctrl+S handled by early source navigation), #62: Shift+S - bookmark
        case "s":
            if event.modifierFlags.contains(.shift) {
                // #62: Shift+S = add/delete bookmark at current position
                let entry = entries[currentIndex]
                let defaultName = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
                BookmarkDialogHelper.handleShiftS(
                    sourceURL: imageSource.url,
                    imageIndex: currentIndex,
                    defaultName: defaultName,
                    window: NSApp.keyWindow,
                    onChanged: { bookmarksVersion += 1 }
                )
            } else {
                moveFocus(by: columnCount)
            }
            return true
        
        // #62 Phase 5: Shift+B = toggle bookmark list overlay
        case "b":
            if event.modifierFlags.contains(.shift) {
                let bookmarks = CacheManager.shared.getBookmarks(for: imageSource.url)
                showBookmarkList = true
                // Set cursor to nearest bookmark to current position
                if let nearest = bookmarks.enumerated().min(by: {
                    abs($0.element.imageIndex - currentIndex) < abs($1.element.imageIndex - currentIndex)
                }) {
                    bookmarkListCursor = nearest.offset
                } else {
                    bookmarkListCursor = 0
                }
                Logger.folder.debug("Shift+B → bookmark list (\(bookmarks.count, privacy: .public) bookmarks)")
            }
            return true
        
        // #72: Cmd+1-5 = jump to percentage position (RTL-aware, Cmd to avoid system shortcut conflict)
        case "1":
            if event.modifierFlags.contains(.command) {
                let percent = isRTL ? 100 : 0
                focusedIndex = NavigationHelper.indexForPercent(percent, totalCount: entries.count)
                Logger.folder.debug("Cmd+1 → \(percent, privacy: .public)%")
                return true
            }
            return false
        case "2":
            if event.modifierFlags.contains(.command) {
                let percent = isRTL ? 75 : 25
                focusedIndex = NavigationHelper.indexForPercent(percent, totalCount: entries.count)
                Logger.folder.debug("Cmd+2 → \(percent, privacy: .public)%")
                return true
            }
            return false
        case "3":
            if event.modifierFlags.contains(.command) {
                focusedIndex = NavigationHelper.indexForPercent(50, totalCount: entries.count)
                Logger.folder.debug("Cmd+3 → 50%")
                return true
            }
            return false
        case "4":
            if event.modifierFlags.contains(.command) {
                let percent = isRTL ? 25 : 75
                focusedIndex = NavigationHelper.indexForPercent(percent, totalCount: entries.count)
                Logger.folder.debug("Cmd+4 → \(percent, privacy: .public)%")
                return true
            }
            return false
        case "5":
            if event.modifierFlags.contains(.command) {
                let percent = isRTL ? 0 : 100
                focusedIndex = NavigationHelper.indexForPercent(percent, totalCount: entries.count)
                Logger.folder.debug("Cmd+5 → \(percent, privacy: .public)%")
                return true
            }
            return false
            
        // X key - toggle selection
        case "x":
            let entry = entries[currentIndex]
            toggleSelection(entry)
            return true
            
        // #55: V key - toggle single page marker (previously: favorite)
        case "v":
            let added = CacheManager.shared.toggleSinglePageMarker(for: imageSource.url, at: currentIndex)
            Logger.thumbnailGrid.debug("Single page marker at \(currentIndex, privacy: .public): \(added ? "ON" : "OFF")")
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
                Logger.folder.debug("Reading direction toggled to: \(newDirection.displayName, privacy: .public)")
            } else {
                // R: Open from bookmark (last viewed), fallback to current
                let startIndex = lastViewedIndex ?? currentIndex
                previewMode = .viewer(index: startIndex)
            }
            return true
        
        // #72: Z - previous favorite (RTL-aware), Ctrl+Z - first/last favorite (RTL-aware)
        case "z":
            if event.modifierFlags.contains(.control) {
                // Ctrl+Z = jump to first favorite (RTL: last favorite)
                let targetFav = isRTL ? favoriteIndices.max() : favoriteIndices.min()
                if let fav = targetFav {
                    focusedIndex = fav
                    Logger.folder.debug("Ctrl+Z → \(isRTL ? "last" : "first", privacy: .public) favorite at \(fav, privacy: .public)")
                }
            } else {
                let targetIndex = isRTL
                    ? NavigationHelper.nextFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: settings.loopWithinSource)
                    : NavigationHelper.previousFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: settings.loopWithinSource)
                if let target = targetIndex {
                    focusedIndex = target
                    Logger.folder.debug("Z → favorite at \(target, privacy: .public)")
                }
            }
            return true
            
        // #72: C - next favorite (RTL-aware), Ctrl+C - last/first favorite (RTL-aware)
        case "c":
            if event.modifierFlags.contains(.control) {
                // Ctrl+C = jump to last favorite (RTL: first favorite)
                let targetFav = isRTL ? favoriteIndices.min() : favoriteIndices.max()
                if let fav = targetFav {
                    focusedIndex = fav
                    Logger.folder.debug("Ctrl+C → \(isRTL ? "first" : "last", privacy: .public) favorite at \(fav, privacy: .public)")
                }
            } else {
                let targetIndex = isRTL
                    ? NavigationHelper.previousFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: settings.loopWithinSource)
                    : NavigationHelper.nextFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: settings.loopWithinSource)
                if let target = targetIndex {
                    focusedIndex = target
                    Logger.folder.debug("C → favorite at \(target, privacy: .public)")
                }
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
    
    private func openPreview(at index: Int) {
        guard index >= 0 && index < entries.count else { return }
        Logger.preview.debug("Opening preview at index: \(index, privacy: .public) - \(entries[index].name)")
        previewMode = .quickLook(index: index)
    }
    
    // MARK: - Archive Export
    
    private func confirmExportArchive() {
        // #105: Initialize metadata options from settings
        exportMetadataOptions = settings.defaultMetadataOptions
        // #103: Show confirmation if favorites would be excluded
        if affectedFavoriteCount > 0 {
            pendingExportType = .archive
            showFavoriteExportConfirm = true
            return
        }
        executeExportArchive()
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
        // #105: Initialize metadata options from settings
        exportMetadataOptions = settings.defaultMetadataOptions
        // #103: Show confirmation if favorites would be excluded
        if affectedFavoriteCount > 0 {
            pendingExportType = .pdf
            showFavoriteExportConfirm = true
            return
        }
        executeExportPDF()
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
        // #105: Initialize metadata options from settings
        exportMetadataOptions = settings.defaultMetadataOptions
        // #103: Show confirmation if favorites would be excluded
        if affectedFavoriteCount > 0 {
            pendingExportType = .png
            showFavoriteExportConfirm = true
            return
        }
        executeExportPNG()
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
        // #105: Initialize metadata options from settings
        exportMetadataOptions = settings.defaultMetadataOptions
        // #103: Show confirmation if favorites would be excluded
        if affectedFavoriteCount > 0 {
            pendingExportType = .pngZip
            showFavoriteExportConfirm = true
            return
        }
        executeExportPNGZip()
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

// MARK: - Grid Section for Bookmarks (#62)

/// A section of the grid, divided by bookmarks
struct GridSection: Identifiable {
    let id: String  // Stable ID for SwiftUI
    let bookmark: Bookmark?  // nil = first section (before any bookmark)
    let items: [GridEntry]
    
    struct GridEntry: Identifiable {
        let index: Int
        let entry: ImageEntry
        var id: UUID { entry.id }
    }
}

/// Horizontal divider with bookmark name (#62)
/// Click section name to edit inline (Phase 4)
struct BookmarkDividerView: View {
    let bookmark: Bookmark
    let sourceURL: URL
    let isRTL: Bool
    var onNameChanged: (() -> Void)?
    
    @State private var isEditing: Bool = false
    @State private var editingName: String = ""
    @FocusState private var textFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            if isRTL {
                line
                label
            } else {
                label
                line
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }
    
    @ViewBuilder
    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            
            if isEditing {
                TextField("Section name", text: $editingName)
                .font(.caption)
                .fontWeight(.medium)
                .textFieldStyle(.plain)
                .frame(maxWidth: 200)
                .focused($textFieldFocused)
                .onSubmit {
                    commitEdit()
                }
                .onExitCommand {
                    cancelEdit()
                }
                .onAppear {
                    textFieldFocused = true
                }
            } else {
                Text(bookmark.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .onTapGesture {
                        startEdit()
                    }
                    .help("Click to edit section name")
            }
        }
    }
    
    private var line: some View {
        Rectangle()
            .fill(Color.orange.opacity(0.4))
            .frame(height: 1)
    }
    
    private func startEdit() {
        editingName = bookmark.name
        isEditing = true
    }
    
    private func commitEdit() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != bookmark.name {
            CacheManager.shared.updateBookmarkName(for: sourceURL, id: bookmark.id, name: trimmed)
            Logger.bookmark.debug("Renamed '\(bookmark.name)' → '\(trimmed)'")
            onNameChanged?()
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
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

// MARK: - Thumbnail Display Item (#69)

enum ThumbnailDisplayItem: Identifiable {
    case single(Int)
    case spread(leftIndex: Int, rightIndex: Int)
    
    var id: String {
        switch self {
        case .single(let index):
            return "single-\(index)"
        case .spread(let left, let right):
            return "spread-\(left)-\(right)"
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
    
    @State private var spreadLayoutVersion: Int = 0
    @State private var pendingDebounce: DispatchWorkItem? = nil

    private func scheduleSpreadLayoutUpdate() {
        pendingDebounce?.cancel()
        let work = DispatchWorkItem { spreadLayoutVersion += 1 }
        pendingDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    
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
        let _ = spreadLayoutVersion  // #144: Trigger re-evaluation after aspect ratio cache
        let isSpreadMode = AppSettings.shared.isSpreadModeEnabled
        let indices = buildDisplayIndices(isSpreadMode: isSpreadMode)
        
        ForEach(indices, id: \.id) { item in
            switch item {
            case .single(let index):
                let entry = entries[index]
                ThumbnailItemView(
                    imageSource: imageSource,
                    entry: entry,
                    index: index,
                    isCurrent: index == currentIndex,
                    favoriteStatus: getFavoriteStatus(entry),
                    isSelected: selectedPaths.contains(entry.path),
                    selectionMode: selectionMode,
                    size: thumbnailSize,
                    onTap: { onSelect(index) },
                    onAspectRatioCached: { scheduleSpreadLayoutUpdate() }
                )
                .id("\(index)-\(favoritesVersion)")
                
            case .spread(let leftIndex, let rightIndex):
                SpreadThumbnailPairView(
                    imageSource: imageSource,
                    leftEntry: entries[leftIndex],
                    rightEntry: entries[rightIndex],
                    leftIndex: leftIndex,
                    rightIndex: rightIndex,
                    currentIndex: currentIndex,
                    contentHashes: contentHashes,
                    selectedPaths: selectedPaths,
                    favoritesVersion: favoritesVersion,
                    selectionMode: selectionMode,
                    pairSize: thumbnailSize,
                    onSelect: { index in onSelect(index) }
                )
                .id("spread-\(leftIndex)-\(favoritesVersion)")
            }
        }
    }
    
    /// Build display indices considering spread pairs
    private func buildDisplayIndices(isSpreadMode: Bool) -> [ThumbnailDisplayItem] {
        var items: [ThumbnailDisplayItem] = []
        var index = 0
        
        while index < entries.count {
            if !isSpreadMode {
                // Spread mode OFF: all single
                items.append(.single(index))
                index += 1
            } else {
                let shouldBeSingle = SpreadNavigationHelper.shouldShowSinglePage(
                    for: imageSource.url,
                    at: index,
                    totalCount: entries.count,
                    entries: entries
                )
                
                if shouldBeSingle || index >= entries.count - 1 {
                    items.append(.single(index))
                    index += 1
                } else {
                    // Spread pair: index and index+1
                    items.append(.spread(leftIndex: index, rightIndex: index + 1))
                    index += 2
                }
            }
        }
        
        return items
    }
    
    private func scrollToIndex(_ index: Int, proxy: ScrollViewProxy) {
            guard index >= 0, index < entries.count else { return }
            
            // Find the correct ID to scroll to
            let targetID: String
            let isSpreadMode = AppSettings.shared.isSpreadModeEnabled
            
            if isSpreadMode {
                // Check if this index is part of a spread pair
                let items = buildDisplayIndices(isSpreadMode: true)
                if let item = items.first(where: { item in
                    switch item {
                    case .single(let i): return i == index
                    case .spread(let left, let right): return left == index || right == index
                    }
                }) {
                    switch item {
                    case .single(let i):
                        targetID = "\(i)-\(favoritesVersion)"
                    case .spread(let left, _):
                        targetID = "spread-\(left)-\(favoritesVersion)"
                    }
                } else {
                    targetID = "\(index)-\(favoritesVersion)"
                }
            } else {
                targetID = "\(index)-\(favoritesVersion)"
            }
            
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(targetID, anchor: .center)
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
    var onAspectRatioCached: (() -> Void)? = nil
    
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
            if let image = image {
                // #144: Cache aspect ratio for spread detection
                CacheManager.shared.setAspectRatio(
                    for: imageSource.url, path: entry.path,
                    ratio: image.size.width / image.size.height
                )
            }
            DispatchQueue.main.async {
                thumbnail = image
                onAspectRatioCached?()
            }
        }
    }
}

// MARK: - Spread Thumbnail Pair View (#69)

struct SpreadThumbnailPairView: View {
    let imageSource: any ImageSource
    let leftEntry: ImageEntry
    let rightEntry: ImageEntry
    let leftIndex: Int
    let rightIndex: Int
    let currentIndex: Int
    let contentHashes: [String: String]
    let selectedPaths: Set<String>
    let favoritesVersion: Int
    let selectionMode: SelectionMode
    let pairSize: CGFloat  // Total width/height for the pair
    var onSelect: (Int) -> Void
    
    @State private var leftThumbnail: NSImage? = nil
    @State private var rightThumbnail: NSImage? = nil
    
    /// Is this pair currently focused (contains currentIndex)?
    private var isCurrent: Bool {
        currentIndex == leftIndex || currentIndex == rightIndex
    }
    
    /// Size for each thumbnail (half of pair size minus spacing)
    private var itemSize: CGFloat {
        (pairSize - 2) / 2  // 2px for center gap
    }
    
    private var leftFavoriteStatus: CacheManager.FavoriteStatus {
        let hash = contentHashes[leftEntry.path]
        return CacheManager.shared.getFavoriteStatus(
            sourceURL: imageSource.url,
            entryPath: leftEntry.path,
            contentHash: hash
        )
    }
    
    private var rightFavoriteStatus: CacheManager.FavoriteStatus {
        let hash = contentHashes[rightEntry.path]
        return CacheManager.shared.getFavoriteStatus(
            sourceURL: imageSource.url,
            entryPath: rightEntry.path,
            contentHash: hash
        )
    }
    
    private var isLeftSelected: Bool {
        selectedPaths.contains(leftEntry.path)
    }
    
    private var isRightSelected: Bool {
        selectedPaths.contains(rightEntry.path)
    }
    
    private var overlayColor: Color {
        switch selectionMode {
        case .exclude: return .red
        case .keep: return .green
        }
    }
    
    var body: some View {
        // HStack with two thumbnails - #116: RTL resolved internally via source reading direction
        let direction = CacheManager.shared.getEffectiveReadingDirection(for: imageSource.url)
        HStack(spacing: 2) {
            // Left side (in LTR: lower index page; in RTL: higher index page)
            thumbnailView(
                entry: leftEntry,
                index: leftIndex,
                thumbnail: leftThumbnail,
                favoriteStatus: leftFavoriteStatus,
                isSelected: isLeftSelected
            )
            
            // Right side
            thumbnailView(
                entry: rightEntry,
                index: rightIndex,
                thumbnail: rightThumbnail,
                favoriteStatus: rightFavoriteStatus,
                isSelected: isRightSelected
            )
        }
        .environment(\.layoutDirection, direction.layoutDirection)  // #116: RTL spread inversion
        .frame(width: pairSize, height: pairSize)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onAppear {
            loadThumbnails()
        }
    }
    
    @ViewBuilder
    private func thumbnailView(
        entry: ImageEntry,
        index: Int,
        thumbnail: NSImage?,
        favoriteStatus: CacheManager.FavoriteStatus,
        isSelected: Bool
    ) -> some View {
        ZStack {
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            
            // Favorite indicator
            if favoriteStatus == .direct {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                            .padding(2)
                    }
                    Spacer()
                }
            }
            
            // Selection indicator
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(overlayColor, lineWidth: 2)
            }
        }
        .frame(width: itemSize, height: itemSize * 1.4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(index)
        }
    }
    
    private func loadThumbnails() {
        DispatchQueue.global(qos: .utility).async {
            let leftImage = imageSource.thumbnail(for: leftEntry, maxSize: pairSize)
            DispatchQueue.main.async {
                leftThumbnail = leftImage
            }
        }
        
        DispatchQueue.global(qos: .utility).async {
            let rightImage = imageSource.thumbnail(for: rightEntry, maxSize: pairSize)
            DispatchQueue.main.async {
                rightThumbnail = rightImage
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
    var onRequestSourceJump: ((Int) -> Void)?  // #143
    
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
    
    // #62 Phase 5: Bookmark list overlay state
    @State private var showBookmarkList: Bool = false
    @State private var bookmarkListCursor: Int = 0
    
    // #140: Metadata inspector state
    @State private var showMetadataInspector: Bool = false
    @State private var metadataSections: [MetadataSection] = []
    
    // #101: Deskew state
    @State private var isDeskewEnabled: Bool = false
    
    // #154: Render gate — prevent rapid key repeat from skipping pages
    @State private var isNavigationGated: Bool = false
    
    /// #54: Effective reading direction for this source
    private var effectiveReadingDirection: ReadingDirection {
        CacheManager.shared.getEffectiveReadingDirection(for: imageSource.url)
    }
    
    /// #76: Check if RTL mode for navigation key inversion
    private var isRTL: Bool {
        effectiveReadingDirection == .rtl
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
    
    // #115: Check if spread partner page is a favorite
    private var isSpreadPartnerFavorite: Bool {
        let partnerIndex = viewerIndex + 1
        guard partnerIndex < entries.count else { return false }
        let partnerEntry = entries[partnerIndex]
        let hash = contentHashes[partnerEntry.path]
        let status = CacheManager.shared.getFavoriteStatus(
            sourceURL: imageSource.url,
            entryPath: partnerEntry.path,
            contentHash: hash
        )
        return status == .direct
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
                            onSelect: { index in navigateTo(spreadSnappedIndex(index)) }
                        )
                        mainContentView
                            .environment(\.layoutDirection, effectiveReadingDirection.layoutDirection)
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
                            onSelect: { index in navigateTo(spreadSnappedIndex(index)) }
                        )
                    }
                    .environment(\.layoutDirection, effectiveReadingDirection.layoutDirection)
                    
                case .hidden:
                    mainContentView
                        .environment(\.layoutDirection, effectiveReadingDirection.layoutDirection)
                }
            }
            
            // Key event handler (transparent overlay)
            ViewerKeyEventHandler { event in
                handleKeyEvent(event)
            }
            .allowsHitTesting(false)
            
            // #62 Phase 5: Bookmark list overlay
            if showBookmarkList {
                BookmarkListOverlayView(
                    bookmarks: CacheManager.shared.getBookmarks(for: imageSource.url),
                    selectedCursor: bookmarkListCursor,
                    onSelect: { imageIndex in
                        showBookmarkList = false
                        navigateTo(min(imageIndex, entries.count - 1))
                        Logger.viewer.debug("Bookmark list click → jump to \(imageIndex, privacy: .public)")
                    },
                    onClose: { showBookmarkList = false }
                )
            }
            // #140: Metadata inspector overlay
            if showMetadataInspector {
                MetadataInspectorView(
                    sections: metadataSections,
                    onClose: { showMetadataInspector = false }
                )
            }
        }
        .clipped()
        .onAppear {
            viewerIndex = currentIndex
            previousViewerIndex = currentIndex
            isDeskewEnabled = CacheManager.shared.isDeskewEnabled(for: imageSource.url)  // #101
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
            // #140: Update metadata if inspector is open
            if showMetadataInspector, newValue >= 0, newValue < entries.count {
                metadataSections = MetadataExtractor.extract(from: imageSource, entry: entries[newValue])
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
            // #131: Empty source feedback in Viewer Mode
            if entries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("画像がありません")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(imageSource.url.lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    SpreadImageViewer(
                        imageSource: imageSource,
                        entries: entries,
                        currentIndex: $viewerIndex,
                        favoriteIndices: favoriteIndices,
                        reloadTrigger: spreadUpdateTrigger,
                        isShowingSpread: $isShowingSpread,
                        couldBeSpreadWithPrevious: $couldBeSpreadWithPrevious,
                        onImageReady: { _ in isNavigationGated = false }  // #154
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
            }
            
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
            
            // Favorite indicator — #115: spread-aware (either page)
            if isCurrentFavorite || (isShowingSpread && isSpreadPartnerFavorite) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
            
            // #101: Deskew indicator (PDF only)
            if isDeskewEnabled {
                HStack(spacing: 3) {
                    Image(systemName: "angle")
                        .font(.caption)
                    Text("DESKEW")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.cyan.opacity(0.15))
                .cornerRadius(4)
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
            
            // Position indicator — #115: spread-aware (show both pages)
            if isShowingSpread {
                let left = viewerIndex + 1
                let right = viewerIndex + 2
                Text(isRTL
                     ? "\(right)-\(left) / \(entries.count)"
                     : "\(left)-\(right) / \(entries.count)")
                    .foregroundStyle(.white.opacity(0.8))
                    .monospacedDigit()
            } else {
                Text("\(viewerIndex + 1) / \(entries.count)")
                    .foregroundStyle(.white.opacity(0.8))
                    .monospacedDigit()
            }
            
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
            // #101: Deskew hints (PDF only)
            if imageSource.sourceType == .pdf {
                Text("⌘D: 傾き補正")
                Text("⌘[/]: 微調整")
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
        Logger.viewer.debug("navigateTo: \(viewerIndex, privacy: .public) → \(index, privacy: .public)")
        previousViewerIndex = viewerIndex
        viewerIndex = index
    }
    
    /// #154: Navigate with render gate — ensures each page displays at least one frame
    private func gatedNavigate(_ action: () -> Void) {
        guard !isNavigationGated else { return }
        let before = viewerIndex
        action()
        if viewerIndex != before { isNavigationGated = true }
    }
    
    /// #129: Snap index to spread pair start if target is a non-leading page
    private func spreadSnappedIndex(_ index: Int) -> Int {
        SpreadNavigationHelper.spreadStartIndex(
            for: index, sourceURL: imageSource.url, entries: entries)
    }
    
    private func goToPrevious() {
        Logger.viewer.debug("goToPrevious called, current: \(viewerIndex, privacy: .public), isShowingSpread: \(isShowingSpread, privacy: .public)")
        
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
                Logger.viewer.debug("goToPrevious: cached spread at \(prevIndex, privacy: .public), stepping -2")
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
        Logger.viewer.debug("goToNext called, current: \(viewerIndex, privacy: .public), isShowingSpread: \(isShowingSpread, privacy: .public)")
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
    
    // #72: Favorite navigation (unified from Slide Mode)
    // #14: Unified favorite navigation via NavigationHelper
    private func goToPreviousFavorite() {
        guard let targetIndex = NavigationHelper.previousFavoriteIndexSpreadAware(
            from: viewerIndex,
            favoriteIndices: favoriteIndices,
            sourceURL: imageSource.url,
            entries: entries
        ) else { return }
        
        Logger.viewer.debug("goToPreviousFavorite: \(viewerIndex, privacy: .public) → \(targetIndex, privacy: .public)")
        navigateTo(targetIndex)
    }
    
    // #14: Unified favorite navigation via NavigationHelper
    private func goToNextFavorite() {
        guard let targetIndex = NavigationHelper.nextFavoriteIndexSpreadAware(
            from: viewerIndex,
            favoriteIndices: favoriteIndices,
            sourceURL: imageSource.url,
            entries: entries,
            isShowingSpread: isShowingSpread
        ) else { return }
        
        Logger.viewer.debug("goToNextFavorite: \(viewerIndex, privacy: .public) → \(targetIndex, privacy: .public)")
        navigateTo(targetIndex)
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
                Logger.viewer.debug("Correcting backward spread (showing spread): \(viewerIndex, privacy: .public) → \(viewerIndex - 1, privacy: .public)")
                preNavIndex = viewerIndex
                viewerIndex -= 1
                return  // Keep navDirection for chained corrections
            }
        } else if couldBeSpreadWithPrevious {
            // 単独表示だが、前のページとspreadになれる可能性がある → 戻ってみる
            if viewerIndex > 0 {
                Logger.viewer.debug("Correcting backward spread (could be spread): \(viewerIndex, privacy: .public) → \(viewerIndex - 1, privacy: .public)")
                preNavIndex = viewerIndex
                viewerIndex -= 1
                return  // Keep navDirection for chained corrections
            }
        }
        
        navDirection = 0
    }
    
    // MARK: - #101: Deskew Angle Adjustment
    
    /// Nudge the deskew angle for a page by a given degree offset
    /// - Parameters:
    ///   - degrees: Angle adjustment in degrees (+/-)
    ///   - targetRight: If true, targets the visual RIGHT page in spread mode
    ///     Without shift = visual left page, with shift = visual right page
    ///     RTL-aware: visual left/right maps to correct entry index via XOR
    private func nudgeDeskewAngle(by degrees: CGFloat, targetRight: Bool = false) {
        // Determine which page to adjust (RTL-aware for spread)
        // In spread: LTR left=viewerIndex, right=viewerIndex+1
        //            RTL left=viewerIndex+1, right=viewerIndex (HStack reverses)
        // adjustPartner = targetRight XOR isRTL
        let adjustPartner = (targetRight != isRTL)
        let targetIndex = (isShowingSpread && adjustPartner && viewerIndex + 1 < entries.count)
            ? viewerIndex + 1
            : viewerIndex
        
        guard targetIndex < entries.count else { return }
        let entry = entries[targetIndex]
        
        // Auto-enable deskew if not already on
        if !isDeskewEnabled {
            _ = CacheManager.shared.toggleDeskew(for: imageSource.url)
            isDeskewEnabled = true
        }
        
        let step = degrees * CGFloat.pi / 180.0
        let currentAngle = CacheManager.shared.getDeskewAngle(for: imageSource.url, entryPath: entry.path) ?? 0.0
        let newAngle = currentAngle + step
        CacheManager.shared.setDeskewAngle(for: imageSource.url, entryPath: entry.path, angle: newAngle)
        spreadUpdateTrigger.toggle()
        Logger.viewer.debug("Deskew nudge \(degrees > 0 ? "+" : "")\(degrees, privacy: .public)° page[\(targetIndex, privacy: .public)] → \(newAngle * 180 / CGFloat.pi, privacy: .public)°")
    }
    
    // MARK: - Key Event Handling (#67: Spread-aware navigation)
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // #62 Phase 5: Delegate keys to bookmark list overlay when showing
        if showBookmarkList {
            let bookmarks = CacheManager.shared.getBookmarks(for: imageSource.url)
            let action = BookmarkListKeyHandler.handle(event: event, bookmarks: bookmarks, cursor: bookmarkListCursor)
            switch action {
            case .moveCursor(let newCursor):
                bookmarkListCursor = newCursor
            case .selectAndClose(let imageIndex):
                showBookmarkList = false
                navigateTo(min(imageIndex, entries.count - 1))
                Logger.viewer.debug("Bookmark list → jump to \(imageIndex, privacy: .public)")
            case .close:
                showBookmarkList = false
            case .consumed:
                break
            }
            return true
        }

        // #140: When metadata inspector is showing, Esc closes it instead of exiting viewer
        if showMetadataInspector && event.keyCode == 53 {
            showMetadataInspector = false
            return true
        }
        
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
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step file navigation (RTL-aware)
                let step = AppSettings.shared.navigationStepCount
                if let target = NavigationHelper.navigateNStep(
                    direction: .backward, from: viewerIndex,
                    totalCount: entries.count, stepCount: step, isRTL: isRTL
                ) { navigateTo(target) }
            } else if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                // #76: RTL inverts direction
                gatedNavigate { isRTL ? goToNext() : goToPrevious() }  // #154
            }
            return true
            
        // Right arrow
        case 124:
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step file navigation (RTL-aware)
                let step = AppSettings.shared.navigationStepCount
                if let target = NavigationHelper.navigateNStep(
                    direction: .forward, from: viewerIndex,
                    totalCount: entries.count, stepCount: step, isRTL: isRTL
                ) { navigateTo(target) }
            } else if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                // #76: RTL inverts direction
                gatedNavigate { isRTL ? goToPrevious() : goToNext() }  // #154
            }
            return true
        
        // Up arrow - always previous (#106: vertical = direction-independent)
        case 126:
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step source navigation
                let step = AppSettings.shared.navigationStepCount
                onRequestSourceJump?(-step)
            } else if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                gatedNavigate { goToPrevious() }  // #154
            }
            return true
            
        // Down arrow - always next (#106: vertical = direction-independent)
        case 125:
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step source navigation
                let step = AppSettings.shared.navigationStepCount
                onRequestSourceJump?(step)
            } else if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                gatedNavigate { goToNext() }  // #154
            }
            return true

        // F key (keyCode 3) - Ctrl+F = Slide Mode
        case 3:
            Logger.viewer.debug("keyCode 3 detected, control: \(event.modifierFlags.contains(.control), privacy: .public)")
            if event.modifierFlags.contains(.control) {
                Logger.viewer.debug("Ctrl+F → entering Slide Mode")
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
            
        // A - previous (Ctrl+A = jump to start/end, #62: Shift+A = prev bookmark)
        case "a":
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step file navigation (RTL-aware)
                let step = AppSettings.shared.navigationStepCount
                if let target = NavigationHelper.navigateNStep(
                    direction: .backward, from: viewerIndex,
                    totalCount: entries.count, stepCount: step, isRTL: isRTL
                ) { navigateTo(target) }
            } else if event.modifierFlags.contains(.shift) {
                // #62: Shift+A = previous bookmark (RTL-aware)
                if let target = NavigationHelper.navigateBookmark(
                    direction: .backward, from: viewerIndex,
                    sourceURL: imageSource.url, isRTL: isRTL
                ) {
                    navigateTo(target)
                    Logger.viewer.debug("Shift+A → bookmark at \(target, privacy: .public)")
                }
            } else if event.modifierFlags.contains(.control) {
                // #72: Ctrl+A = jump to start (RTL: end)
                let target = isRTL ? entries.count - 1 : 0
                navigateTo(target)
                Logger.viewer.debug("Ctrl+A → \(isRTL ? "end" : "start")")
            } else {
                // #76: RTL inverts direction
                gatedNavigate { isRTL ? goToNext() : goToPrevious() }  // #154
            }
            return true
            
        // D - next (Ctrl+D = jump to end/start, #62: Shift+D = next bookmark, #101: Cmd+D = deskew)
        case "d":
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step file navigation (RTL-aware)
                let step = AppSettings.shared.navigationStepCount
                if let target = NavigationHelper.navigateNStep(
                    direction: .forward, from: viewerIndex,
                    totalCount: entries.count, stepCount: step, isRTL: isRTL
                ) { navigateTo(target) }
            } else if event.modifierFlags.contains(.shift) {
                // #62: Shift+D = next bookmark (RTL-aware)
                if let target = NavigationHelper.navigateBookmark(
                    direction: .forward, from: viewerIndex,
                    sourceURL: imageSource.url, isRTL: isRTL
                ) {
                    navigateTo(target)
                    Logger.viewer.debug("Shift+D → bookmark at \(target, privacy: .public)")
                }
            } else if event.modifierFlags.contains(.command) {
                // #101: Cmd+D = toggle deskew (PDF only)
                if imageSource.sourceType == .pdf {
                    let enabled = CacheManager.shared.toggleDeskew(for: imageSource.url)
                    isDeskewEnabled = enabled
                    spreadUpdateTrigger.toggle()
                    Logger.viewer.info("Deskew toggled: \(enabled ? "ON" : "OFF")")
                }
            } else if event.modifierFlags.contains(.control) {
                // #72: Ctrl+D = jump to end (RTL: start)
                let target = isRTL ? 0 : entries.count - 1
                navigateTo(target)
                Logger.viewer.debug("Ctrl+D → \(isRTL ? "start" : "end")")
            } else {
                // #76: RTL inverts direction
                gatedNavigate { isRTL ? goToPrevious() : goToNext() }  // #154
            }
            return true
        
        // S017: W - previous (#106: vertical = direction-independent)
        case "w":
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step source navigation
                let step = AppSettings.shared.navigationStepCount
                onRequestSourceJump?(-step)
            } else if event.modifierFlags.contains(.control) {
                onRequestPreviousSource?()
            } else {
                gatedNavigate { goToPrevious() }  // #154
            }
            return true
            
        // S017: S - next (#106: vertical = direction-independent)
        // #62: Shift+S = bookmark
        case "s":
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step source navigation
                let step = AppSettings.shared.navigationStepCount
                onRequestSourceJump?(step)
            } else if event.modifierFlags.contains(.shift) {
                // #62: Shift+S = add/delete bookmark at current position
                if let entry = currentEntry {
                    let defaultName = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
                    BookmarkDialogHelper.handleShiftS(
                        sourceURL: imageSource.url,
                        imageIndex: viewerIndex,
                        defaultName: defaultName,
                        window: NSApp.keyWindow
                    )
                }
            } else if event.modifierFlags.contains(.control) {
                onRequestNextSource?()
            } else {
                gatedNavigate { goToNext() }  // #154
            }
            return true
        
        // #62 Phase 5: Shift+B = toggle bookmark list overlay
        case "b":
            if event.modifierFlags.contains(.shift) {
                let bookmarks = CacheManager.shared.getBookmarks(for: imageSource.url)
                showBookmarkList = true
                if let nearest = bookmarks.enumerated().min(by: {
                    abs($0.element.imageIndex - viewerIndex) < abs($1.element.imageIndex - viewerIndex)
                }) {
                    bookmarkListCursor = nearest.offset
                } else {
                    bookmarkListCursor = 0
                }
                Logger.viewer.debug("Shift+B → bookmark list (\(bookmarks.count, privacy: .public) bookmarks)")
            }
            return true
        // #140: I - toggle metadata inspector
        case "i":
            if showMetadataInspector {
                showMetadataInspector = false
            } else {
                if let entry = currentEntry {
                    metadataSections = MetadataExtractor.extract(from: imageSource, entry: entry)
                }
                showMetadataInspector = true
            }
            return true

        // #72: Cmd+1-5 = jump to percentage position (RTL-aware, Cmd to avoid system shortcut conflict)
        case "1":
            if event.modifierFlags.contains(.command) {
                let percent = isRTL ? 100 : 0
                navigateTo(NavigationHelper.indexForPercent(percent, totalCount: entries.count))
                Logger.viewer.debug("Cmd+1 → \(percent, privacy: .public)%")
                return true
            }
            return false
        case "2":
            if event.modifierFlags.contains(.command) {
                let percent = isRTL ? 75 : 25
                navigateTo(NavigationHelper.indexForPercent(percent, totalCount: entries.count))
                Logger.viewer.debug("Cmd+2 → \(percent, privacy: .public)%")
                return true
            }
            return false
        case "3":
            if event.modifierFlags.contains(.command) {
                navigateTo(NavigationHelper.indexForPercent(50, totalCount: entries.count))
                Logger.viewer.debug("Cmd+3 → 50%")
                return true
            }
            return false
        case "4":
            if event.modifierFlags.contains(.command) {
                let percent = isRTL ? 25 : 75
                navigateTo(NavigationHelper.indexForPercent(percent, totalCount: entries.count))
                Logger.viewer.debug("Cmd+4 → \(percent, privacy: .public)%")
                return true
            }
            return false
        case "5":
            if event.modifierFlags.contains(.command) {
                let percent = isRTL ? 0 : 100
                navigateTo(NavigationHelper.indexForPercent(percent, totalCount: entries.count))
                Logger.viewer.debug("Cmd+5 → \(percent, privacy: .public)%")
                return true
            }
            return false

        // F - toggle favorite
        case "f":
            if event.modifierFlags.contains(.control) {
                Logger.viewer.debug("Ctrl+F (char) → entering Slide Mode")
                onEnterSlideMode(viewerIndex)
            } else {
                guard let entry = currentEntry else { return true }
                let hash = contentHashes[entry.path]
                
                // #104: Determine direction based on leading page
                let currentStatus = CacheManager.shared.getFavoriteStatus(
                    sourceURL: imageSource.url, entryPath: entry.path, contentHash: hash
                )
                let isAdding = currentStatus != .direct
                
                _ = CacheManager.shared.toggleFavorite(
                    sourceURL: imageSource.url,
                    entryPath: entry.path,
                    contentHash: hash
                )
                
                // #104: Toggle partner if spread (only if state needs to change)
                if isShowingSpread, viewerIndex + 1 < entries.count {
                    let partnerEntry = entries[viewerIndex + 1]
                    let partnerHash = contentHashes[partnerEntry.path]
                    let partnerIsDirect = CacheManager.shared.isDirectFavorite(
                        sourceURL: imageSource.url, entryPath: partnerEntry.path
                    )
                    if isAdding != partnerIsDirect {
                        _ = CacheManager.shared.toggleFavorite(
                            sourceURL: imageSource.url,
                            entryPath: partnerEntry.path,
                            contentHash: partnerHash
                        )
                    }
                }
                
                favoritesVersion += 1
            }
            return true
        
        // R - exit to Filer (close Viewer Mode)
        // #54: Ctrl+R = toggle reading direction
        case "r":
            if event.modifierFlags.contains(.control) {
                // Ctrl+R: Toggle reading direction
                let newDirection = CacheManager.shared.toggleReadingDirection(for: imageSource.url)
                Logger.viewer.debug("Reading direction toggled to: \(newDirection.displayName, privacy: .public)")
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
        
        // #55/#67: V - toggle single page marker (#111: spread-aware)
        case "v":
            let target = CacheManager.shared.spreadAwareToggleTarget(for: imageSource.url, at: viewerIndex, isInSpread: isShowingSpread)
            let added = CacheManager.shared.toggleSinglePageMarker(for: imageSource.url, at: target)
            Logger.viewer.debug("Single page marker at \(target, privacy: .public) (from \(viewerIndex, privacy: .public), spread: \(isShowingSpread, privacy: .public)): \(added ? "ON" : "OFF")")
            spreadUpdateTrigger.toggle()  // #67: Trigger SpreadImageViewer refresh
            return true
        
        // #101: Cmd+[ = nudge deskew angle -0.1°, Cmd+] = nudge +0.1°
        //       Cmd+Shift+[/] = adjust visual RIGHT page in spread (Shift+[ produces "{")
        case "[", "{":
            if event.modifierFlags.contains(.command), imageSource.sourceType == .pdf {
                let targetRight = event.modifierFlags.contains(.shift)
                nudgeDeskewAngle(by: -0.1, targetRight: targetRight)
            }
            return true
        case "]", "}":
            if event.modifierFlags.contains(.command), imageSource.sourceType == .pdf {
                let targetRight = event.modifierFlags.contains(.shift)
                nudgeDeskewAngle(by: 0.1, targetRight: targetRight)
            }
            return true
        
        // #72: Z - previous favorite (RTL-aware), Ctrl+Z - first/last favorite (RTL-aware)
        case "z":
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step favorite navigation (RTL-aware)
                let step = AppSettings.shared.navigationStepCount
                if let target = NavigationHelper.navigateFavoriteNStep(
                    direction: .backward, from: viewerIndex,
                    favoriteIndices: favoriteIndices, stepCount: step, isRTL: isRTL
                ) { navigateTo(target) }
            } else if event.modifierFlags.contains(.control) {
                // Ctrl+Z = jump to visual left favorite (first in LTR, last in RTL)
                let targetFav = isRTL ? favoriteIndices.max() : favoriteIndices.min()
                if let fav = targetFav {
                    navigateTo(fav)
                    Logger.viewer.debug("Ctrl+Z → \(isRTL ? "last" : "first", privacy: .public) favorite at \(fav, privacy: .public)")
                }
            } else {
                gatedNavigate { isRTL ? goToNextFavorite() : goToPreviousFavorite() }  // #154
            }
            return true
            
        // #72: C - next favorite (RTL-aware), Ctrl+C - last/first favorite (RTL-aware)
        case "c":
            if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.option) {
                // #143: N-step favorite navigation (RTL-aware)
                let step = AppSettings.shared.navigationStepCount
                if let target = NavigationHelper.navigateFavoriteNStep(
                    direction: .forward, from: viewerIndex,
                    favoriteIndices: favoriteIndices, stepCount: step, isRTL: isRTL
                ) { navigateTo(target) }
            } else if event.modifierFlags.contains(.control) {
                // Ctrl+C = jump to visual right favorite (last in LTR, first in RTL)
                let targetFav = isRTL ? favoriteIndices.min() : favoriteIndices.max()
                if let fav = targetFav {
                    navigateTo(fav)
                    Logger.viewer.debug("Ctrl+C → \(isRTL ? "first" : "last", privacy: .public) favorite at \(fav, privacy: .public)")
                }
            } else {
                gatedNavigate { isRTL ? goToPreviousFavorite() : goToNextFavorite() }  // #154
            }
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

// MARK: - Export Confirmation View (#105)

/// Sheet dialog for export confirmation with metadata carry-over options
struct ExportConfirmationView: View {
    let affectedFavoriteCount: Int
    let selectionMode: SelectionMode
    @Binding var options: MetadataCarryOverOptions
    let onCancel: () -> Void
    let onExport: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text("エクスポートの確認")
                .font(.headline)
            
            // ★ warning
            if selectionMode == .exclude {
                Label("★付き \(affectedFavoriteCount) 件が除外されます", systemImage: "star.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("★付き \(affectedFavoriteCount) 件が出力に含まれません", systemImage: "star.fill")
                    .foregroundStyle(.orange)
            }
            
            Divider()
            
            // Metadata options
            Text("メタデータの引き継ぎ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Toggle("★ お気に入り", isOn: $options.favorites)
            Toggle("栞 ブックマーク", isOn: $options.bookmarks)
            Toggle("読み取り方向", isOn: $options.readingDirection)
            Toggle("単独表示マーカー", isOn: $options.singlePageMarkers)
            
            Divider()
            
            // Buttons
            HStack {
                Spacer()
                Button("キャンセル", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button(selectionMode == .exclude ? "除外する" : "続行") {
                    onExport()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
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
