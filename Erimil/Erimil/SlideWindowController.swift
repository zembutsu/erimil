//
//  SlideWindowController.swift
//  Erimil
//
//  Created for Phase 2.2 - Slide Mode
//  Session: S003 (2025-12-17)
//  Updated: S005 (2025-12-27) - Added source navigation (Ctrl+Arrow)
//  Updated: S008 (2025-01-09) - Centralized key handling for empty source support (#21)
//

import SwiftUI
import AppKit

/// Controller for managing the Slide Mode fullscreen window
class SlideWindowController {
    
    static var shared = SlideWindowController()
    
    private var slideWindow: NSWindow?
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
    
    private init() {}
    
    /// Open Slide Mode window with fullscreen
    /// - Parameters:
    ///   - imageSource: The image source (ZIP or Folder)
    ///   - entries: Array of image entries
    ///   - initialIndex: Starting image index
    ///   - favoriteIndices: Set of favorite entry indices for z/c navigation
    ///   - onClose: Callback when window is closed
    ///   - onIndexChange: Callback when navigation changes index (for Grid sync)
    ///   - onNextSource: Callback when user requests next source (Ctrl+Arrow)
    ///   - onPreviousSource: Callback when user requests previous source (Ctrl+Arrow)
    func open(
        imageSource: any ImageSource,
        entries: [ImageEntry],
        initialIndex: Int,
        favoriteIndices: Set<Int>,
        onClose: @escaping () -> Void,
        onIndexChange: ((Int) -> Void)? = nil,
        onNextSource: (() -> Void)? = nil,
        onPreviousSource: (() -> Void)? = nil
    ) {
        print("[SlideWindowController] open() called")
        print("[SlideWindowController] entries.count: \(entries.count), initialIndex: \(initialIndex), favorites: \(favoriteIndices.count)")
        
        // Close existing window if any
        close()
        
        currentIndex = initialIndex
        
        // S008: Store callbacks and state for event monitor
        storedOnClose = onClose
        storedOnNextSource = onNextSource
        storedOnPreviousSource = onPreviousSource
        storedOnIndexChange = onIndexChange
        storedEntries = entries
        storedFavoriteIndices = favoriteIndices
        
        // Create the SwiftUI view
        let slideView = SlideWindowView(
            imageSource: imageSource,
            entries: entries,
            initialIndex: initialIndex,
            favoriteIndices: favoriteIndices,
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
        
        print("[SlideWindowController] Window created, making key and ordering front")
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        
        // Toggle to fullscreen after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("[SlideWindowController] Toggling fullscreen...")
            window.toggleFullScreen(nil)
        }
        
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
        storedEntries = []
        storedFavoriteIndices = []
        
        guard let window = slideWindow else {
            print("[SlideWindowController] No window to close")
            return
        }
        
        print("[SlideWindowController] Closing window immediately (isFullScreen: \(window.styleMask.contains(.fullScreen)))")
        
        // Clear content view to release SwiftUI hosting view
        window.contentView = nil
        
        // Hide the window instantly (regardless of fullscreen state)
        window.orderOut(nil)
        
        // Close the window
        window.close()
        
        // Release our reference
        slideWindow = nil
        
        print("[SlideWindowController] Window closed and released")
    }
    
    /// Check if Slide Mode window is open
    var isOpen: Bool {
        slideWindow != nil
    }
    
