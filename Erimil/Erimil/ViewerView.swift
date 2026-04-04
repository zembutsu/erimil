//
//  ViewerView.swift
//  Erimil
//
//  Extracted from ThumbnailGridView.swift (#175 Phase 1)
//  Contains: ThumbnailSidebarView, ViewerView, ViewerKeyEventHandler
//

import SwiftUI
import AppKit
import os

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

    // #172: Auto-Slide / #178: Reverse Playback
    @State private var autoSlideMode: Int = 0         // 0=off 1/2/3=forward -1/-2/-3=reverse
    @State private var autoSlideTapHandler = AutoSlideTapHandler()
    @State private var autoSlideWaitingForImage: Bool = false
    
    // #201: Animation playback controller (shared with SpreadImageViewer)
    @StateObject private var animationController = AnimationPlaybackController()
    
    // #235: Cursor auto-hide in Reader Mode
    @State private var cursorHideTimer: DispatchWorkItem?
    @State private var isCursorHidden: Bool = false
    @State private var mouseMonitor: Any?
    private let cursorHideDelay: TimeInterval = 3.0
    
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
            startCursorMonitor()  // #235
        }
        .onDisappear {
            stopCursorMonitor()  // #235
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
                        animationController: animationController,  // #201
                        onImageReady: { _ in
                            // #160: Hold gate for 1 frame min — prevents key-repeat from skipping pages on cache hit
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                                isNavigationGated = false
                                // #172: Auto-Slide cache-miss wait
                                if autoSlideWaitingForImage {
                                    autoSlideWaitingForImage = false
                                    scheduleNextAutoSlideAdvance()
                                }
                            }
                        }  // #154
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

            // #172/#178: Auto-Slide badge
            if autoSlideMode != 0 {
                let labels = ["", "AUTO", "FAST", "TURBO"]
                let absMode = abs(autoSlideMode)
                let isReverse = autoSlideMode < 0
                let arrowForward = ["", "▶ ", "▶▶ ", "▶▶▶ "]
                let arrowReverse = ["", "◀ ", "◀◀ ", "◀◀◀ "]
                let arrow = isReverse ? arrowReverse[absMode] : arrowForward[absMode]
                let badgeColor: Color = isReverse ? .purple : .green
                HStack(spacing: 4) {
                    Text(arrow + labels[absMode])
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.2))
                .cornerRadius(4)
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

    // MARK: - Auto-Slide (#172)

    private func handleAutoSlideSpaceKey() {
        autoSlideTapHandler.handleSpace(
            currentMode: autoSlideMode,
            start: { mode in startAutoSlide(mode: mode) },
            stop: { stopAutoSlide() }
        )
    }

    private func handleAutoSlideShiftSpaceKey() {
        autoSlideTapHandler.handleShiftSpace(
            currentMode: autoSlideMode,
            start: { mode in startAutoSlide(mode: mode) },
            stop: { stopAutoSlide() }
        )
    }

    private func startAutoSlide(mode: Int) {
        autoSlideMode = mode
        autoSlideWaitingForImage = false
        scheduleNextAutoSlideAdvance()
        Logger.viewer.debug("Viewer Auto-slide started: mode=\(mode)")
    }

    private func stopAutoSlide() {
        guard autoSlideMode != 0 || autoSlideTapHandler.hasPendingTaps else { return }
        autoSlideMode = 0
        autoSlideTapHandler.reset()
        autoSlideWaitingForImage = false
        Logger.viewer.debug("Viewer Auto-slide stopped")
    }

    private func scheduleNextAutoSlideAdvance() {
        guard autoSlideMode != 0 else { return }
        let interval: TimeInterval
        switch abs(autoSlideMode) {
        case 1:  interval = AppSettings.shared.autoSlideIntervalNormal
        case 2:  interval = AppSettings.shared.autoSlideIntervalFast
        default: interval = AppSettings.shared.autoSlideIntervalTurbo
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            advanceAutoSlide()
        }
    }

    private func advanceAutoSlide() {
        guard autoSlideMode != 0 else { return }
        let before = viewerIndex
        let isReverse = autoSlideMode < 0
        if isReverse { goToPrevious() } else { goToNext() }
        if viewerIndex == before {
            if AppSettings.shared.autoSlideLoops {
                let target = isReverse ? entries.count - 1 : 0
                navigateTo(target)
                Logger.viewer.debug("Viewer Auto-slide: loop to \(isReverse ? "end" : "start")")
            } else {
                Logger.viewer.debug("Viewer Auto-slide: boundary reached, stopping")
                stopAutoSlide()
                return
            }
        }
        autoSlideWaitingForImage = true
    }
    
    // MARK: - #235: Cursor Auto-Hide
    
    private func startCursorMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [self] event in
            showCursor()
            scheduleCursorHide()
            return event
        }
        scheduleCursorHide()
        Logger.viewer.debug("#235: Cursor monitor started")
    }
    
    private func stopCursorMonitor() {
        cursorHideTimer?.cancel()
        cursorHideTimer = nil
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        showCursor()
        Logger.viewer.debug("#235: Cursor monitor stopped")
    }
    
    private func scheduleCursorHide() {
        cursorHideTimer?.cancel()
        let work = DispatchWorkItem { [self] in
            hideCursor()
        }
        cursorHideTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cursorHideDelay, execute: work)
    }
    
    private func hideCursor() {
        guard !isCursorHidden else { return }
        // Don't hide cursor when interactive overlays are showing
        guard !showBookmarkList, !showMetadataInspector else { return }
        NSCursor.hide()
        isCursorHidden = true
        Logger.viewer.debug("#235: Cursor hidden")
    }
    
    private func showCursor() {
        guard isCursorHidden else { return }
        NSCursor.unhide()
        isCursorHidden = false
        Logger.viewer.debug("#235: Cursor shown")
    }
    
    // MARK: - Navigation (#67: Spread-aware using isShowingSpread)
    
    private func navigateTo(_ index: Int) {
        guard index >= 0, index < entries.count else { return }
        Logger.viewer.debug("navigateTo: \(viewerIndex, privacy: .public) → \(index, privacy: .public)")
        previousViewerIndex = viewerIndex
        viewerIndex = index
        hideCursor()  // #235: Hide cursor on navigation (same as Slide Mode behavior)
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
            // #172/#178: Auto-Slide running → stop only
            if autoSlideMode != 0 {
                stopAutoSlide()
                return true
            }
            onIndexChange(viewerIndex)
            onClose()
            return true
            
        // Return/Enter - go to Slide Mode
        case 36:
            stopAutoSlide()
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

            // Shift+Space - Reverse Auto-Slide (#178)
            case KeyCode.space where event.modifierFlags.contains(.shift):
                handleAutoSlideShiftSpaceKey()
                return true

            // Space - Auto-Slide (#172) / Animation toggle (#201)
            case KeyCode.space:
                if animationController.hasAnimatedContent {
                    animationController.togglePlay()
                } else {
                    handleAutoSlideSpaceKey()
                }
                return true
            
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
            // #172/#178: Auto-Slide running → stop only
            if autoSlideMode != 0 {
                stopAutoSlide()
                return true
            }
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
            
        // L - toggle animation loop (#201)
        case "l":
            if animationController.hasAnimatedContent {
                animationController.toggleLoop()
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

