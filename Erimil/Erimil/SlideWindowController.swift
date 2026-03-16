//
//  SlideWindowController.swift
//  Erimil
//
//  Created for Phase 2.2 - Slide Mode
//  Session: S003 (2025-12-17)
//  Updated: S005 (2025-12-27) - Added source navigation (Ctrl+Arrow)
//  Updated: S008 (2025-01-09) - Centralized key handling for empty source support (#21)
//  Updated: S010 (2025-01-11) - Added source position indicator (#23)
//  Updated: S010 (2025-01-11) - Added Favorites Mode, f/x toggles (#23 continued)
//  Updated: S017 (2026-01-24) - Added W/S/↑/↓ key bindings (#53)
//  Updated: S017 (2026-01-24) - Resume last viewed position (#52)
//  Updated: S020 (2026-01-26) - Spread (two-page) view mode (#55)
//  Updated: S021 (2026-01-26) - Refactoring: SpreadImageViewer extracted to separate file (#67)
//  Updated: S026 (2026-01-30) - RTL navigation key inversion (#76)
//  Updated: S031 (2026-02-03) - Consolidated key handling (#72): Re-enabled Z/C with RTL support
//

import SwiftUI
import AppKit
import os

/// Controller for managing the Slide Mode fullscreen window
class SlideWindowController {
    
    static var shared = SlideWindowController()
    
    private var slideWindow: NSWindow?
    private var currentIndex: Int = 0
    // #154: Render gate — prevent rapid key repeat from skipping pages
    private var isNavigationGated: Bool = false
    private var imageReadyObserver: NSObjectProtocol?
    
    // #172: Auto-Slide / #178: Reverse Playback
    private var autoSlideMode: Int = 0  // 0=off, 1/2/3=forward Normal/Fast/Turbo, -1/-2/-3=reverse
    private let autoSlideTapHandler = AutoSlideTapHandler()
    private var autoSlideWaitingForImage: Bool = false
    
    // #201: Animation playback controller (shared with SpreadImageViewer)
    private let animationController = AnimationPlaybackController()
    
    /// Public getter for current index
    var getCurrentIndex: Int {
        return currentIndex
    }
    
    // S008: Event monitor for centralized key handling
    private var eventMonitor: Any?
    
    // S008: Callback storage for event monitor
    private var storedOnClose: (() -> Void)?
    private var storedOnNextSource: (() -> Void)?
    private var storedOnPreviousSource: (() -> Void)?
    private var storedOnSourceJump: ((Int) -> Void)?  // #143: N-step source navigation
    private var storedOnIndexChange: ((Int) -> Void)?
    private var storedOnExitToViewerMode: (() -> Void)?
    private var storedImageSource: (any ImageSource)?  // #54: For reading direction toggle
    private var storedEntries: [ImageEntry] = []
    private var storedFavoriteIndices: Set<Int> = []
    
    // S010: Source position info storage
    private var storedSourceName: String = ""
    private var storedSourcePosition: Int = 0
    private var storedTotalSources: Int = 0
    
    // S010: Favorite and selection callbacks
    private var storedOnToggleFavorite: ((Int) -> Void)?
    private var storedOnToggleSelection: ((Int) -> Void)?
    private var storedSelectedIndices: Set<Int> = []
    
    // S010: Favorites Mode state
    private var isFavoritesMode: Bool = false
    
    // #151: Overlay display level (persists across source switches)
    // 0=full (all controls+hints), 1=compact (nav bar only), 2=clean (indicators only)
    private var overlayLevel: Int = 0
    
    // #62 Phase 5: Bookmark list state
    private var showBookmarkList: Bool = false
    private var bookmarkListCursor: Int = 0
    
    // #145: Cursor auto-hide in Slide Mode
    private var mousePollingTimer: Timer?
    private var cursorHideTimer: DispatchWorkItem?
    private var isCursorHidden: Bool = false
    private let cursorHideDelay: TimeInterval = 3.0
    private var lastMouseLocation: NSPoint = .zero
    private weak var slideHostingView: NSView?  // #145: For cursor update control
    
