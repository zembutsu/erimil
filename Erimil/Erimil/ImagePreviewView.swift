//
//  ImagePreviewView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//  Updated: S003 (2025-12-17) - Phase 2.2 Quick Look + navigation
//  Updated: S020 (2026-01-26) - Spread (two-page) view support (#55)
//  Updated: S021 (2026-01-26) - Refactoring: Use SpreadNavigationHelper (#67)
//  Updated: S026 (2026-01-30) - RTL navigation key inversion (#76)
//  Updated: S031 (2026-02-03) - Consolidated key handling (#72): Added ↑/↓, W/S, Q
//

import SwiftUI
import AppKit
import os

/// Quick Look preview window with navigation support
/// - Space/Esc/Enter: close
/// - a/←: previous image
/// - d/→: next image
/// - z: previous favorite
/// - c: next favorite
/// - f: toggle fullscreen (Slide Mode)
/// - v: toggle single page marker (#55)
struct ImagePreviewView: View {
    let imageSource: any ImageSource
    let entries: [ImageEntry]
    let initialIndex: Int
    let favoriteIndices: Set<Int>  // For z/c navigation
    let onClose: () -> Void
    let onToggleFullScreen: () -> Void  // Callback to switch between Quick Look / Slide Mode
    
    @State private var currentIndex: Int = 0
    @State private var spreadUpdateTrigger: Bool = false  // #55: For triggering view update
    @State private var isShowingSpread: Bool = false  // #115: Track for position indicator
    
    // #62 Phase 5: Bookmark list overlay state
    @State private var showBookmarkList: Bool = false
    @State private var bookmarkListCursor: Int = 0
    
    // #55: Check if spread mode is enabled
    private var isSpreadEnabled: Bool {
        AppSettings.shared.isSpreadModeEnabled
    }
    
    // #76: Check if current source uses RTL direction
    private var isRTL: Bool {
        CacheManager.shared.getEffectiveReadingDirection(for: imageSource.url) == .rtl
    }
    
