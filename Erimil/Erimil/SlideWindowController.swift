//
//  SlideWindowController.swift
//  Erimil
//
//  Created for Phase 2.2 - Slide Mode
//  Session: S003 (2025-12-17)
//  Updated: S005 (2025-12-27) - Added source navigation (Ctrl+Arrow)
//
//  Manages a separate NSWindow for fullscreen Slide Mode viewing.
//  This approach is required because:
//  1. fullScreenCover() is not available on macOS
//  2. Sheet windows cannot use toggleFullScreen()
//

import SwiftUI
import AppKit

/// Controller for managing the Slide Mode fullscreen window
class SlideWindowController {
    
    static var shared = SlideWindowController()
    
    private var slideWindow: NSWindow?
    private var currentIndex: Int = 0
    
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
                // Exit fullscreen but keep window open? Or close entirely?
                // For now, close the window (return to Quick Look)
                self?.close()
                onClose()
            },
            onIndexChange: onIndexChange,
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
        print("[SlideWindowController] open() complete")
    }
    
    /// Close the Slide Mode window
    func close() {
        print("[SlideWindowController] close() called")
        
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
            onIndexChange: onIndexChange,
            onNextSource: onNextSource,
            onPreviousSource: onPreviousSource
        )
        
        // Replace content view while keeping window state (including fullscreen)
        let hostingView = NSHostingView(rootView: slideView)
        window.contentView = hostingView
        
        // Ensure window has focus
        window.makeFirstResponder(hostingView)
        
        print("[SlideWindowController] updateSource: content replaced, fullscreen maintained")
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
            // Image viewer
            ImageViewerCore(
                imageSource: imageSource,
                entries: entries,
                currentIndex: $currentIndex,
                showPositionIndicator: false,
                favoriteIndices: favoriteIndices
            )
            
            // Controls overlay (auto-hide capable)
            if showControls {
                controlsOverlay
            }
            
            // Key event handler
            SlideKeyHandler(
                onClose: onClose,
                onPrevious: { goToPrevious() },
                onNext: { goToNext() },
                onPreviousFavorite: { goToPreviousFavorite() },
                onNextFavorite: { goToNextFavorite() },
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
    }
    
    // MARK: - Controls Overlay
    
    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                // Filename
                if currentIndex >= 0 && currentIndex < entries.count {
                    Text(entries[currentIndex].name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Position indicator
                Text("\(currentIndex + 1) / \(entries.count)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                
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
    
    // MARK: - Navigation
    
    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }
    
    private func goToNext() {
        guard currentIndex < entries.count - 1 else { return }
        currentIndex += 1
    }
    
    private func goToPreviousFavorite() {
        guard !favoriteIndices.isEmpty else { return }
        
        let previousFavorites = favoriteIndices.filter { $0 < currentIndex }
        if let targetIndex = previousFavorites.max() {
            currentIndex = targetIndex
        } else if let lastFavorite = favoriteIndices.max(), lastFavorite != currentIndex {
            currentIndex = lastFavorite
        }
    }
    
    private func goToNextFavorite() {
        guard !favoriteIndices.isEmpty else { return }
        
        let nextFavorites = favoriteIndices.filter { $0 > currentIndex }
        if let targetIndex = nextFavorites.min() {
            currentIndex = targetIndex
        } else if let firstFavorite = favoriteIndices.min(), firstFavorite != currentIndex {
            currentIndex = firstFavorite
        }
    }
}

// MARK: - Slide Key Handler

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
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
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
        
        override func flagsChanged(with event: NSEvent) {
            print("[SlideKeyView] flagsChanged: modifiers=\(event.modifierFlags.rawValue)")
            super.flagsChanged(with: event)
        }
        
        override func keyDown(with event: NSEvent) {
            // RAW debug log to check if events arrive at all
            print("[SlideKeyView] RAW: keyCode=\(event.keyCode), modifiers=\(event.modifierFlags.rawValue), chars='\(event.characters ?? "nil")', charsIgnoring='\(event.charactersIgnoringModifiers ?? "nil")'")
            
            let hasControl = event.modifierFlags.contains(.control)
            let hasCommand = event.modifierFlags.contains(.command)
            
            print("[SlideKeyView] keyDown: keyCode=\(event.keyCode), chars='\(event.charactersIgnoringModifiers ?? "nil")', ctrl=\(hasControl), cmd=\(hasCommand)")
            
            switch event.keyCode {
            // Escape - close
            case 53:
                print("[SlideKeyView] → Close triggered (Esc)")
                onClose?()
                
            // Space - toggle controls
            case 49:
                print("[SlideKeyView] → Toggle controls (Space)")
                onToggleControls?()
                
            // Left arrow
            case 123:
                if hasControl {
                    print("[SlideKeyView] → Previous source (Ctrl+←)")
                    onPreviousSource?()
                } else {
                    print("[SlideKeyView] → Previous (←)")
                    onPrevious?()
                }
                
            // Right arrow
            case 124:
                if hasControl {
                    print("[SlideKeyView] → Next source (Ctrl+→)")
                    onNextSource?()
                } else {
                    print("[SlideKeyView] → Next (→)")
                    onNext?()
                }
                
            default:
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    switch chars {
                    case "a":
                        if hasControl {
                            print("[SlideKeyView] → Previous source (Ctrl+A)")
                            onPreviousSource?()
                        } else {
                            print("[SlideKeyView] → Previous (a)")
                            onPrevious?()
                        }
                    case "d":
                        if hasControl {
                            print("[SlideKeyView] → Next source (Ctrl+D)")
                            onNextSource?()
                        } else {
                            print("[SlideKeyView] → Next (d)")
                            onNext?()
                        }
                    case "z":
                        print("[SlideKeyView] → Previous favorite (z)")
                        onPreviousFavorite?()
                    case "c":
                        print("[SlideKeyView] → Next favorite (c)")
                        onNextFavorite?()
                    case "f":
                        print("[SlideKeyView] → Exit fullscreen (f)")
                        onExitFullScreen?()
                    case "q":
                        print("[SlideKeyView] → Close (q)")
                        onClose?()
                    default:
                        print("[SlideKeyView] → Unhandled key")
                        super.keyDown(with: event)
                    }
                } else {
                    super.keyDown(with: event)
                }
            }
        }
    }
}