    /// Transparent 1x1 cursor — immune to SwiftUI tracking area resets
    private lazy var transparentCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        return NSCursor(image: image, hotSpot: .zero)
    }()
    
    // #76: RTL navigation support
    private var isRTL: Bool {
        guard let source = storedImageSource else { return false }
        return CacheManager.shared.getEffectiveReadingDirection(for: source.url) == .rtl
    }
    
    private init() {}
    
    /// Open Slide Mode window with fullscreen
    func open(
        imageSource: any ImageSource,
        entries: [ImageEntry],
        initialIndex: Int,
        favoriteIndices: Set<Int>,
        selectedIndices: Set<Int> = [],
        sourceName: String = "",
        sourcePosition: Int = 0,
        totalSources: Int = 0,
        onClose: @escaping () -> Void,
        onIndexChange: ((Int) -> Void)? = nil,
        onNextSource: (() -> Void)? = nil,
        onPreviousSource: (() -> Void)? = nil,
        onSourceJump: ((Int) -> Void)? = nil,  // #143: N-step source navigation
        onToggleFavorite: ((Int) -> Void)? = nil,
        onToggleSelection: ((Int) -> Void)? = nil,
        onExitToViewerMode: (() -> Void)? = nil
    ) {
        Logger.slideWindow.debug("open() called")
        Logger.slideWindow.debug("entries.count: \(entries.count, privacy: .public), initialIndex: \(initialIndex, privacy: .public), favorites: \(favoriteIndices.count, privacy: .public)")
        Logger.slideWindow.debug("source: \(sourceName) (\(sourcePosition, privacy: .public)/\(totalSources, privacy: .public))")
        
        // Close existing window if any
        close()
        
        currentIndex = initialIndex
        isFavoritesMode = false
        showBookmarkList = false
        bookmarkListCursor = 0
        isNavigationGated = false  // #154 (reset on open, no delay needed)
        stopAutoSlide()  // #172: reset on open
        
        // #154: Listen for image ready signal to release navigation gate
        if let existing = imageReadyObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        imageReadyObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SlideWindowImageReady"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // #160: Hold gate for 1 frame min — prevents key-repeat from skipping pages on cache hit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                self.isNavigationGated = false
            }
            // #172: Auto-slide — schedule next advance after image is ready
            if self.autoSlideWaitingForImage {
                self.autoSlideWaitingForImage = false
                self.scheduleNextAutoSlideAdvance()
            }
        }
        
        // S008: Store callbacks and state for event monitor
        storedOnClose = onClose
        storedImageSource = imageSource  // #54
        storedOnNextSource = onNextSource
        storedOnPreviousSource = onPreviousSource
        storedOnSourceJump = onSourceJump  // #143
        storedOnIndexChange = onIndexChange
        storedEntries = entries
        storedFavoriteIndices = favoriteIndices
        
        // S010: Store source position info
        storedSourceName = sourceName
        storedSourcePosition = sourcePosition
        storedTotalSources = totalSources
        
        // S010: Store favorite/selection callbacks
        storedOnToggleFavorite = onToggleFavorite
        storedOnToggleSelection = onToggleSelection
        storedSelectedIndices = selectedIndices
        
        storedOnExitToViewerMode = onExitToViewerMode
        
        // Create the SwiftUI view
        let slideView = SlideWindowView(
            imageSource: imageSource,
            entries: entries,
            initialIndex: initialIndex,
            favoriteIndices: favoriteIndices,
            selectedIndices: selectedIndices,
            sourceName: sourceName,
            sourcePosition: sourcePosition,
            totalSources: totalSources,
            isFavoritesMode: isFavoritesMode,
            overlayLevel: overlayLevel,  // #151: Persist across source switches
            onClose: { [weak self] in
                Logger.slideWindow.debug("onClose callback triggered")
                self?.close()
                onClose()
            },
            onExitFullScreen: { [weak self] in
                Logger.slideWindow.debug("onExitFullScreen callback triggered")
                self?.close()
                onClose()
            },
            onIndexChange: { [weak self] index in
                self?.currentIndex = index
                onIndexChange?(index)
            },
            onNextSource: onNextSource,
            onPreviousSource: onPreviousSource,
            animationController: animationController  // #201
        )
        
        // Create hosting view (#145: subclass for cursor control)
        let hostingView = SlideHostingView(rootView: slideView)
        slideHostingView = hostingView
        
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hostingView
        window.title = "Slide Mode"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        
        // Center on screen
        window.center()
        
        Logger.slideWindow.info("Window created, making key and ordering front")
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        
        // Toggle to fullscreen after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Logger.slideWindow.debug("Toggling fullscreen...")
            window.toggleFullScreen(nil)
            // #145: Start mouse monitoring and hide cursor after fullscreen transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                self.setupMouseMonitor()
                self.hideCursor()
            }
        }
        
        slideWindow = window
        
        // S008: Register key event monitor
        setupEventMonitor()
        
        Logger.slideWindow.info("open() complete")
    }
    
    /// Close the Slide Mode window
    func close() {
        Logger.slideWindow.debug("close() called")
        
        // S008: Remove event monitor first
        removeEventMonitor()
        removeMouseMonitor()  // #145
        stopAutoSlide()  // #172
        slideHostingView = nil  // #145
        
        // #154: Remove image ready observer
        if let observer = imageReadyObserver {
            NotificationCenter.default.removeObserver(observer)
            imageReadyObserver = nil
        }
        
        // S008: Clear stored callbacks
        storedOnClose = nil
        storedImageSource = nil  // #54
        storedOnNextSource = nil
        storedOnPreviousSource = nil
        storedOnSourceJump = nil  // #143
        storedOnIndexChange = nil
        storedOnToggleFavorite = nil
        storedOnToggleSelection = nil
        storedOnExitToViewerMode = nil
        storedEntries = []
        storedFavoriteIndices = []
        storedSelectedIndices = []
        
        // S010: Clear source position info
        storedSourceName = ""
        storedSourcePosition = 0
        storedTotalSources = 0
        
        // S010: Reset favorites mode
        isFavoritesMode = false
        
        // #140: Close metadata inspector panel
        MetadataInspectorPanelController.shared.close()
        
        guard let window = slideWindow else {
            Logger.slideWindow.debug("No window to close")
            return
        }
        
        Logger.slideWindow.debug("Closing window immediately (isFullScreen: \(window.styleMask.contains(.fullScreen), privacy: .public))")
        
        // Clear content view to release SwiftUI hosting view
        window.contentView = nil
        
        // Hide the window instantly (regardless of fullscreen state)
        window.orderOut(nil)
        
        // Close the window
        window.close()
        
        // Release our reference
        slideWindow = nil
        
        Logger.slideWindow.info("Window closed and released")
    }
    
    /// Check if Slide Mode window is open
    var isOpen: Bool {
        slideWindow != nil
    }
    
    /// Update the source while keeping fullscreen state (S005)
    func updateSource(
        imageSource: any ImageSource,
        entries: [ImageEntry],
        favoriteIndices: Set<Int>,
        selectedIndices: Set<Int> = [],
        sourceName: String = "",
        sourcePosition: Int = 0,
        totalSources: Int = 0,
        onClose: @escaping () -> Void,
        onIndexChange: ((Int) -> Void)? = nil,
        onNextSource: (() -> Void)? = nil,
        onPreviousSource: (() -> Void)? = nil,
        onSourceJump: ((Int) -> Void)? = nil,  // #143
        onToggleFavorite: ((Int) -> Void)? = nil,
        onToggleSelection: ((Int) -> Void)? = nil,
        onExitToViewerMode: (() -> Void)? = nil
    ) {
        guard let window = slideWindow else {
            Logger.slideWindow.debug("updateSource: no window, falling back to open()")
            open(
                imageSource: imageSource,
                entries: entries,
                initialIndex: 0,
                favoriteIndices: favoriteIndices,
                selectedIndices: selectedIndices,
                sourceName: sourceName,
                sourcePosition: sourcePosition,
                totalSources: totalSources,
                onClose: onClose,
                onIndexChange: onIndexChange,
                onNextSource: onNextSource,
                onPreviousSource: onPreviousSource,
                onSourceJump: onSourceJump,
                onToggleFavorite: onToggleFavorite,
                onToggleSelection: onToggleSelection
            )
            return
        }
        
        Logger.slideWindow.debug("updateSource: updating content in-place")
        Logger.slideWindow.debug("new entries.count: \(entries.count, privacy: .public), favorites: \(favoriteIndices.count, privacy: .public)")
        Logger.slideWindow.debug("source: \(sourceName) (\(sourcePosition, privacy: .public)/\(totalSources, privacy: .public))")
        
        // #52: Restore last position for new source
        let startIndex: Int
        if !entries.isEmpty, let lastIndex = CacheManager.shared.getLastPosition(for: imageSource.url) {
            startIndex = min(lastIndex, entries.count - 1)
            Logger.slideWindow.info("Restored last position: \(startIndex, privacy: .public)")
        } else {
            startIndex = 0
        }
        
        // S008: Update stored state for event monitor
        currentIndex = startIndex
        isFavoritesMode = false  // Reset mode on source change
        showBookmarkList = false  // #62: Reset bookmark list on source change
        MetadataInspectorPanelController.shared.close()  // #140: Close inspector on source change
        stopAutoSlide()  // #172: reset on source change
        storedOnClose = onClose
        storedImageSource = imageSource  // #54
        storedOnNextSource = onNextSource
        storedOnPreviousSource = onPreviousSource
        storedOnSourceJump = onSourceJump  // #143
        storedOnIndexChange = onIndexChange
        storedEntries = entries
        storedFavoriteIndices = favoriteIndices
        
        // S010: Update source position info
        storedSourceName = sourceName
        storedSourcePosition = sourcePosition
        storedTotalSources = totalSources
        
        // S010: Update favorite/selection callbacks
        storedOnToggleFavorite = onToggleFavorite
        storedOnToggleSelection = onToggleSelection
        storedSelectedIndices = selectedIndices
        
        storedOnExitToViewerMode = onExitToViewerMode
        
        // Create new SwiftUI view with updated content
        let slideView = SlideWindowView(
            imageSource: imageSource,
            entries: entries,
            initialIndex: startIndex,  // #52: Start from last position
            favoriteIndices: favoriteIndices,
            selectedIndices: selectedIndices,
            sourceName: sourceName,
            sourcePosition: sourcePosition,
            totalSources: totalSources,
            isFavoritesMode: isFavoritesMode,
            overlayLevel: overlayLevel,  // #151: Persist across source switches
            onClose: { [weak self] in
                Logger.slideWindow.debug("onClose callback triggered")
                self?.close()
                onClose()
            },
            onExitFullScreen: { [weak self] in
                Logger.slideWindow.debug("onExitFullScreen callback triggered")
                self?.close()
                onClose()
            },
            onIndexChange: { [weak self] index in
                self?.currentIndex = index
                onIndexChange?(index)
            },
            onNextSource: onNextSource,
            onPreviousSource: onPreviousSource,
            animationController: animationController  // #201
        )
        
        // Replace content view while keeping window state (including fullscreen)
        let hostingView = SlideHostingView(rootView: slideView)
        hostingView.shouldHideCursor = isCursorHidden
        slideHostingView = hostingView  // #145
        window.contentView = hostingView
        
        Logger.slideWindow.debug("updateSource: content replaced, fullscreen maintained")
    }
    
    // MARK: - S010: Update favorite/selection state from external changes
    
    /// Update favorite indices (called when ThumbnailGrid changes favorites)
    func updateFavoriteIndices(_ indices: Set<Int>) {
        storedFavoriteIndices = indices
        notifyViewOfStateChange()
    }
    
    /// Update selected indices (called when ThumbnailGrid changes selections)
    func updateSelectedIndices(_ indices: Set<Int>) {
        storedSelectedIndices = indices
        notifyViewOfStateChange()
    }
    
    // MARK: - S008: Centralized Key Event Handling
    
    private func setupEventMonitor() {
        removeEventMonitor()  // Ensure no duplicate
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            guard self.slideWindow?.isKeyWindow == true else { return event }
            
            return self.handleKeyEvent(event)
        }
        
        Logger.slideWindow.debug("Event monitor registered")
    }
    
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            Logger.slideWindow.debug("Event monitor removed")
        }
    }
    
    // MARK: - #145: Cursor Auto-Hide
    
    private func setupMouseMonitor() {
        removeMouseMonitor()
        lastMouseLocation = NSEvent.mouseLocation
        
        // #145: Poll mouse position instead of event monitor
        // NSEvent.addLocalMonitorForEvents(.mouseMoved) is unreliable in fullscreen —
        // macOS generates phantom mouse events during SwiftUI view updates.
        // Polling at 0.2s interval avoids this entirely with minimal latency.
        mousePollingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let current = NSEvent.mouseLocation
            let dx = current.x - self.lastMouseLocation.x
            let dy = current.y - self.lastMouseLocation.y
            if dx * dx + dy * dy > 25.0 {  // 5px threshold
                self.lastMouseLocation = current
                self.showCursor()
                self.scheduleCursorHide()
            }
        }
        
        Logger.slideWindow.debug("Mouse polling started (#145)")
    }
    
    private func removeMouseMonitor() {
        mousePollingTimer?.invalidate()
        mousePollingTimer = nil
        cursorHideTimer?.cancel()
        cursorHideTimer = nil
        showCursor()
    }
    
    private func scheduleCursorHide() {
        cursorHideTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Logger.slideWindow.debug("#145: Timer fired → hideCursor")
            self?.hideCursor()
        }
        cursorHideTimer = work
        Logger.slideWindow.debug("#145: scheduleCursorHide — timer set (3.0s)")
        DispatchQueue.main.asyncAfter(deadline: .now() + cursorHideDelay, execute: work)
    }
    
    private func hideCursor() {
        guard !isCursorHidden else { return }
        transparentCursor.set()
        isCursorHidden = true
        lastMouseLocation = NSEvent.mouseLocation  // #145: Reset baseline to prevent immediate re-show
        // Notify hosting view to block cursorUpdate resets
        if let hostingView = slideHostingView as? SlideHostingView<SlideWindowView> {
            hostingView.shouldHideCursor = true
        }
        Logger.slideWindow.debug("#145: hideCursor — transparent cursor set")
    }
    
    private func showCursor() {
        guard isCursorHidden else { return }
        NSCursor.arrow.set()
        isCursorHidden = false
        if let hostingView = slideHostingView as? SlideHostingView<SlideWindowView> {
            hostingView.shouldHideCursor = false
        }
        Logger.slideWindow.debug("#145: showCursor — arrow cursor restored")
    }
    
    /// Re-apply transparent cursor (called from SlideHostingView.cursorUpdate)
    func reapplyTransparentCursor() {
        if isCursorHidden {
            transparentCursor.set()
        }
    }
    
    /// Handle key events centrally - returns nil to consume, event to pass through
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        hideCursor()  // #145: Hide cursor on any key navigation
        let hasControl = event.modifierFlags.contains(.control)
        let hasCommand = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)  // #62: Bookmark keys
        let hasOption = event.modifierFlags.contains(.option)  // #143: N-step navigation
        let hasCtrlOption = hasControl && hasOption  // #143: Ctrl+Option = N-step
        
        Logger.slideWindow.debug("handleKeyEvent: keyCode=\(event.keyCode, privacy: .public), ctrl=\(hasControl, privacy: .public), cmd=\(hasCommand, privacy: .public), shift=\(hasShift, privacy: .public), favMode=\(self.isFavoritesMode, privacy: .public)")
        
        // #62 Phase 5: Delegate keys to bookmark list when showing
        if showBookmarkList {
            guard let source = storedImageSource else { return nil }
            let bookmarks = CacheManager.shared.getBookmarks(for: source.url)
            let action = BookmarkListKeyHandler.handle(event: event, bookmarks: bookmarks, cursor: bookmarkListCursor)
            switch action {
            case .moveCursor(let newCursor):
                bookmarkListCursor = newCursor
                notifyViewOfBookmarkListChange()
            case .selectAndClose(let imageIndex):
                showBookmarkList = false
                notifyViewOfBookmarkListChange()
                jumpToIndex(min(imageIndex, storedEntries.count - 1))
                Logger.slideWindow.debug("Bookmark list → jump to \(imageIndex, privacy: .public)")
            case .close:
                showBookmarkList = false
                notifyViewOfBookmarkListChange()
            case .consumed:
                break
            }
            return nil
        }
        
        switch event.keyCode {
        // Escape - dismiss inspector panel OR close fullscreen
        case KeyCode.escape:
            if MetadataInspectorPanelController.shared.isVisible {
                Logger.slideWindow.debug("→ Close metadata inspector (Esc)")
                MetadataInspectorPanelController.shared.close()
            } else {
                Logger.slideWindow.debug("→ Close (Esc)")
                triggerClose()
            }
            return nil
            
        // Shift+Space - Reverse Auto-Slide (#178)
        case KeyCode.space where event.modifierFlags.contains(.shift):
            autoSlideTapHandler.handleShiftSpace(
                currentMode: autoSlideMode,
                start: { [weak self] mode in self?.startAutoSlide(mode: mode) },
                stop: { [weak self] in self?.stopAutoSlide() }
            )
            return nil

        // Space - Auto-Slide (#172; overlay toggle moved to O key) / Animation toggle (#201)
        case KeyCode.space:
            if animationController.hasAnimatedContent {
                animationController.togglePlay()
            } else {
                autoSlideTapHandler.handleSpace(
                    currentMode: autoSlideMode,
                    start: { [weak self] mode in self?.startAutoSlide(mode: mode) },
                    stop: { [weak self] in self?.stopAutoSlide() }
                )
            }
            return nil
            
        // Tab - next favorite + enter Favorites Mode
        case KeyCode.tab:
            Logger.slideWindow.debug("→ Next favorite + Favorites Mode ON (Tab)")
            if !isFavoritesMode {
                isFavoritesMode = true
                notifyViewOfModeChange()
            }
            goToNextFavorite()
            return nil
            
        // Left arrow
        case KeyCode.leftArrow:
            if hasCtrlOption {
                // #143: N-step file navigation (RTL-aware)
                jumpNStep(direction: .backward)
                return nil
            } else if hasControl {
                Logger.slideWindow.debug("→ Previous source (Ctrl+←)")
                storedOnPreviousSource?()
                return nil
            } else if isFavoritesMode {
                // #76: RTL inverts direction
                Logger.slideWindow.debug("→ \(self.isRTL ? "Next" : "Previous") favorite (← in Favorites Mode)")
                gatedNavigate { isRTL ? goToNextFavorite() : goToPreviousFavorite() }  // #154
                return nil
            } else {
                // #76: RTL inverts direction
                gatedNavigate { isRTL ? goToNext() : goToPrevious() }  // #154
                return nil
            }
            
        // Right arrow
        case KeyCode.rightArrow:
            if hasCtrlOption {
                // #143: N-step file navigation (RTL-aware)
                jumpNStep(direction: .forward)
                return nil
            } else if hasControl {
                Logger.slideWindow.debug("→ Next source (Ctrl+→)")
                storedOnNextSource?()
                return nil
            } else if isFavoritesMode {
                // #76: RTL inverts direction
                Logger.slideWindow.debug("→ \(self.isRTL ? "Previous" : "Next") favorite (→ in Favorites Mode)")
                gatedNavigate { isRTL ? goToPreviousFavorite() : goToNextFavorite() }  // #154
                return nil
            } else {
                // #76: RTL inverts direction
                gatedNavigate { isRTL ? goToPrevious() : goToNext() }  // #154
                return nil
            }
        
        // Up arrow - always previous (#106: vertical = direction-independent)
        case KeyCode.upArrow:
            if hasCtrlOption {
                // #143: N-step source navigation
                jumpNStepSource(direction: .backward)
                return nil
            } else if hasControl {
                Logger.slideWindow.debug("→ Previous source (Ctrl+↑)")
                storedOnPreviousSource?()
                return nil
            } else if isFavoritesMode {
                Logger.slideWindow.debug("→ Previous favorite (↑ in Favorites Mode)")
                gatedNavigate { goToPreviousFavorite() }  // #154
                return nil
            } else {
                gatedNavigate { goToPrevious() }  // #154
                return nil
            }
            
        // Down arrow - always next (#106: vertical = direction-independent)
        case KeyCode.downArrow:
            if hasCtrlOption {
                // #143: N-step source navigation
                jumpNStepSource(direction: .forward)
                return nil
            } else if hasControl {
                Logger.slideWindow.debug("→ Next source (Ctrl+↓)")
                storedOnNextSource?()
                return nil
            } else if isFavoritesMode {
                Logger.slideWindow.debug("→ Next favorite (↓ in Favorites Mode)")
                gatedNavigate { goToNextFavorite() }  // #154
                return nil
            } else {
                gatedNavigate { goToNext() }  // #154
                return nil
            }
        
        // R - exit to Viewer Mode (Reader)
        // #54: Ctrl+R = toggle reading direction
        case KeyCode.r:
            if hasControl {
                // Ctrl+R: Toggle reading direction
                if let source = storedImageSource {
                    let newDirection = CacheManager.shared.toggleReadingDirection(for: source.url)
                    notifyViewOfReadingDirectionChange()  // #150: Trigger view re-render
                    Logger.slideWindow.debug("Reading direction toggled to: \(newDirection.displayName, privacy: .public)")
                }
                return nil
            } else {
                Logger.slideWindow.debug("→ Exit to Viewer Mode (R)")
                if let exitToViewer = storedOnExitToViewerMode {
                    close()
                    exitToViewer()
                }
                return nil
            }
            
        default:
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "a":
                    if hasCtrlOption {
                        // #143: N-step file navigation (RTL-aware)
                        jumpNStep(direction: .backward)
                    } else if hasShift {
                        // #62: Shift+A = previous bookmark (RTL-aware)
                        if let source = storedImageSource,
                           let target = NavigationHelper.navigateBookmark(
                            direction: .backward, from: currentIndex,
                            sourceURL: source.url, isRTL: isRTL
                           ) {
                            Logger.slideWindow.debug("→ Shift+A → bookmark at \(target, privacy: .public)")
                            jumpToIndex(target)
                        }
                    } else if hasControl {
                        // #72: Ctrl+A = jump to visual left (start in LTR, end in RTL)
                        let target = isRTL ? storedEntries.count - 1 : 0
                        Logger.slideWindow.debug("→ Jump to \(self.isRTL ? "end" : "start") (Ctrl+A)")
                        jumpToIndex(target)
                    } else if isFavoritesMode {
                        // #76: RTL inverts direction
                        Logger.slideWindow.debug("→ \(self.isRTL ? "Next" : "Previous") favorite (A in Favorites Mode)")
                        gatedNavigate { isRTL ? goToNextFavorite() : goToPreviousFavorite() }  // #154
                    } else {
                        // #76: RTL inverts direction
                        gatedNavigate { isRTL ? goToNext() : goToPrevious() }  // #154
                    }
                    return nil
                    
                case "d":
                    if hasCtrlOption {
                        // #143: N-step file navigation (RTL-aware)
                        jumpNStep(direction: .forward)
                    } else if hasShift {
                        // #62: Shift+D = next bookmark (RTL-aware)
                        if let source = storedImageSource,
                           let target = NavigationHelper.navigateBookmark(
                            direction: .forward, from: currentIndex,
                            sourceURL: source.url, isRTL: isRTL
                           ) {
                            Logger.slideWindow.debug("→ Shift+D → bookmark at \(target, privacy: .public)")
                            jumpToIndex(target)
                        }
                    } else if hasCommand {
                        // #101: Cmd+D = toggle deskew
                        toggleDeskew()
                    } else if hasControl {
                        // #72: Ctrl+D = jump to visual right (end in LTR, start in RTL)
                        let target = isRTL ? 0 : storedEntries.count - 1
                        Logger.slideWindow.debug("→ Jump to \(self.isRTL ? "start" : "end") (Ctrl+D)")
                        jumpToIndex(target)
                    } else if isFavoritesMode {
                        // #76: RTL inverts direction
                        Logger.slideWindow.debug("→ \(self.isRTL ? "Previous" : "Next") favorite (D in Favorites Mode)")
                        gatedNavigate { isRTL ? goToPreviousFavorite() : goToNextFavorite() }  // #154
                    } else {
                        // #76: RTL inverts direction
                        gatedNavigate { isRTL ? goToPrevious() : goToNext() }  // #154
                    }
                    return nil
                
                // S017: W key (#106: vertical = direction-independent)
                case "w":
                    if hasCtrlOption {
                        // #143: N-step source navigation
                        jumpNStepSource(direction: .backward)
                    } else if hasControl {
                        Logger.slideWindow.debug("→ Previous source (Ctrl+W)")
                        storedOnPreviousSource?()
                    } else if isFavoritesMode {
                        Logger.slideWindow.debug("→ Previous favorite (W in Favorites Mode)")
                        gatedNavigate { goToPreviousFavorite() }  // #154
                    } else {
                        gatedNavigate { goToPrevious() }  // #154
                    }
                    return nil
                    
                // S017: S key (#106: vertical = direction-independent, #62: Shift+S = bookmark)
                case "s":
                    if hasCtrlOption {
                        // #143: N-step source navigation
                        jumpNStepSource(direction: .forward)
                    } else if hasShift {
                        // #62: Shift+S = add/delete bookmark at current position
                        if let source = storedImageSource, currentIndex < storedEntries.count {
                            let entry = storedEntries[currentIndex]
                            let defaultName = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
                            BookmarkDialogHelper.handleShiftS(
                                sourceURL: source.url,
                                imageIndex: currentIndex,
                                defaultName: defaultName,
                                window: slideWindow
                            )
                        }
                    } else if hasControl {
                        Logger.slideWindow.debug("→ Next source (Ctrl+S)")
                        storedOnNextSource?()
                    } else if isFavoritesMode {
                        Logger.slideWindow.debug("→ Next favorite (S in Favorites Mode)")
                        gatedNavigate { goToNextFavorite() }  // #154
                    } else {
                        gatedNavigate { goToNext() }  // #154
                    }
                    return nil
                
                // #62 Phase 5: Shift+B = toggle bookmark list overlay
                case "b":
                    if hasShift {
                        if let source = storedImageSource {
                            let bookmarks = CacheManager.shared.getBookmarks(for: source.url)
                            showBookmarkList = true
                            if let nearest = bookmarks.enumerated().min(by: {
                                abs($0.element.imageIndex - currentIndex) < abs($1.element.imageIndex - currentIndex)
                            }) {
                                bookmarkListCursor = nearest.offset
                            } else {
                                bookmarkListCursor = 0
                            }
                            notifyViewOfBookmarkListChange()
                            Logger.slideWindow.debug("Shift+B → bookmark list (\(bookmarks.count, privacy: .public) bookmarks)")
                        }
                        return nil
                    }
                
                // #72: Cmd+1-5 = jump to percentage position (RTL-aware, Cmd to avoid system shortcut conflict)
                case "1":
                    if hasCommand {
                        let percent = isRTL ? 100 : 0
                        Logger.slideWindow.debug("→ Jump to \(percent, privacy: .public)% (Cmd+1)")
                        jumpToIndex(NavigationHelper.indexForPercent(percent, totalCount: storedEntries.count))
                        return nil
                    }
                case "2":
                    if hasCommand {
                        let percent = isRTL ? 75 : 25
                        Logger.slideWindow.debug("→ Jump to \(percent, privacy: .public)% (Cmd+2)")
                        jumpToIndex(NavigationHelper.indexForPercent(percent, totalCount: storedEntries.count))
                        return nil
                    }
                case "3":
                    if hasCommand {
                        Logger.slideWindow.debug("→ Jump to 50% (Cmd+3)")
                        jumpToIndex(NavigationHelper.indexForPercent(50, totalCount: storedEntries.count))
                        return nil
                    }
                case "4":
                    if hasCommand {
                        let percent = isRTL ? 25 : 75
                        Logger.slideWindow.debug("→ Jump to \(percent, privacy: .public)% (Cmd+4)")
                        jumpToIndex(NavigationHelper.indexForPercent(percent, totalCount: storedEntries.count))
                        return nil
                    }
                case "5":
                    if hasCommand {
                        let percent = isRTL ? 0 : 100
                        Logger.slideWindow.debug("→ Jump to \(percent, privacy: .public)% (Cmd+5)")
                        jumpToIndex(NavigationHelper.indexForPercent(percent, totalCount: storedEntries.count))
                        return nil
                    }
                    
                case "f":
                    // S010: Toggle favorite (not exit fullscreen anymore)
                    Logger.slideWindow.debug("→ Toggle favorite (F)")
                    toggleFavorite()
                    return nil
                    
                case "x":
                    // S010: Toggle selection
                    Logger.slideWindow.debug("→ Toggle selection (X)")
                    toggleSelection()
                    return nil
                    
                case "q":
                    // #172/#178: Auto-Slide running → stop only
                    if autoSlideMode != 0 {
                        Logger.slideWindow.debug("→ Auto-slide stop (Q)")
                        stopAutoSlide()
                        return nil
                    }
                    // S010: Exit Favorites Mode OR close fullscreen
                    if isFavoritesMode {
                        Logger.slideWindow.debug("→ Exit Favorites Mode (Q)")
                        isFavoritesMode = false
                        notifyViewOfModeChange()
                    } else {
                        Logger.slideWindow.debug("→ Close fullscreen (Q)")
                        triggerClose()
                    }
                    return nil
                
                case "v":
                    // #55: Toggle single page marker (#111: spread-aware)
                    if let source = storedImageSource {
                        let isInSpread: Bool = {
                            guard AppSettings.shared.isSpreadModeEnabled,
                                  currentIndex + 1 < storedEntries.count else { return false }
                            return !SpreadNavigationHelper.shouldShowSinglePage(
                                for: source.url, at: currentIndex,
                                totalCount: storedEntries.count, entries: storedEntries
                            )
                        }()
                        let target = CacheManager.shared.spreadAwareToggleTarget(for: source.url, at: currentIndex, isInSpread: isInSpread)
                        let added = CacheManager.shared.toggleSinglePageMarker(for: source.url, at: target)
                        Logger.slideWindow.debug("Single page marker at \(target, privacy: .public) (from \(self.currentIndex, privacy: .public), spread: \(isInSpread, privacy: .public)): \(added ? "ON" : "OFF")")
                        notifyViewOfSpreadChange()
                    }
                    return nil
                
                // #151: P - toggle PDF Deskew (alias for ⌘D)
                case "p":
                    Logger.slideWindow.debug("→ Toggle deskew (P)")
                    toggleDeskew()
                    return nil
                
                // #72: Z - previous favorite (RTL-aware), Ctrl+Z - first/last favorite (RTL-aware)
                case "z":
                    if hasCtrlOption {
                        // #143: N-step favorite navigation (RTL-aware)
                        jumpNStepFavorite(direction: .backward)
                    } else if hasControl {
                        // Ctrl+Z = jump to visual left favorite (first in LTR, last in RTL)
                        let targetFav = isRTL ? storedFavoriteIndices.max() : storedFavoriteIndices.min()
                        if let fav = targetFav {
                            Logger.slideWindow.debug("→ \(self.isRTL ? "Last" : "First") favorite (Ctrl+Z) at \(fav)")
                            jumpToIndex(fav)
                        }
                    } else {
                        Logger.slideWindow.debug("→ \(self.isRTL ? "Next" : "Previous") favorite (Z)")
                        gatedNavigate { isRTL ? goToNextFavorite() : goToPreviousFavorite() }  // #154
                    }
                    return nil
                    
                // #72: C - next favorite (RTL-aware), Ctrl+C - last/first favorite (RTL-aware)
                case "c":
                    if hasCtrlOption {
                        // #143: N-step favorite navigation (RTL-aware)
                        jumpNStepFavorite(direction: .forward)
                    } else if hasControl {
                        // Ctrl+C = jump to visual right favorite (last in LTR, first in RTL)
                        let targetFav = isRTL ? storedFavoriteIndices.min() : storedFavoriteIndices.max()
                        if let fav = targetFav {
                            Logger.slideWindow.debug("→ \(self.isRTL ? "First" : "Last") favorite (Ctrl+C) at \(fav)")
                            jumpToIndex(fav)
                        }
                    } else {
                        Logger.slideWindow.debug("→ \(self.isRTL ? "Previous" : "Next") favorite (C)")
                        gatedNavigate { isRTL ? goToPreviousFavorite() : goToNextFavorite() }  // #154
                    }
                    return nil
                    
                // #101: Cmd+[ = nudge deskew angle -0.1°, Cmd+] = nudge +0.1°
                //       Cmd+Shift+[/] = adjust visual RIGHT page in spread
                case "[", "{":
                    if hasCommand {
                        nudgeDeskewAngle(by: -0.1, targetRight: hasShift)
                    }
                    return nil
                case "]", "}":
                    if hasCommand {
                        nudgeDeskewAngle(by: 0.1, targetRight: hasShift)
                    }
                    return nil
                
                // #172: O key - toggle controls overlay (moved from Space)
                case "o":
                    Logger.slideWindow.debug("→ Toggle controls (O)")
                    notifyViewOfControlsToggle()
                    return nil
                
                // #140: Toggle metadata inspector panel
                case "i":
                    if currentIndex < storedEntries.count {
                        MetadataInspectorPanelController.shared.toggle(
                            imageSource: storedImageSource,
                            entry: storedEntries[currentIndex],
                            parentWindow: slideWindow
                        )
                    }
                    return nil
                    
                // L - toggle animation loop (#201)
                case "l":
                    if animationController.hasAnimatedContent {
                        animationController.toggleLoop()
                    }
                    return nil
                    
                default:
                    return event  // Pass through unhandled
                }
            }
            return event
        }
    }
    
    private func triggerClose() {
        let callback = storedOnClose
        close()
        callback?()
    }
    
    // MARK: - S008: Navigation (#67: Simple ±1 navigation)
    // Note: Spread-aware navigation deferred due to wide image detection complexity.
    // SpreadImageViewer handles display, navigation is always ±1.
    
    private func goToPrevious() {
        guard !storedEntries.isEmpty else { return }
        Logger.slideWindow.debug("goToPrevious called, current: \(self.currentIndex, privacy: .public)")
        
        guard currentIndex > 0 || AppSettings.shared.loopWithinSource else { return }
        
        // #67 Phase 3: Try to determine step using cached aspect ratios
        if currentIndex >= 2, let source = storedImageSource {
            let prevIndex = currentIndex - 2
            let wouldBeSingle = SpreadNavigationHelper.shouldShowSinglePage(
                for: source.url,
                at: prevIndex,
                totalCount: storedEntries.count,
                entries: storedEntries
            )
            
            if !wouldBeSingle {
                Logger.slideWindow.debug("goToPrevious: cached spread at \(prevIndex, privacy: .public), stepping -2")
                currentIndex = prevIndex
                storedOnIndexChange?(currentIndex)
                notifyViewOfIndexChange()
                return
            }
        }
        
        // Fallback: step -1
        if currentIndex > 0 {
            currentIndex -= 1
            Logger.slideWindow.debug("→ new index: \(self.currentIndex, privacy: .public)")
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        } else if AppSettings.shared.loopWithinSource {
            currentIndex = storedEntries.count - 1
            Logger.slideWindow.debug("→ looped to: \(self.currentIndex, privacy: .public)")
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        }
    }

    
    private func goToNext() {
        guard !storedEntries.isEmpty else { return }
        Logger.slideWindow.debug("goToNext called, current: \(self.currentIndex, privacy: .public)")
        
        // #67: Calculate step using cached aspect ratios
        var step = 1
        if let source = storedImageSource {
            let isSingle = SpreadNavigationHelper.shouldShowSinglePage(
                for: source.url,
                at: currentIndex,
                totalCount: storedEntries.count,
                entries: storedEntries
            )
            step = isSingle ? 1 : 2
            Logger.slideWindow.debug("goToNext: step = \(step, privacy: .public) (single: \(isSingle, privacy: .public))")
        }
        
        let nextIndex = currentIndex + step
        if nextIndex < storedEntries.count {
            currentIndex = nextIndex
            Logger.slideWindow.debug("→ new index: \(self.currentIndex, privacy: .public)")
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        } else if currentIndex < storedEntries.count - 1 {
            // Step would overshoot but there's still a page - go to last
            currentIndex = storedEntries.count - 1
            Logger.slideWindow.debug("→ last page: \(self.currentIndex, privacy: .public)")
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        } else if AppSettings.shared.loopWithinSource {
            currentIndex = 0
            Logger.slideWindow.debug("→ looped to: \(self.currentIndex, privacy: .public)")
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        }
    }
    
    /// #154: Navigate with render gate — ensures each page displays at least one frame
    private func gatedNavigate(_ action: () -> Void) {
        guard !isNavigationGated else { return }
        let before = currentIndex
        action()
        if currentIndex != before { isNavigationGated = true }
    }
    
    private func goToPreviousFavorite() {
        // #14: Unified favorite navigation via NavigationHelper
        guard let source = storedImageSource,
              let targetIndex = NavigationHelper.previousFavoriteIndexSpreadAware(
                from: currentIndex,
                favoriteIndices: storedFavoriteIndices,
                sourceURL: source.url,
                entries: storedEntries,
                wrap: AppSettings.shared.loopWithinSource
              ) else { return }
        
        currentIndex = targetIndex
        storedOnIndexChange?(currentIndex)
        notifyViewOfIndexChange()
    }
    
    private func goToNextFavorite() {
        // #14: Unified favorite navigation via NavigationHelper
        guard let source = storedImageSource else { return }
        
        let isShowingSpread: Bool = {
            guard AppSettings.shared.isSpreadModeEnabled,
                  currentIndex + 1 < storedEntries.count else { return false }
            return !SpreadNavigationHelper.shouldShowSinglePage(
                for: source.url, at: currentIndex,
                totalCount: storedEntries.count, entries: storedEntries
            )
        }()
        
        guard let targetIndex = NavigationHelper.nextFavoriteIndexSpreadAware(
            from: currentIndex,
            favoriteIndices: storedFavoriteIndices,
            sourceURL: source.url,
            entries: storedEntries,
            isShowingSpread: isShowingSpread,
            wrap: AppSettings.shared.loopWithinSource
        ) else { return }
        
        currentIndex = targetIndex
        storedOnIndexChange?(currentIndex)
        notifyViewOfIndexChange()
    }
    
    // #72: Jump to specific index (for Ctrl+A/D, Ctrl+1-5)
    private func jumpToIndex(_ index: Int) {
        guard !storedEntries.isEmpty else { return }
        let targetIndex = min(max(0, index), storedEntries.count - 1)
        guard targetIndex != currentIndex else { return }
        
        currentIndex = targetIndex
        Logger.slideWindow.debug("→ jumped to: \(self.currentIndex, privacy: .public)")
        storedOnIndexChange?(currentIndex)
        notifyViewOfIndexChange()
    }
    
    // MARK: - #143: N-Step Navigation
    
    /// Jump N files forward/backward (Ctrl+Option+A/D/←/→)
    private func jumpNStep(direction: NavigationDirection) {
        let step = AppSettings.shared.navigationStepCount
        if let target = NavigationHelper.navigateNStep(
            direction: direction, from: currentIndex,
            totalCount: storedEntries.count, stepCount: step, isRTL: isRTL
        ) {
            Logger.slideWindow.debug("→ N-step(\(step)) \(direction == .forward ? "fwd" : "bwd") → \(target, privacy: .public)")
            jumpToIndex(target)
        }
    }
    
    /// Jump N favorites forward/backward (Ctrl+Option+Z/C)
    private func jumpNStepFavorite(direction: NavigationDirection) {
        let step = AppSettings.shared.navigationStepCount
        if let target = NavigationHelper.navigateFavoriteNStep(
            direction: direction, from: currentIndex,
            favoriteIndices: storedFavoriteIndices, stepCount: step, isRTL: isRTL
        ) {
            Logger.slideWindow.debug("→ N-step fav(\(step)) \(direction == .forward ? "fwd" : "bwd") → \(target, privacy: .public)")
            jumpToIndex(target)
        }
    }
    
    /// Jump N sources forward/backward (Ctrl+Option+W/S/↑/↓)
    private func jumpNStepSource(direction: NavigationDirection) {
        guard let source = storedImageSource else { return }
        let step = AppSettings.shared.navigationStepCount
        let steps = direction == .forward ? step : -step
        
        if storedOnSourceJump != nil {
            Logger.slideWindow.debug("→ N-step source(\(step)) \(direction == .forward ? "fwd" : "bwd")")
            storedOnSourceJump?(steps)
        } else {
            Logger.slideWindow.debug("→ N-step source: no jump callback, falling back to single step")
            if direction == .forward {
                storedOnNextSource?()
            } else {
                storedOnPreviousSource?()
            }
        }
    }
    
    // MARK: - S010: Favorite and Selection Toggles
    
    private func toggleFavorite() {
        guard !storedEntries.isEmpty, currentIndex >= 0, currentIndex < storedEntries.count else { return }
        
        // #104: Determine if currently showing spread
        let partnerIndex: Int? = {
            guard AppSettings.shared.isSpreadModeEnabled,
                  let source = storedImageSource else { return nil }
            let isSingle = SpreadNavigationHelper.shouldShowSinglePage(
                for: source.url,
                at: currentIndex,
                totalCount: storedEntries.count,
                entries: storedEntries
            )
            if !isSingle, currentIndex + 1 < storedEntries.count {
                return currentIndex + 1
            }
            return nil
        }()
        
        // Determine direction based on leading page
        let isAdding = !storedFavoriteIndices.contains(currentIndex)
        
        // Toggle leading page in local state
        if isAdding {
            storedFavoriteIndices.insert(currentIndex)
        } else {
            storedFavoriteIndices.remove(currentIndex)
        }
        storedOnToggleFavorite?(currentIndex)
        
        // #104: Toggle partner if spread (only if state needs to change)
        if let partner = partnerIndex {
            let partnerHasFavorite = storedFavoriteIndices.contains(partner)
            if isAdding != partnerHasFavorite {
                if isAdding {
                    storedFavoriteIndices.insert(partner)
                } else {
                    storedFavoriteIndices.remove(partner)
                }
                storedOnToggleFavorite?(partner)
            }
        }
        
        // Update view
        notifyViewOfStateChange()
    }
    
    private func toggleSelection() {
        guard !storedEntries.isEmpty, currentIndex >= 0, currentIndex < storedEntries.count else { return }
        
        // Toggle in local state
        if storedSelectedIndices.contains(currentIndex) {
            storedSelectedIndices.remove(currentIndex)
        } else {
            storedSelectedIndices.insert(currentIndex)
        }
        
        // Notify ThumbnailGrid via callback
        storedOnToggleSelection?(currentIndex)
        
        // Update view
        notifyViewOfStateChange()
    }
    
    // MARK: - #101: Deskew Toggle
    
    private func toggleDeskew() {
        guard let source = storedImageSource else { return }
        
        // Only meaningful for PDF sources
        guard source.sourceType == .pdf else {
            Logger.slideWindow.debug("Deskew: not a PDF source, ignoring")
            return
        }
        
        let enabled = CacheManager.shared.toggleDeskew(for: source.url)
        Logger.slideWindow.info("Deskew toggled: \(enabled ? "ON" : "OFF") for \(source.url.lastPathComponent)")
        
        // Notify view to refresh (re-render with or without correction)
        notifyViewOfDeskewChange(enabled: enabled)
    }
    
    private func notifyViewOfDeskewChange(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowDeskewChanged"),
            object: nil,
            userInfo: ["deskewEnabled": enabled]
        )
    }
    
    /// Nudge the deskew angle for a page by a given degree offset (#101)
    /// - Parameters:
    ///   - degrees: Angle adjustment in degrees (+/-)
    ///   - targetRight: If true, targets the visual RIGHT page in spread mode
    private func nudgeDeskewAngle(by degrees: CGFloat, targetRight: Bool = false) {
        guard let source = storedImageSource, source.sourceType == .pdf else { return }
        guard currentIndex < storedEntries.count else { return }
        
        // Determine if currently showing spread
        let isCurrentSpread: Bool = {
            guard AppSettings.shared.isSpreadModeEnabled,
                  currentIndex + 1 < storedEntries.count else { return false }
            return !SpreadNavigationHelper.shouldShowSinglePage(
                for: source.url, at: currentIndex,
                totalCount: storedEntries.count, entries: storedEntries
            )
        }()
        
        // RTL-aware page targeting for spread
        // In spread: LTR left=currentIndex, right=currentIndex+1
        //            RTL left=currentIndex+1, right=currentIndex (HStack reverses)
        // adjustPartner = targetRight XOR isRTL
        let adjustPartner = (targetRight != isRTL)
        let targetIndex = (isCurrentSpread && adjustPartner && currentIndex + 1 < storedEntries.count)
            ? currentIndex + 1
            : currentIndex
        
        let entryPath = storedEntries[targetIndex].path
        
        // Auto-enable deskew if not already on
        if !CacheManager.shared.isDeskewEnabled(for: source.url) {
            _ = CacheManager.shared.toggleDeskew(for: source.url)
            notifyViewOfDeskewChange(enabled: true)
        }
        
        let step = degrees * CGFloat.pi / 180.0
        let currentAngle = CacheManager.shared.getDeskewAngle(for: source.url, entryPath: entryPath) ?? 0.0
        let newAngle = currentAngle + step
        CacheManager.shared.setDeskewAngle(for: source.url, entryPath: entryPath, angle: newAngle)
        
        // Force reload via spread change notification
        notifyViewOfSpreadChange()
        Logger.slideWindow.debug("Deskew nudge \(degrees > 0 ? "+" : "")\(degrees, privacy: .public)° page[\(targetIndex, privacy: .public)] → \(newAngle * 180 / CGFloat.pi, privacy: .public)°")
    }
    
    // MARK: - #172: Auto-Slide
    
    private func startAutoSlide(mode: Int) {
        autoSlideMode = mode
        autoSlideWaitingForImage = false
        notifyViewOfAutoSlideChange()
        scheduleNextAutoSlideAdvance()
        Logger.slideWindow.debug("Auto-slide started: mode=\(mode)")
    }
    
    private func stopAutoSlide() {
        guard autoSlideMode != 0 || autoSlideTapHandler.hasPendingTaps else { return }
        autoSlideMode = 0
        autoSlideTapHandler.reset()
        autoSlideWaitingForImage = false
        notifyViewOfAutoSlideChange()
        Logger.slideWindow.debug("Auto-slide stopped")
    }
    
    private func scheduleNextAutoSlideAdvance() {
        guard autoSlideMode != 0 else { return }
        let interval: TimeInterval
        switch abs(autoSlideMode) {
        case 1:  interval = AppSettings.shared.autoSlideIntervalNormal
        case 2:  interval = AppSettings.shared.autoSlideIntervalFast
        default: interval = AppSettings.shared.autoSlideIntervalTurbo
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.advanceAutoSlide()
        }
    }
    
    private func advanceAutoSlide() {
        guard autoSlideMode != 0 else { return }
        let before = currentIndex
        let isReverse = autoSlideMode < 0
        // Fav Mode 中は★のみ進む
        if isFavoritesMode {
            if isReverse { goToPreviousFavorite() } else { goToNextFavorite() }
        } else {
            if isReverse { goToPrevious() } else { goToNext() }
        }
        if currentIndex == before {
            // End of source (forward) or start of source (reverse)
            if AppSettings.shared.autoSlideLoops {
                if isFavoritesMode {
                    let sorted = storedFavoriteIndices.sorted()
                    if let target = isReverse ? sorted.last : sorted.first {
                        currentIndex = target
                        notifyViewOfIndexChange()
                        Logger.slideWindow.debug("Auto-slide: loop to \(isReverse ? "last" : "first") favorite (\(target))")
                    } else {
                        stopAutoSlide(); return
                    }
                } else {
                    let target = isReverse ? storedEntries.count - 1 : 0
                    currentIndex = target
                    notifyViewOfIndexChange()
                    Logger.slideWindow.debug("Auto-slide: loop to \(isReverse ? "end" : "start")")
                }
            } else {
                Logger.slideWindow.debug("Auto-slide: boundary reached, stopping")
                stopAutoSlide()
                return
            }
        }
        autoSlideWaitingForImage = true
        // Next advance scheduled via imageReadyObserver on SlideWindowImageReady
    }
    
    private func notifyViewOfAutoSlideChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowAutoSlideChanged"),
            object: nil,
            userInfo: ["autoSlideMode": autoSlideMode]
        )
    }
    
    // MARK: - Notifications
    
    /// Notify the view of index change via NotificationCenter
    private func notifyViewOfIndexChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowIndexChanged"),
            object: nil,
            userInfo: ["index": currentIndex]
        )
        
        // #140: Update metadata inspector panel if visible
        if MetadataInspectorPanelController.shared.isVisible,
           currentIndex < storedEntries.count {
            MetadataInspectorPanelController.shared.update(
                imageSource: storedImageSource,
                entry: storedEntries[currentIndex]
            )
        }
    }
    
    /// Notify the view of mode change via NotificationCenter
    private func notifyViewOfModeChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowModeChanged"),
            object: nil,
            userInfo: ["isFavoritesMode": isFavoritesMode]
        )
    }
    
    /// Notify the view of state change (favorites/selections) via NotificationCenter
    private func notifyViewOfStateChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowStateChanged"),
            object: nil,
            userInfo: [
                "favoriteIndices": storedFavoriteIndices,
                "selectedIndices": storedSelectedIndices
            ]
        )
    }
    
    /// Notify the view of reading direction change via NotificationCenter (#150)
    private func notifyViewOfReadingDirectionChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowReadingDirectionChanged"),
            object: nil
        )
    }
    
    /// Notify the view to cycle overlay level via NotificationCenter (#151)
    private func notifyViewOfControlsToggle() {
        overlayLevel = (overlayLevel + 1) % 3  // #151: Full(0) → Compact(1) → Clean(2) → Full(0)
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowControlsToggle"),
            object: nil,
            userInfo: ["overlayLevel": overlayLevel]
        )
    }
    
    /// Notify the view of spread layout change via NotificationCenter (#55)
    private func notifyViewOfSpreadChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowSpreadChanged"),
            object: nil
        )
    }
    
    /// Notify the view of bookmark list state change via NotificationCenter (#62 Phase 5)
    private func notifyViewOfBookmarkListChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowBookmarkListChanged"),
            object: nil,
            userInfo: [
                "show": showBookmarkList,
                "cursor": bookmarkListCursor
            ]
        )
    }
    
}