    var body: some View {
        ZStack {
            // #55/#67: Spread-aware image viewer (now from separate file)
            SpreadImageViewer(
                imageSource: imageSource,
                entries: entries,
                currentIndex: $currentIndex,
                favoriteIndices: favoriteIndices,
                reloadTrigger: spreadUpdateTrigger,
                isShowingSpread: $isShowingSpread,  // #115: Track for position indicator
                couldBeSpreadWithPrevious: .constant(false)
            )
            
            // Header overlay
            VStack {
                headerView
                Spacer()
            }
            
            // Key event handler (transparent to clicks)
            // #76: RTL mode inverts navigation direction
            QuickLookKeyHandler(
                onClose: onClose,
                onPrevious: { isRTL ? goToNext() : goToPrevious() },
                onNext: { isRTL ? goToPrevious() : goToNext() },
                onPreviousFavorite: { isRTL ? goToNextFavorite() : goToPreviousFavorite() },
                onNextFavorite: { isRTL ? goToPreviousFavorite() : goToNextFavorite() },
                onToggleFullScreen: onToggleFullScreen,
                onToggleSinglePage: { toggleSinglePageMarker() },  // #55
                onJumpToIndex: { index in jumpToIndex(index) },  // #72
                onJumpToFirstFavorite: { jumpToFirstFavorite() },  // #72: Ctrl+Z
                onJumpToLastFavorite: { jumpToLastFavorite() },  // #72: Ctrl+C
                totalCount: entries.count,  // #72
                isRTL: isRTL,  // #72: RTL support
                onAddOrDeleteBookmark: { handleBookmarkAction() },  // #62
                onPreviousBookmark: { navigateBookmark(.backward) },  // #62
                onNextBookmark: { navigateBookmark(.forward) },  // #62
                // #62 Phase 5: Bookmark list
                showBookmarkList: showBookmarkList,
                onToggleBookmarkList: {
                    let bookmarks = CacheManager.shared.getBookmarks(for: imageSource.url)
                    showBookmarkList = true
                    if let nearest = bookmarks.enumerated().min(by: {
                        abs($0.element.imageIndex - currentIndex) < abs($1.element.imageIndex - currentIndex)
                    }) {
                        bookmarkListCursor = nearest.offset
                    } else {
                        bookmarkListCursor = 0
                    }
                    Logger.preview.debug("Shift+B → bookmark list (\(bookmarks.count, privacy: .public) bookmarks)")
                },
                onBookmarkListKeyEvent: { event in
                    let bookmarks = CacheManager.shared.getBookmarks(for: imageSource.url)
                    let action = BookmarkListKeyHandler.handle(event: event, bookmarks: bookmarks, cursor: bookmarkListCursor)
                    switch action {
                    case .moveCursor(let newCursor):
                        bookmarkListCursor = newCursor
                    case .selectAndClose(let imageIndex):
                        showBookmarkList = false
                        currentIndex = min(imageIndex, entries.count - 1)
                        Logger.preview.debug("Bookmark list → jump to \(imageIndex, privacy: .public)")
                    case .close:
                        showBookmarkList = false
                    case .consumed:
                        break
                    }
                }
            )
            .allowsHitTesting(false)
            
            // #62 Phase 5: Bookmark list overlay
            if showBookmarkList {
                BookmarkListOverlayView(
                    bookmarks: CacheManager.shared.getBookmarks(for: imageSource.url),
                    selectedCursor: bookmarkListCursor,
                    onSelect: { imageIndex in
                        showBookmarkList = false
                        currentIndex = min(imageIndex, entries.count - 1)
                        Logger.preview.debug("Bookmark list click → jump to \(imageIndex, privacy: .public)")
                    },
                    onClose: { showBookmarkList = false }
                )
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            currentIndex = initialIndex
        }
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private var headerView: some View {
        HStack {
            // Navigation button - previous
            Button {
                goToPrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex <= 0)
            .opacity(currentIndex <= 0 ? 0.3 : 1.0)
            
            Spacer()
            
            // Filename + position
            if currentIndex >= 0 && currentIndex < entries.count {
                VStack(spacing: 2) {
                    Text(entries[currentIndex].name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    // #115: Spread-aware position indicator
                    if isShowingSpread {
                        let left = currentIndex + 1
                        let right = currentIndex + 2
                        Text(isRTL
                             ? "\(right)-\(left) / \(entries.count)"
                             : "\(left)-\(right) / \(entries.count)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text("\(currentIndex + 1) / \(entries.count)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            
            Spacer()
            
            // Navigation button - next
            Button {
                goToNext()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= entries.count - 1)
            .opacity(currentIndex >= entries.count - 1 ? 0.3 : 1.0)
            
            // #55: Single page marker hint (only when spread mode enabled)
            if isSpreadEnabled {
                Text("v")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.2))
                    .cornerRadius(4)
                    .padding(.leading, 8)
                    .help("Toggle single page marker")
            }
            
            // Fullscreen button (for debugging / alternative to f key)
            Button {
                Logger.preview.debug("Fullscreen button clicked")
                onToggleFullScreen()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .help("Enter Slide Mode (f)")
            
            // Fullscreen toggle hint
            Text("f")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.2))
                .cornerRadius(4)
                .padding(.leading, 4)
            
            // Close button
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Navigation (#67: Cache-based spread-aware navigation)
    
    private func goToPrevious() {
        Logger.preview.debug("goToPrevious called, current: \(currentIndex, privacy: .public)")
        guard currentIndex > 0 else { return }
        
        // #67: Try to determine step using cached aspect ratios
        if currentIndex >= 2 {
            let prevIndex = currentIndex - 2
            let wouldBeSingle = SpreadNavigationHelper.shouldShowSinglePage(
                for: imageSource.url,
                at: prevIndex,
                totalCount: entries.count,
                entries: entries
            )
            
            if !wouldBeSingle {
                Logger.preview.debug("goToPrevious: cached spread at \(prevIndex, privacy: .public), stepping -2")
                currentIndex = prevIndex
                return
            }
        }
        
        // Fallback: step -1
        currentIndex -= 1
        Logger.preview.debug("→ new index: \(currentIndex, privacy: .public)")
    }
    
    private func goToNext() {
        Logger.preview.debug("goToNext called, current: \(currentIndex, privacy: .public)")
        guard currentIndex < entries.count - 1 else { return }
        
        // #67: Calculate step using cached aspect ratios
        let isSingle = SpreadNavigationHelper.shouldShowSinglePage(
            for: imageSource.url,
            at: currentIndex,
            totalCount: entries.count,
            entries: entries
        )
        let step = isSingle ? 1 : 2
        Logger.preview.debug("goToNext: step = \(step, privacy: .public) (single: \(isSingle, privacy: .public))")
        
        let nextIndex = currentIndex + step
        if nextIndex < entries.count {
            currentIndex = nextIndex
            Logger.preview.debug("→ new index: \(currentIndex, privacy: .public)")
        } else if currentIndex < entries.count - 1 {
            // Step would overshoot but there's still a page
            currentIndex = entries.count - 1
            Logger.preview.debug("→ last page: \(currentIndex, privacy: .public)")
        }
    }
    
    // #14: Unified favorite navigation via NavigationHelper
    private func goToPreviousFavorite() {
        guard let targetIndex = NavigationHelper.previousFavoriteIndexSpreadAware(
            from: currentIndex,
            favoriteIndices: favoriteIndices,
            sourceURL: imageSource.url,
            entries: entries
        ) else { return }
        
        currentIndex = targetIndex
    }
    
    // #14: Unified favorite navigation via NavigationHelper
    private func goToNextFavorite() {
        let isShowingSpread: Bool = {
            guard AppSettings.shared.isSpreadModeEnabled,
                  currentIndex + 1 < entries.count else { return false }
            return !SpreadNavigationHelper.shouldShowSinglePage(
                for: imageSource.url, at: currentIndex,
                totalCount: entries.count, entries: entries
            )
        }()
        
        guard let targetIndex = NavigationHelper.nextFavoriteIndexSpreadAware(
            from: currentIndex,
            favoriteIndices: favoriteIndices,
            sourceURL: imageSource.url,
            entries: entries,
            isShowingSpread: isShowingSpread
        ) else { return }
        
        currentIndex = targetIndex
    }
    
    // #55: Toggle single page marker
    private func toggleSinglePageMarker() {
        let added = CacheManager.shared.toggleSinglePageMarker(for: imageSource.url, at: currentIndex)
        Logger.preview.debug("Single page marker at \(currentIndex, privacy: .public): \(added ? "ON" : "OFF")")
        spreadUpdateTrigger.toggle()
    }
    
    // #72: Jump to specific index (for Ctrl+A/D, Ctrl+1-5)
    private func jumpToIndex(_ index: Int) {
        guard !entries.isEmpty else { return }
        let targetIndex = min(max(0, index), entries.count - 1)
        guard targetIndex != currentIndex else { return }
        
        currentIndex = targetIndex
        Logger.preview.debug("→ jumped to: \(currentIndex, privacy: .public)")
    }
    
    // #72: Jump to first favorite (Ctrl+Z)
    private func jumpToFirstFavorite() {
        if let firstFav = favoriteIndices.min() {
            currentIndex = firstFav
            Logger.preview.debug("→ jumped to first favorite: \(firstFav, privacy: .public)")
        }
    }
    
    // #72: Jump to last favorite (Ctrl+C)
    private func jumpToLastFavorite() {
        if let lastFav = favoriteIndices.max() {
            currentIndex = lastFav
            Logger.preview.debug("→ jumped to last favorite: \(lastFav, privacy: .public)")
        }
    }
    
    // #62: Handle Shift+S bookmark add/delete
    private func handleBookmarkAction() {
        guard currentIndex >= 0 && currentIndex < entries.count else { return }
        let entry = entries[currentIndex]
        let defaultName = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
        BookmarkDialogHelper.handleShiftS(
            sourceURL: imageSource.url,
            imageIndex: currentIndex,
            defaultName: defaultName,
            window: NSApp.keyWindow
        )
    }
    
    // #62: Navigate to bookmark (Shift+A/D)
    private func navigateBookmark(_ direction: NavigationDirection) {
        if let target = NavigationHelper.navigateBookmark(
            direction: direction, from: currentIndex,
            sourceURL: imageSource.url, isRTL: isRTL
        ) {
            currentIndex = target
            Logger.preview.debug("→ bookmark at \(target, privacy: .public)")
        }
    }
}

// MARK: - Key Event Handler for Quick Look

struct QuickLookKeyHandler: NSViewRepresentable {
    let onClose: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPreviousFavorite: () -> Void
    let onNextFavorite: () -> Void
    let onToggleFullScreen: () -> Void
    let onToggleSinglePage: () -> Void  // #55
    let onJumpToIndex: (Int) -> Void  // #72
    let onJumpToFirstFavorite: () -> Void  // #72: Ctrl+Z
    let onJumpToLastFavorite: () -> Void  // #72: Ctrl+C
    let totalCount: Int  // #72
    let isRTL: Bool  // #72: RTL support
    let onAddOrDeleteBookmark: () -> Void  // #62: Shift+S bookmark
    let onPreviousBookmark: () -> Void  // #62: Shift+A
    let onNextBookmark: () -> Void  // #62: Shift+D
    // #62 Phase 5: Bookmark list
    let showBookmarkList: Bool
    let onToggleBookmarkList: () -> Void
    let onBookmarkListKeyEvent: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> QuickLookKeyView {
        let view = QuickLookKeyView()
        view.onClose = onClose
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onPreviousFavorite = onPreviousFavorite
        view.onNextFavorite = onNextFavorite
        view.onToggleFullScreen = onToggleFullScreen
        view.onToggleSinglePage = onToggleSinglePage  // #55
        view.onJumpToIndex = onJumpToIndex  // #72
        view.onJumpToFirstFavorite = onJumpToFirstFavorite  // #72
        view.onJumpToLastFavorite = onJumpToLastFavorite  // #72
        view.totalCount = totalCount  // #72
        view.isRTL = isRTL  // #72
        view.onAddOrDeleteBookmark = onAddOrDeleteBookmark  // #62
        view.onPreviousBookmark = onPreviousBookmark  // #62
        view.onNextBookmark = onNextBookmark  // #62
        view.showBookmarkList = showBookmarkList  // #62 Phase 5
        view.onToggleBookmarkList = onToggleBookmarkList  // #62 Phase 5
        view.onBookmarkListKeyEvent = onBookmarkListKeyEvent  // #62 Phase 5
        Logger.preview.debug("makeNSView called")
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            Logger.preview.info("makeFirstResponder called, success: \(view.window?.firstResponder === view, privacy: .public)")
        }
        return view
    }
    
    func updateNSView(_ nsView: QuickLookKeyView, context: Context) {
        nsView.onClose = onClose
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.onPreviousFavorite = onPreviousFavorite
        nsView.onNextFavorite = onNextFavorite
        nsView.onToggleFullScreen = onToggleFullScreen
        nsView.onToggleSinglePage = onToggleSinglePage  // #55
        nsView.onJumpToIndex = onJumpToIndex  // #72
        nsView.onJumpToFirstFavorite = onJumpToFirstFavorite  // #72
        nsView.onJumpToLastFavorite = onJumpToLastFavorite  // #72
        nsView.totalCount = totalCount  // #72
        nsView.isRTL = isRTL  // #72
        nsView.onAddOrDeleteBookmark = onAddOrDeleteBookmark  // #62
        nsView.onPreviousBookmark = onPreviousBookmark  // #62
        nsView.onNextBookmark = onNextBookmark  // #62
        nsView.showBookmarkList = showBookmarkList  // #62 Phase 5
        nsView.onToggleBookmarkList = onToggleBookmarkList  // #62 Phase 5
        nsView.onBookmarkListKeyEvent = onBookmarkListKeyEvent  // #62 Phase 5
    }
    
    class QuickLookKeyView: NSView {
        var onClose: (() -> Void)?
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?
        var onPreviousFavorite: (() -> Void)?
        var onNextFavorite: (() -> Void)?
        var onToggleFullScreen: (() -> Void)?
        var onToggleSinglePage: (() -> Void)?  // #55
        var onJumpToIndex: ((Int) -> Void)?  // #72: For Ctrl+A/D, Cmd+1-5
        var onJumpToFirstFavorite: (() -> Void)?  // #72: Ctrl+Z (LTR) / Ctrl+C (RTL)
        var onJumpToLastFavorite: (() -> Void)?  // #72: Ctrl+C (LTR) / Ctrl+Z (RTL)
        var totalCount: Int = 0  // #72: For percentage calculation
        var isRTL: Bool = false  // #72: RTL support
        var onAddOrDeleteBookmark: (() -> Void)?  // #62: Shift+S bookmark
        var onPreviousBookmark: (() -> Void)?  // #62: Shift+A
        var onNextBookmark: (() -> Void)?  // #62: Shift+D
        // #62 Phase 5: Bookmark list
        var showBookmarkList: Bool = false
        var onToggleBookmarkList: (() -> Void)?
        var onBookmarkListKeyEvent: ((NSEvent) -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            let hasControl = event.modifierFlags.contains(.control)
            let hasCommand = event.modifierFlags.contains(.command)
            let hasShift = event.modifierFlags.contains(.shift)  // #62
            Logger.preview.debug("keyDown: keyCode=\(event.keyCode, privacy: .public), chars='\(event.charactersIgnoringModifiers ?? "nil")', ctrl=\(hasControl), cmd=\(hasCommand), shift=\(hasShift)")
            
            // #62 Phase 5: Delegate keys to bookmark list when showing
            if showBookmarkList {
                onBookmarkListKeyEvent?(event)
                return
            }
            
            switch event.keyCode {
            // Space (49), Escape (53), Enter (36) - close
            case 49, 53, 36:
                Logger.preview.debug("→ Close triggered")
                onClose?()
                
            // Left arrow (123)
            case 123:
                Logger.preview.debug("→ Previous triggered")
                onPrevious?()
                
            // Right arrow (124)
            case 124:
                Logger.preview.debug("→ Next triggered")
                onNext?()
            
            // #72: Up arrow (126) - same as Left (unified with Slide/Viewer)
            case 126:
                Logger.preview.debug("→ Previous (↑) triggered")
                onPrevious?()
                
            // #72: Down arrow (125) - same as Right (unified with Slide/Viewer)
            case 125:
                Logger.preview.debug("→ Next (↓) triggered")
                onNext?()
                
            default:
                // Check character keys
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    switch chars {
                    case "a":
                        if hasShift {
                            // #62: Shift+A = previous bookmark
                            Logger.preview.debug("→ Previous bookmark (Shift+A)")
                            onPreviousBookmark?()
                        } else if hasControl {
                            // #72: Ctrl+A = jump to visual left (start in LTR, end in RTL)
                            let target = isRTL ? NavigationHelper.lastIndex(totalCount: totalCount) : 0
                            Logger.preview.debug("→ Jump to \(self.isRTL ? "end" : "start") (Ctrl+A)")
                            onJumpToIndex?(target)
                        } else {
                            Logger.preview.debug("→ Previous (a) triggered")
                            onPrevious?()
                        }
                    case "d":
                        if hasShift {
                            // #62: Shift+D = next bookmark
                            Logger.preview.debug("→ Next bookmark (Shift+D)")
                            onNextBookmark?()
                        } else if hasControl {
                            // #72: Ctrl+D = jump to visual right (end in LTR, start in RTL)
                            let target = isRTL ? 0 : NavigationHelper.lastIndex(totalCount: totalCount)
                            Logger.preview.debug("→ Jump to \(self.isRTL ? "start" : "end") (Ctrl+D)")
                            onJumpToIndex?(target)
                        } else {
                            Logger.preview.debug("→ Next (d) triggered")
                            onNext?()
                        }
                    // #72: W - same as A (unified with Slide/Viewer)
                    case "w":
                        Logger.preview.debug("→ Previous (w) triggered")
                        onPrevious?()
                    // #72: S - same as D (unified with Slide/Viewer)
                    // #62: Shift+S = bookmark
                    case "s":
                        if hasShift {
                            Logger.preview.debug("→ Bookmark (Shift+S) triggered")
                            onAddOrDeleteBookmark?()
                        } else {
                            Logger.preview.debug("→ Next (s) triggered")
                            onNext?()
                        }
                    // #72: Cmd+1-5 = jump to percentage position (RTL-aware, Cmd to avoid system shortcut conflict)
                    case "1":
                        if hasCommand {
                            let percent = isRTL ? 100 : 0
                            Logger.preview.debug("→ Jump to \(percent, privacy: .public)% (Cmd+1)")
                            onJumpToIndex?(NavigationHelper.indexForPercent(percent, totalCount: totalCount))
                        }
                    case "2":
                        if hasCommand {
                            let percent = isRTL ? 75 : 25
                            Logger.preview.debug("→ Jump to \(percent, privacy: .public)% (Cmd+2)")
                            onJumpToIndex?(NavigationHelper.indexForPercent(percent, totalCount: totalCount))
                        }
                    case "3":
                        if hasCommand {
                            Logger.preview.debug("→ Jump to 50% (Cmd+3)")
                            onJumpToIndex?(NavigationHelper.indexForPercent(50, totalCount: totalCount))
                        }
                    case "4":
                        if hasCommand {
                            let percent = isRTL ? 25 : 75
                            Logger.preview.debug("→ Jump to \(percent, privacy: .public)% (Cmd+4)")
                            onJumpToIndex?(NavigationHelper.indexForPercent(percent, totalCount: totalCount))
                        }
                    case "5":
                        if hasCommand {
                            let percent = isRTL ? 0 : 100
                            Logger.preview.debug("→ Jump to \(percent, privacy: .public)% (Cmd+5)")
                            onJumpToIndex?(NavigationHelper.indexForPercent(percent, totalCount: totalCount))
                        }
                    // #72: Z - previous favorite, Ctrl+Z - first/last favorite (RTL-aware)
                    case "z":
                        if hasControl {
                            // Ctrl+Z = visual left favorite (first in LTR, last in RTL)
                            Logger.preview.debug("→ \(self.isRTL ? "Last" : "First") favorite (Ctrl+Z)")
                            isRTL ? onJumpToLastFavorite?() : onJumpToFirstFavorite?()
                        } else {
                            Logger.preview.debug("→ Previous favorite (z) triggered")
                            onPreviousFavorite?()
                        }
                    // #72: C - next favorite, Ctrl+C - last/first favorite (RTL-aware)
                    case "c":
                        if hasControl {
                            // Ctrl+C = visual right favorite (last in LTR, first in RTL)
                            Logger.preview.debug("→ \(self.isRTL ? "First" : "Last") favorite (Ctrl+C)")
                            isRTL ? onJumpToFirstFavorite?() : onJumpToLastFavorite?()
                        } else {
                            Logger.preview.debug("→ Next favorite (c) triggered")
                            onNextFavorite?()
                        }
                    case "f":
                        Logger.preview.debug("→ FullScreen (f) triggered, calling onToggleFullScreen")
                        onToggleFullScreen?()
                    case "v":  // #55
                        Logger.preview.debug("→ Toggle single page (v) triggered")
                        onToggleSinglePage?()
                    // #72: Q - close (unified with Slide/Viewer)
                    case "q":
                        Logger.preview.debug("→ Close (q) triggered")
                        onClose?()
                    // #62 Phase 5: Shift+B = toggle bookmark list
                    case "b":
                        if hasShift {
                            Logger.preview.debug("→ Bookmark list (Shift+B) triggered")
                            onToggleBookmarkList?()
                        }
                    default:
                        Logger.preview.debug("→ Unhandled key, passing to super")
                        super.keyDown(with: event)
                    }
                } else {
                    Logger.preview.debug("→ No chars, passing to super")
                    super.keyDown(with: event)
                }
            }
        }
    }
}

#Preview {
    ImagePreviewView(
        imageSource: ArchiveManager(zipURL: URL(fileURLWithPath: "/tmp/test.zip")),
        entries: [],
        initialIndex: 0,
        favoriteIndices: [],
        onClose: {},
        onToggleFullScreen: {}
    )
}