    /// Update the source while keeping fullscreen state (S005)
    /// - Parameters:
    ///   - imageSource: The new image source
    ///   - entries: New array of image entries
    ///   - favoriteIndices: New set of favorite indices
    ///   - onClose: Callback when window is closed
    ///   - onIndexChange: Callback when navigation changes index
    ///   - onNextSource: Callback for next source navigation
    ///   - onPreviousSource: Callback for previous source navigation
    func updateSource(
        imageSource: any ImageSource,
        entries: [ImageEntry],
        favoriteIndices: Set<Int>,
        onClose: @escaping () -> Void,
        onIndexChange: ((Int) -> Void)? = nil,
        onNextSource: (() -> Void)? = nil,
        onPreviousSource: (() -> Void)? = nil
    ) {
        guard let window = slideWindow else {
            print("[SlideWindowController] updateSource: no window, falling back to open()")
            open(
                imageSource: imageSource,
                entries: entries,
                initialIndex: 0,
                favoriteIndices: favoriteIndices,
                onClose: onClose,
                onIndexChange: onIndexChange,
                onNextSource: onNextSource,
                onPreviousSource: onPreviousSource
            )
            return
        }
        
        print("[SlideWindowController] updateSource: updating content in-place")
        print("[SlideWindowController] new entries.count: \(entries.count), favorites: \(favoriteIndices.count)")
        
        // S008: Update stored state for event monitor
        currentIndex = 0
        storedOnClose = onClose
        storedOnNextSource = onNextSource
        storedOnPreviousSource = onPreviousSource
        storedOnIndexChange = onIndexChange
        storedEntries = entries
        storedFavoriteIndices = favoriteIndices
        
        // Create new SwiftUI view with updated content
        let slideView = SlideWindowView(
            imageSource: imageSource,
            entries: entries,
            initialIndex: 0,  // Start from first image
            favoriteIndices: favoriteIndices,
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
        
        // S008: No need to set firstResponder - event monitor handles keys
        
        print("[SlideWindowController] updateSource: content replaced, fullscreen maintained")
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
        
        print("[SlideWindowController] handleKeyEvent: keyCode=\(event.keyCode), ctrl=\(hasControl)")
        
        switch event.keyCode {
        // Escape - close
        case 53:
            print("[SlideWindowController] → Close (Esc)")
            triggerClose()
            return nil
            
        // Space - toggle controls (pass to view)
        case 49:
            return event  // Let SlideKeyView handle this
            
        // Left arrow
        case 123:
            if hasControl {
                print("[SlideWindowController] → Previous source (Ctrl+←)")
                storedOnPreviousSource?()
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
                    } else {
                        goToPrevious()
                    }
                    return nil
                case "d":
                    if hasControl {
                        print("[SlideWindowController] → Next source (Ctrl+D)")
                        storedOnNextSource?()
                    } else {
                        goToNext()
                    }
                    return nil
                case "z":
                    goToPreviousFavorite()
                    return nil
                case "c":
                    goToNextFavorite()
                    return nil
                case "f":
                    print("[SlideWindowController] → Exit fullscreen (f)")
                    triggerClose()
                    return nil
                case "q":
                    print("[SlideWindowController] → Close (q)")
                    triggerClose()
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
            currentIndex = firstFavorite
            storedOnIndexChange?(currentIndex)
            notifyViewOfIndexChange()
        }
    }
    
    /// Notify the view of index change via NotificationCenter
    private func notifyViewOfIndexChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SlideWindowIndexChanged"),
            object: nil,
            userInfo: ["index": currentIndex]
        )
    }
}

// MARK: - Slide Window View

/// The view displayed in the Slide Mode fullscreen window
struct SlideWindowView: View {
    let imageSource: any ImageSource
    let entries: [ImageEntry]
    let initialIndex: Int
    let favoriteIndices: Set<Int>
    let onClose: () -> Void
    let onExitFullScreen: () -> Void
    let onIndexChange: ((Int) -> Void)?
    let onNextSource: (() -> Void)?
    let onPreviousSource: (() -> Void)?
    
    @State private var currentIndex: Int = 0
    @State private var showControls: Bool = true
    
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
    
    // MARK: - Controls Overlay
    
    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                // Filename (or source name for empty)
                if entries.isEmpty {
                    Text(imageSource.url.lastPathComponent)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.6))
                } else if currentIndex >= 0 && currentIndex < entries.count {
                    Text(entries[currentIndex].name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Position indicator
                if entries.isEmpty {
                    Text("0 / 0")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    Text("\(currentIndex + 1) / \(entries.count)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                Spacer()
                
                // Exit hint
                HStack(spacing: 4) {
                    Text("f")
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
            .padding()
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
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
                Text("previous")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                
                Spacer()
                
                // Source navigation hint
                Text("⌃←/→")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text("prev/next source")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                
                Spacer()
                
                Text("next")
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
        // S008: Don't force firstResponder - controller handles keys
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