// MARK: - Slide Window View

/// The view displayed in the Slide Mode fullscreen window
struct SlideWindowView: View {
    let imageSource: any ImageSource
    let entries: [ImageEntry]
    let initialIndex: Int
    let initialFavoriteIndices: Set<Int>
    let initialSelectedIndices: Set<Int>
    let sourceName: String
    let sourcePosition: Int
    let totalSources: Int
    let initialIsFavoritesMode: Bool
    let initialOverlayLevel: Int  // #151: 0=full, 1=compact, 2=clean
    let onClose: () -> Void
    let onExitFullScreen: () -> Void
    let onIndexChange: ((Int) -> Void)?
    let onNextSource: (() -> Void)?
    let onPreviousSource: (() -> Void)?
    let animationController: AnimationPlaybackController  // #201
    
    @State private var currentIndex: Int = 0
    @State private var overlayLevel: Int = 0  // #151: 0=full, 1=compact, 2=clean
    @State private var isFavoritesMode: Bool = false
    @State private var favoriteIndices: Set<Int> = []
    @State private var selectedIndices: Set<Int> = []
    
    // #62 Phase 5: Bookmark list overlay state
    @State private var showBookmarkList: Bool = false
    @State private var bookmarkListCursor: Int = 0
    
    // #101: Deskew state
    @State private var isDeskewEnabled: Bool = false
    
