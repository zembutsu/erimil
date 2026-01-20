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
//  Updated: S012 (2025-01-20) - Added close animation options (#17)
//

import SwiftUI
import AppKit

/// Slide Mode close animation style (#17)
enum SlideCloseStyle: String, CaseIterable {
    case `default` = "default"  // macOS standard behavior
    case instant = "instant"    // No animation
    case fade = "fade"          // Fade out (0.2s)
    
    static var current: SlideCloseStyle {
        let raw = UserDefaults.standard.string(forKey: "slideCloseStyle") ?? "default"
        return SlideCloseStyle(rawValue: raw) ?? .default
    }
}

/// S012: Borderless window that can receive key events (#17)
class SlideWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Controller for managing the Slide Mode fullscreen window
class SlideWindowController {
    
    static var shared = SlideWindowController()
    
    private var slideWindow: NSWindow?
    private var backgroundWindows: [NSWindow] = []  // S012: For secondary displays
    private var currentIndex: Int = 0
    
    // S008: Event monitor for centralized key handling
    private var eventMonitor: Any?
    
    // S008: Callback storage for event monitor
    private var storedOnClose: (() -> Void)?
    private var storedOnNextSource: (() -> Void)?
    private var storedOnPreviousSource: (() -> Void)?
    private var storedOnIndexChange: ((Int) -> Void)?
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
        onToggleFavorite: ((Int) -> Void)? = nil,
        onToggleSelection: ((Int) -> Void)? = nil
    ) {
        print("[SlideWindowController] open() called")
        print("[SlideWindowController] entries.count: \(entries.count), initialIndex: \(initialIndex), favorites: \(favoriteIndices.count)")
        print("[SlideWindowController] source: \(sourceName) (\(sourcePosition)/\(totalSources))")
        
        // Close existing window if any
        close()
        
        currentIndex = initialIndex
        isFavoritesMode = false
        
        // S008: Store callbacks and state for event monitor
        storedOnClose = onClose
        storedOnNextSource = onNextSource
        storedOnPreviousSource = onPreviousSource
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
            onClose: { [weak self] in
                print("[SlideWindowController] onClose callback triggered")
                self?.close()
                onClose()
            },
            onExitFullScreen: { [weak self] in
                print("[SlideWindowController] onExitFullScreen callback triggered")
                self?.close()
                onClose()
            },
            onIndexChange: { [weak self] index in
                self?.currentIndex = index
                onIndexChange?(index)
            },
            onNextSource: onNextSource,
            onPreviousSource: onPreviousSource
        )
        
        // Create hosting view
        let hostingView = NSHostingView(rootView: slideView)
        
        // S012: Get screen for pseudo-fullscreen (#17)
        guard let mainScreen = NSScreen.main else {
            print("[SlideWindowController] No main screen available")
            return
        }
        
        // S012: Create black background windows for secondary displays first
        for screen in NSScreen.screens where screen != mainScreen {
            let bgWindow = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            bgWindow.backgroundColor = .black
            bgWindow.level = .screenSaver
            bgWindow.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
            bgWindow.setFrame(screen.frame, display: true)
            bgWindow.orderFront(nil)
            backgroundWindows.append(bgWindow)
            print("[SlideWindowController] Background window created for secondary display")
        }
        
        // S012: Create main window with SlideWindow (supports key events)
        let window = SlideWindow(
            contentRect: mainScreen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hostingView
        window.title = "Slide Mode"
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        
        // S012: Pseudo-fullscreen settings
        window.level = .screenSaver  // Stay above other windows
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.setFrame(mainScreen.frame, display: true)
        
        print("[SlideWindowController] Window created (pseudo-fullscreen), making key and ordering front")
        
        // Show window immediately (no toggleFullScreen needed)
        window.makeKeyAndOrderFront(nil)
        
        slideWindow = window
        
        // S008: Register key event monitor
        setupEventMonitor()
        
        print("[SlideWindowController] open() complete")
    }
    
    /// Close the Slide Mode window
    func close() {
        print("[SlideWindowController] close() called")
        
        // S008: Remove event monitor first
        removeEventMonitor()
        
        // S008: Clear stored callbacks
        storedOnClose = nil
        storedOnNextSource = nil
        storedOnPreviousSource = nil
        storedOnIndexChange = nil
        storedOnToggleFavorite = nil
        storedOnToggleSelection = nil
        storedEntries = []
        storedFavoriteIndices = []
        storedSelectedIndices = []
        
        // S010: Clear source position info
        storedSourceName = ""
        storedSourcePosition = 0
        storedTotalSources = 0
        
        // S010: Reset favorites mode
        isFavoritesMode = false
        
        guard let window = slideWindow else {
            print("[SlideWindowController] No window to close")
            // S012: Still close background windows if any
            closeBackgroundWindows()
            return
        }
        
        let style = SlideCloseStyle.current
        print("[SlideWindowController] Closing window with style: \(style.rawValue) (isFullScreen: \(window.styleMask.contains(.fullScreen)))")
        
        // S012: Close with selected animation style (#17)
        // Note: Using pseudo-fullscreen, no system fullscreen animation to bypass
        switch style {
        case .default:
            // Standard close (instant for pseudo-fullscreen)
            window.contentView = nil
            slideWindow = nil
            closeBackgroundWindows()
            window.orderOut(nil)
            window.close()
            
        case .instant:
            // Instant close
            window.contentView = nil
            slideWindow = nil
            window.animationBehavior = .none
            closeBackgroundWindows()
            window.orderOut(nil)
            window.close()
            
        case .fade:
            // Fade out animation (0.2s) - include background windows
            // Capture background windows before animation to avoid timing issues
            let bgWindows = backgroundWindows
            backgroundWindows.removeAll()
            slideWindow = nil  // Clear reference early to prevent re-entry
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 0
                for bgWindow in bgWindows {
                    bgWindow.animator().alphaValue = 0
                }
            }, completionHandler: {
                // Dispatch to next run loop to avoid timing issues with window release
                DispatchQueue.main.async {
                    // Clear content view AFTER animation completes
                    window.contentView = nil
                    // Close all windows
                    for bgWindow in bgWindows {
                        bgWindow.orderOut(nil)
                        bgWindow.close()
                    }
                    window.orderOut(nil)
                    window.close()
                    print("[SlideWindowController] Fade complete, all windows closed")
                }
            })
        }
        
        print("[SlideWindowController] Window closed and released")
    }
    
    /// S012: Close all background windows for secondary displays
    private func closeBackgroundWindows() {
        for bgWindow in backgroundWindows {
            bgWindow.orderOut(nil)
            bgWindow.close()
        }
        backgroundWindows.removeAll()
        print("[SlideWindowController] Background windows closed")
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
        onToggleFavorite: ((Int) -> Void)? = nil,
        onToggleSelection: ((Int) -> Void)? = nil
    ) {
        guard let window = slideWindow else {
            print("[SlideWindowController] updateSource: no window, falling back to open()")
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
                onToggleFavorite: onToggleFavorite,
                onToggleSelection: onToggleSelection
            )
            return
        }
        
        print("[SlideWindowController] updateSource: updating content in-place")
        print("[SlideWindowController] new entries.count: \(entries.count), favorites: \(favoriteIndices.count)")
        print("[SlideWindowController] source: \(sourceName) (\(sourcePosition)/\(totalSources))")
        
        // S008: Update stored state for event monitor
        currentIndex = 0
        isFavoritesMode = false  // Reset mode on source change
        storedOnClose = onClose
        storedOnNextSource = onNextSource
        storedOnPreviousSource = onPreviousSource
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
        
        // Create new SwiftUI view with updated content
        let slideView = SlideWindowView(
            imageSource: imageSource,
            entries: entries,
            initialIndex: 0,  // Start from first image
            favoriteIndices: favoriteIndices,
            selectedIndices: selectedIndices,
            sourceName: sourceName,
            sourcePosition: sourcePosition,
            totalSources: totalSources,
            isFavoritesMode: isFavoritesMode,
            onClose: { [weak self] in
                print("[SlideWindowController] onClose callback triggered")
                self?.close()
                onClose()
            },
            onExitFullScreen: { [weak self] in
                print("[SlideWindowController] onExitFullScreen callback triggered")
                self?.close()
                onClose()
            },
            onIndexChange: { [weak self] index in
                self?.currentIndex = index
                onIndexChange?(index)
            },
            onNextSource: onNextSource,
            onPreviousSource: onPreviousSource
        )
        
        // Replace content view while keeping window state (including fullscreen)
        let hostingView = NSHostingView(rootView: slideView)
        window.contentView = hostingView
        
        print("[SlideWindowController] updateSource: content replaced, fullscreen maintained")
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
        
        print("[SlideWindowController] Event monitor registered")
    }
    
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            print("[SlideWindowController] Event monitor removed")
        }
    }
    
    /// Handle key events centrally - returns nil to consume, event to pass through
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let hasControl = event.modifierFlags.contains(.control)
        
        print("[SlideWindowController] handleKeyEvent: keyCode=\(event.keyCode), ctrl=\(hasControl), favMode=\(isFavoritesMode)")
        
        switch event.keyCode {
        // Escape - close fullscreen
        case 53:
            print("[SlideWindowController] → Close (Esc)")
            triggerClose()
            return nil
            
        // Space - toggle controls (pass to view)
        case 49:
            return event  // Let SlideKeyView handle this
            
        // Tab - next favorite + enter Favorites Mode
        case 48:
            print("[SlideWindowController] → Next favorite + Favorites Mode ON (Tab)")
            if !isFavoritesMode {
                isFavoritesMode = true
                notifyViewOfModeChange()
            }
            goToNextFavorite()
            return nil
            
        // Left arrow
        case 123:
            if hasControl {
                print("[SlideWindowController] → Previous source (Ctrl+←)")
                storedOnPreviousSource?()
                return nil
            } else if isFavoritesMode {
                print("[SlideWindowController] → Previous favorite (← in Favorites Mode)")
                goToPreviousFavorite()
                return nil
            } else {
                goToPrevious()
                return nil
            }
            
        // Right arrow
        case 124:
            if hasControl {
                print("[SlideWindowController] → Next source (Ctrl+→)")
                storedOnNextSource?()
                return nil
            } else if isFavoritesMode {
                print("[SlideWindowController] → Next favorite (→ in Favorites Mode)")
                goToNextFavorite()
                return nil
            } else {
                goToNext()
                return nil
            }
            
        default:
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "a":
                    if hasControl {
                        print("[SlideWindowController] → Previous source (Ctrl+A)")
                        storedOnPreviousSource?()
                    } else if isFavoritesMode {
                        print("[SlideWindowController] → Previous favorite (A in Favorites Mode)")
                        goToPreviousFavorite()
                    } else {
                        goToPrevious()
                    }
                    return nil
                    
                case "d":
                    if hasControl {
                        print("[SlideWindowController] → Next source (Ctrl+D)")
                        storedOnNextSource?()
                    } else if isFavoritesMode {
                        print("[SlideWindowController] → Next favorite (D in Favorites Mode)")
                        goToNextFavorite()
                    } else {
                        goToNext()
                    }
                    return nil
                    
                case "f":
                    // S010: Toggle favorite (not exit fullscreen anymore)
                    print("[SlideWindowController] → Toggle favorite (F)")
                    toggleFavorite()
                    return nil
                    
                case "x":
                    // S010: Toggle selection
                    print("[SlideWindowController] → Toggle selection (X)")
                    toggleSelection()
                    return nil
                    
                case "q":
                    // S010: Exit Favorites Mode OR close fullscreen
                    if isFavoritesMode {
                        print("[SlideWindowController] → Exit Favorites Mode (Q)")
                        isFavoritesMode = false
                        notifyViewOfModeChange()
                    } else {
                        print("[SlideWindowController] → Close fullscreen (Q)")
                        triggerClose()
                    }
                    return nil
                    
                // S010: Disabled keys (commented out for future reference)
                // case "z":
                //     goToPreviousFavorite()
                //     return nil
                // case "c":
                //     goToNextFavorite()
                //     return nil
                    
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
    
    // MARK: - S008: Navigation (moved from View for centralized control)
    
    private func goToPrevious() {
        guard !storedEntries.isEmpty, currentIndex > 0 else { return }
        currentIndex -= 1
        storedOnIndexChange?(currentIndex)
        notifyViewOfIndexChange()
    }
    
    private func goToNext() {
        guard !storedEntries.isEmpty, currentIndex < storedEntries.count - 1 else { return }
        currentIndex += 1
        storedOnIndexChange?(currentIndex)
        notifyViewOfIndexChange()
    }
    
    private func goToPreviousFavorite() {
        guard !storedFavoriteIndices.isEmpty else { return }
        
        let previousFavorites = storedFavoriteIndices.filter { $0 < currentIndex }
        if let targetIndex = previousFavorites.max() {
            currentIndex = targetIndex
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        } else if let lastFavorite = storedFavoriteIndices.max(), lastFavorite != currentIndex {
            // Wrap around to last favorite
            currentIndex = lastFavorite
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        }
    }
    
    private func goToNextFavorite() {
        guard !storedFavoriteIndices.isEmpty else { return }
        
        let nextFavorites = storedFavoriteIndices.filter { $0 > currentIndex }
        if let targetIndex = nextFavorites.min() {
            currentIndex = targetIndex
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        } else if let firstFavorite = storedFavoriteIndices.min(), firstFavorite != currentIndex {
            // Wrap around to first favorite
            currentIndex = firstFavorite
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        }
    }
    
    // MARK: - S010: Favorite and Selection Toggles
    
    private func toggleFavorite() {
        guard !storedEntries.isEmpty, currentIndex >= 0, currentIndex < storedEntries.count else { return }
        
        // Toggle in local state
        if storedFavoriteIndices.contains(currentIndex) {
            storedFavoriteIndices.remove(currentIndex)
        } else {
            storedFavoriteIndices.insert(currentIndex)
        }
        
        // Notify ThumbnailGrid via callback
        storedOnToggleFavorite?(currentIndex)
        
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
    
    // MARK: - Notifications
    
    /// Notify the view of index change via NotificationCenter
    private func notifyViewOfIndexChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowIndexChanged"),
            object: nil,
            userInfo: ["index": currentIndex]
        )
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
    let onClose: () -> Void
    let onExitFullScreen: () -> Void
    let onIndexChange: ((Int) -> Void)?
    let onNextSource: (() -> Void)?
    let onPreviousSource: (() -> Void)?
    
    @State private var currentIndex: Int = 0
    @State private var showControls: Bool = true
    @State private var isFavoritesMode: Bool = false
    @State private var favoriteIndices: Set<Int> = []
    @State private var selectedIndices: Set<Int> = []
    
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
        onClose: @escaping () -> Void,
        onExitFullScreen: @escaping () -> Void,
        onIndexChange: ((Int) -> Void)?,
        onNextSource: (() -> Void)?,
        onPreviousSource: (() -> Void)?
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
        self.onClose = onClose
        self.onExitFullScreen = onExitFullScreen
        self.onIndexChange = onIndexChange
        self.onNextSource = onNextSource
        self.onPreviousSource = onPreviousSource
    }
    
    var body: some View {
        ZStack {
            // S008: Handle empty source
            if entries.isEmpty {
                emptySourceView
            } else {
                // Image viewer
                ImageViewerCore(
                    imageSource: imageSource,
                    entries: entries,
                    currentIndex: $currentIndex,
                    showPositionIndicator: false,
                    favoriteIndices: favoriteIndices
                )
            }
            
            // Controls overlay (auto-hide capable)
            if showControls {
                controlsOverlay
            }
            
            // S010: Persistent Favorites Mode indicator (shown even when controls hidden)
            if isFavoritesMode && !showControls {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.title3)
                                .foregroundStyle(.yellow)
                            Text("FAVORITES")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.yellow)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(.trailing, 16)
                        .padding(.top, 16)
                    }
                    Spacer()
                }
            }
            
            // Key event handler (supplementary - main handling in Controller)
            SlideKeyHandler(
                onClose: onClose,
                onPrevious: { /* handled by controller */ },
                onNext: { /* handled by controller */ },
                onPreviousFavorite: { /* handled by controller */ },
                onNextFavorite: { /* handled by controller */ },
                onExitFullScreen: onExitFullScreen,
                onToggleControls: { showControls.toggle() },
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
            favoriteIndices = initialFavoriteIndices
            selectedIndices = initialSelectedIndices
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
    
    // MARK: - Controls Overlay (S010: 3-row layout with Favorites Mode indicator)
    
    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            // Top bar (S010: 3-row structure)
            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Source name › Filename (position) + Favorites Mode indicator
                HStack {
                    // S010: Full path display
                    if entries.isEmpty {
                        Text(imageSource.url.lastPathComponent)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.6))
                    } else if currentIndex >= 0 && currentIndex < entries.count {
                        // Source name › Filename (n/total)
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
                            Text(" (\(currentIndex + 1)/\(entries.count))")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    // S010: Favorites Mode indicator
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
                    
                    // Exit hint (changed from f to Esc)
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
                    
                    // Close button
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
                
                //// Row 2: Image position indicator (within current source)
                // if entries.count > 1 {
                // Row 2: Image position indicator (always show for consistent layout)
                if !entries.isEmpty {
                    ImagePositionBar(
                        current: currentIndex + 1,
                        total: entries.count,
                        favoriteIndices: favoriteIndices,
                        selectedIndices: selectedIndices,
                        barWidth: 144
                    )
                    .frame(height: 12)
                }
                
                // Row 3: Source position indicator (among sibling sources)
                if totalSources > 1 {
                    SourcePositionIndicator(
                        current: sourcePosition,
                        total: totalSources,
                        barWidth: 144
                    )
                    .frame(height: 16)
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: isFavoritesMode 
                        ? [.yellow.opacity(0.4), .black.opacity(0.3), .clear]  // Yellow tint for Favorites Mode
                        : [.black.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Spacer()
            
            // Bottom bar - navigation hints
            HStack {
                Text("a/←")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text(isFavoritesMode ? "prev ★" : "previous")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                
                Spacer()
                
                // Mode-specific hints
                if isFavoritesMode {
                    Text("q")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("exit ★ mode")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                } else {
                    Text("tab")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("★ mode")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                    
                    Text("q")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.leading, 8)
                    Text("exit")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
                
                Spacer()
                
                Text(isFavoritesMode ? "next ★" : "next")
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
                print("[SlideKeyView] → Toggle controls (Space)")
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
    let current: Int              // 1-based current position
    let total: Int                // Total number of images
    let favoriteIndices: Set<Int> // 0-based indices of favorites
    let selectedIndices: Set<Int> // 0-based indices of selections
    let barWidth: CGFloat         // Fixed width to match source bar
    
    private var progress: CGFloat {
        guard total > 1 else { return 1.0 }
        return CGFloat(current - 1) / CGFloat(total - 1)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Progress bar with fixed width
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: barWidth, height: 3)
                
                // Selection markers (×) - red
                ForEach(Array(selectedIndices), id: \.self) { selIndex in
                    let selProgress = total > 1 ? CGFloat(selIndex) / CGFloat(total - 1) : 0.5
                    let selX = selProgress * barWidth
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(.red)
                        .offset(x: selX - 2.5)
                }
                
                // Favorite markers (★) - yellow
                ForEach(Array(favoriteIndices), id: \.self) { favIndex in
                    let favProgress = total > 1 ? CGFloat(favIndex) / CGFloat(total - 1) : 0.5
                    let favX = favProgress * barWidth
                    
                    Image(systemName: "star.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.yellow)
                        .offset(x: favX - 3)
                }
                
                // Position marker (current)
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .offset(x: max(0, progress * barWidth - 4))
            }
            .frame(width: barWidth, height: 10)
            
            Spacer()
            
            // Numeric indicator (right-aligned)
            Text("\(current)/\(total)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