    // #115: Track spread display state for position indicator
    @State private var isShowingSpread: Bool = false
    
    // #150: Reading direction re-render trigger
    @State private var readingDirectionVersion: Int = 0
    
    // #172: Auto-Slide display state
    @State private var autoSlideMode: Int = 0
    
    /// #150: Effective reading direction (re-evaluated on readingDirectionVersion change)
    private var effectiveReadingDirection: ReadingDirection {
        _ = readingDirectionVersion
        return CacheManager.shared.getEffectiveReadingDirection(for: imageSource.url)
    }
    
    // #54: Effective reading direction
    private var isRTL: Bool {
        effectiveReadingDirection == .rtl
    }
    
    init(
        imageSource: any ImageSource,
        entries: [ImageEntry],
        initialIndex: Int,
        favoriteIndices: Set<Int>,
        selectedIndices: Set<Int>,
        sourceName: String,
        sourcePosition: Int,
        totalSources: Int,
        isFavoritesMode: Bool,
        overlayLevel: Int = 0,
        onClose: @escaping () -> Void,
        onExitFullScreen: @escaping () -> Void,
        onIndexChange: ((Int) -> Void)?,
        onNextSource: (() -> Void)?,
        onPreviousSource: (() -> Void)?,
        animationController: AnimationPlaybackController  // #201
    ) {
        self.imageSource = imageSource
        self.entries = entries
        self.initialIndex = initialIndex
        self.initialFavoriteIndices = favoriteIndices
        self.initialSelectedIndices = selectedIndices
        self.sourceName = sourceName
        self.sourcePosition = sourcePosition
        self.totalSources = totalSources
        self.initialIsFavoritesMode = isFavoritesMode
        self.initialOverlayLevel = overlayLevel
        self._overlayLevel = State(initialValue: overlayLevel)  // #151: Direct State init
        self.onClose = onClose
        self.onExitFullScreen = onExitFullScreen
        self.onIndexChange = onIndexChange
        self.onNextSource = onNextSource
        self.onPreviousSource = onPreviousSource
        self.animationController = animationController  // #201
    }
    
    var body: some View {
        ZStack {
            // S008: Handle empty source
            if entries.isEmpty {
                emptySourceView
            } else {
                // #55/#67: Spread-aware image viewer (now from separate file)
                SpreadImageViewer(
                    imageSource: imageSource,
                    entries: entries,
                    currentIndex: $currentIndex,
                    favoriteIndices: favoriteIndices,
                    reloadTrigger: isDeskewEnabled,  // #101: Force reload when deskew changes
                    isShowingSpread: $isShowingSpread,  // #115: Track for position indicator
                    couldBeSpreadWithPrevious: .constant(false),
                    animationController: animationController,  // #201
                    onImageReady: { _ in  // #154: Release navigation gate
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SlideWindowImageReady"),
                            object: nil
                        )
                    }
                )
                .environment(\.layoutDirection, effectiveReadingDirection.layoutDirection)  // #150: RTL spread inversion
            }
            
            // #151: Controls overlay — always visible, hints togglable with Space
            controlsOverlay
            
            // #62 Phase 5: Bookmark list overlay
            if showBookmarkList {
                BookmarkListOverlayView(
                    bookmarks: CacheManager.shared.getBookmarks(for: imageSource.url),
                    selectedCursor: bookmarkListCursor,
                    onSelect: { imageIndex in
                        // Close overlay and jump (controller handles via notification)
                        showBookmarkList = false
                        currentIndex = min(imageIndex, entries.count - 1)
                        Logger.slideWindow.debug("Bookmark list click → jump to \(imageIndex, privacy: .public)")
                    },
                    onClose: { showBookmarkList = false }
                )
            }
            
            // Key event handler (supplementary - main handling in Controller)
            SlideKeyHandler(
                onClose: onClose,
                onPrevious: { /* handled by controller */ },
                onNext: { /* handled by controller */ },
                onPreviousFavorite: { /* handled by controller */ },
                onNextFavorite: { /* handled by controller */ },
                onExitFullScreen: onExitFullScreen,
                onToggleControls: { /* #151: Space now handled by controller */ },
                onNextSource: onNextSource,
                onPreviousSource: onPreviousSource
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            currentIndex = initialIndex
            isFavoritesMode = initialIsFavoritesMode
            overlayLevel = initialOverlayLevel  // #151: Restore from controller
            favoriteIndices = initialFavoriteIndices
            selectedIndices = initialSelectedIndices
            isDeskewEnabled = CacheManager.shared.isDeskewEnabled(for: imageSource.url)  // #101
        }
        .onChange(of: currentIndex) { _, newIndex in
            onIndexChange?(newIndex)
        }
        // S008: Listen for index changes from controller
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlideWindowIndexChanged"))) { notification in
            if let index = notification.userInfo?["index"] as? Int {
                currentIndex = index
            }
        }
        // S010: Listen for mode changes from controller
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlideWindowModeChanged"))) { notification in
            if let mode = notification.userInfo?["isFavoritesMode"] as? Bool {
                isFavoritesMode = mode
            }
        }
        // S010: Listen for state changes from controller
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlideWindowStateChanged"))) { notification in
            if let favs = notification.userInfo?["favoriteIndices"] as? Set<Int> {
                favoriteIndices = favs
            }
            if let sels = notification.userInfo?["selectedIndices"] as? Set<Int> {
                selectedIndices = sels
            }
        }
        // #62 Phase 5: Listen for bookmark list changes from controller
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlideWindowBookmarkListChanged"))) { notification in
            if let show = notification.userInfo?["show"] as? Bool {
                showBookmarkList = show
            }
            if let cursor = notification.userInfo?["cursor"] as? Int {
                bookmarkListCursor = cursor
            }
        }
        // #101: Listen for deskew toggle
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlideWindowDeskewChanged"))) { notification in
            if let enabled = notification.userInfo?["deskewEnabled"] as? Bool {
                isDeskewEnabled = enabled
            }
        }
        // #150: Listen for reading direction change
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlideWindowReadingDirectionChanged"))) { _ in
            readingDirectionVersion += 1
        }
        // #151: Listen for controls toggle
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlideWindowControlsToggle"))) { notification in
            if let level = notification.userInfo?["overlayLevel"] as? Int {
                overlayLevel = level
            }
        }
        // #172: Listen for auto-slide state changes
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlideWindowAutoSlideChanged"))) { notification in
            if let mode = notification.userInfo?["autoSlideMode"] as? Int {
                autoSlideMode = mode
            }
        }
    }
    
    // MARK: - S008: Empty Source View
    
    @ViewBuilder
    private var emptySourceView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.4))
            
            Text("No images")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
            
            Text(imageSource.url.lastPathComponent)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
            
            Spacer().frame(height: 32)
            
            // Navigation hint
            VStack(spacing: 8) {
                Text("Ctrl+← / Ctrl+→")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Navigate to another source")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }
    
    // MARK: - Controls Overlay (#151: 3-level display)
    // Level 0 (Full): nav bar + position bars + indicators + esc/close + bottom hints
    // Level 1 (Compact): nav bar + position bars + indicators (no esc/close, no bottom hints)
    // Level 2 (Clean): ★ + FAVORITES + DESKEW only, no background
    
    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            if overlayLevel == 2 {
                // Clean: indicators only, no background
                HStack {
                    Spacer()
                    statusIndicators
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
                Spacer()
            } else {
                // Full (0) and Compact (1): top bar with nav info
                VStack(alignment: .leading, spacing: 4) {
                    // Row 1: Source name › Filename (position) + indicators
                    HStack {
                        // Source name › Filename (n/total)
                        if entries.isEmpty {
                            Text(imageSource.url.lastPathComponent)
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.6))
                        } else if currentIndex >= 0 && currentIndex < entries.count {
                            HStack(spacing: 0) {
                                if !sourceName.isEmpty {
                                    Text(sourceName)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.6))
                                    Text(" › ")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                Text(entries[currentIndex].name)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                // #115: Spread-aware position indicator
                                if isShowingSpread {
                                    let left = currentIndex + 1
                                    let right = currentIndex + 2
                                    Text(" (\(isRTL ? "\(right)-\(left)" : "\(left)-\(right)")/\(entries.count))")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.6))
                                } else {
                                    Text(" (\(currentIndex + 1)/\(entries.count))")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                        
                        Spacer()
                        
                        statusIndicators
                        
                        // Full only: esc hint + close button
                        if overlayLevel == 0 {
                            HStack(spacing: 4) {
                                Text("esc")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.2))
                                    .cornerRadius(4)
                                Text("exit")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                            Button {
                                onClose()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 12)
                        }
                    }
                    
                    // Row 2: Image position indicator
                    if !entries.isEmpty {
                        ImagePositionBar(
                            current: currentIndex + 1,
                            total: entries.count,
                            favoriteIndices: favoriteIndices,
                            selectedIndices: selectedIndices,
                            barWidth: 144,
                            isRTL: isRTL
                        )
                        .frame(height: 12)
                    }
                    
                    // Row 3: Source position indicator
                    if totalSources > 1 {
                        SourcePositionIndicator(
                            current: sourcePosition,
                            total: totalSources,
                            barWidth: 144,
                            isRTL: isRTL
                        )
                        .frame(height: 16)
                    }
                }
                .padding()
                .background(
                    overlayLevel == 0 ?
                    LinearGradient(
                        colors: isFavoritesMode 
                            ? [.yellow.opacity(0.4), .black.opacity(0.3), .clear]
                            : [.black.opacity(0.7), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ) :
                    LinearGradient(
                        colors: [.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Spacer()
                
                // Full only: bottom navigation hints
                if overlayLevel == 0 {
                    bottomHints
                }
            }
        }
    }
    
    /// Shared status indicators: ★, FAVORITES badge, DESKEW badge
    @ViewBuilder
    private var statusIndicators: some View {
        // ★ Favorite indicator
        if favoriteIndices.contains(currentIndex) ||
           (isShowingSpread && favoriteIndices.contains(currentIndex + 1)) {
            Image(systemName: "star.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
                .padding(.trailing, 8)
        }
        
        // FAVORITES Mode badge
        if isFavoritesMode {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text("FAVORITES")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.yellow.opacity(0.2))
            .cornerRadius(4)
        }
        
        // AUTO-SLIDE badge (#172/#178)
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
        
        // DESKEW indicator (PDF only)
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
    }
    
    /// Bottom navigation hints bar
    private var bottomHints: some View {
        HStack {
            Text("a/←")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Text(isFavoritesMode ? (isRTL ? "next ★" : "prev ★") : (isRTL ? "next" : "previous"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
            
            Spacer()
            
            if isFavoritesMode {
                Text("q")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text("exit ★ mode")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                if AppSettings.shared.isSpreadModeEnabled {
                    Text("v")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("single")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
                
                if imageSource.sourceType == .pdf {
                    Text("p")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("deskew")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                    
                    Text("⌘[/]")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("adjust")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
                
                Text("tab")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 8)
                Text("★ mode")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                
                Text("space")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 8)
                Text(autoSlideMode != 0 ? "stop auto" : "auto-slide")
                    .font(.caption)
                    .foregroundStyle(autoSlideMode != 0 ? .green.opacity(0.7) : .white.opacity(0.3))
                
                Text("q")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 8)
                Text("exit")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
            
            Spacer()
            
            Text(isFavoritesMode ? (isRTL ? "prev ★" : "next ★") : (isRTL ? "previous" : "next"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
            Text("d/→")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - #145: Slide Hosting View (Cursor Control)

/// NSHostingView subclass that intercepts cursorUpdate to maintain transparent cursor
class SlideHostingView<Content: View>: NSHostingView<Content> {
    var shouldHideCursor: Bool = false
    
    override func cursorUpdate(with event: NSEvent) {
        if shouldHideCursor {
            SlideWindowController.shared.reapplyTransparentCursor()
        } else {
            super.cursorUpdate(with: event)
        }
    }
}

// MARK: - Slide Key Handler (Supplementary)

struct SlideKeyHandler: NSViewRepresentable {
    let onClose: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPreviousFavorite: () -> Void
    let onNextFavorite: () -> Void
    let onExitFullScreen: () -> Void
    let onToggleControls: () -> Void
    let onNextSource: (() -> Void)?
    let onPreviousSource: (() -> Void)?
    
    func makeNSView(context: Context) -> SlideKeyView {
        let view = SlideKeyView()
        view.onClose = onClose
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onPreviousFavorite = onPreviousFavorite
        view.onNextFavorite = onNextFavorite
        view.onExitFullScreen = onExitFullScreen
        view.onToggleControls = onToggleControls
        view.onNextSource = onNextSource
        view.onPreviousSource = onPreviousSource
        return view
    }
    
    func updateNSView(_ nsView: SlideKeyView, context: Context) {
        nsView.onClose = onClose
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.onPreviousFavorite = onPreviousFavorite
        nsView.onNextFavorite = onNextFavorite
        nsView.onExitFullScreen = onExitFullScreen
        nsView.onToggleControls = onToggleControls
        nsView.onNextSource = onNextSource
        nsView.onPreviousSource = onPreviousSource
    }
    
    class SlideKeyView: NSView {
        var onClose: (() -> Void)?
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?
        var onPreviousFavorite: (() -> Void)?
        var onNextFavorite: (() -> Void)?
        var onExitFullScreen: (() -> Void)?
        var onToggleControls: (() -> Void)?
        var onNextSource: (() -> Void)?
        var onPreviousSource: (() -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            // S008: Only handle Space for toggle controls
            // Other keys are handled by SlideWindowController's event monitor
            if event.keyCode == 49 {  // Space
                Logger.slideWindow.debug("→ Toggle controls (Space)")
                onToggleControls?()
            } else {
                // Pass through - already handled by event monitor
                super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Image Position Bar (S010)

/// Progress bar for image position within current source, with favorite and selection markers
struct ImagePositionBar: View {
    let current: Int
    let total: Int
    let favoriteIndices: Set<Int>
    let selectedIndices: Set<Int>
    let barWidth: CGFloat
    let isRTL: Bool  // #54
    
    private var progress: CGFloat {
        guard total > 1 else { return 1.0 }
        let rawProgress = CGFloat(current - 1) / CGFloat(total - 1)
        return isRTL ? (1.0 - rawProgress) : rawProgress
    }
    
    private func markerX(for index: Int) -> CGFloat {
        let rawProgress = total > 1 ? CGFloat(index) / CGFloat(total - 1) : 0.5
        let adjustedProgress = isRTL ? (1.0 - rawProgress) : rawProgress
        return adjustedProgress * barWidth
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: barWidth, height: 3)
            
            ForEach(Array(selectedIndices), id: \.self) { selIndex in
                Image(systemName: "xmark")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundStyle(.red)
                    .offset(x: markerX(for: selIndex) - 2.5)
            }
            
            ForEach(Array(favoriteIndices), id: \.self) { favIndex in
                Image(systemName: "star.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.yellow)
                    .offset(x: markerX(for: favIndex) - 3)
            }
            
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .offset(x: max(0, progress * barWidth - 4))
        }
        .frame(width: barWidth, height: 10)
    }
}

// NOTE: SpreadImageViewer has been extracted to SpreadImageViewer.swift (#67)
