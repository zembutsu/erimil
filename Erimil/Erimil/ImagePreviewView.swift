//
//  ImagePreviewView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//  Updated: S003 (2025-12-17) - Phase 2.2 Quick Look + navigation
//  Updated: S020 (2026-01-26) - Spread (two-page) view support (#55)
//  Updated: S021 (2026-01-26) - Refactoring: Use SpreadNavigationHelper (#67)
//

import SwiftUI
import AppKit

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
    
    // #55: Check if spread mode is enabled
    private var isSpreadEnabled: Bool {
        AppSettings.shared.isSpreadModeEnabled
    }
    
    var body: some View {
        ZStack {
            // #55/#67: Spread-aware image viewer (now from separate file)
            SpreadImageViewer(
                imageSource: imageSource,
                entries: entries,
                currentIndex: $currentIndex,
                favoriteIndices: favoriteIndices,
                reloadTrigger: spreadUpdateTrigger
            )
            
            // Header overlay
            VStack {
                headerView
                Spacer()
            }
            
            // Key event handler (transparent to clicks)
            QuickLookKeyHandler(
                onClose: onClose,
                onPrevious: { goToPrevious() },
                onNext: { goToNext() },
                onPreviousFavorite: { goToPreviousFavorite() },
                onNextFavorite: { goToNextFavorite() },
                onToggleFullScreen: onToggleFullScreen,
                onToggleSinglePage: { toggleSinglePageMarker() }  // #55
            )
            .allowsHitTesting(false)
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
                    Text("\(currentIndex + 1) / \(entries.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
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
                print("[ImagePreviewView] Fullscreen button clicked")
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
    
    // MARK: - Navigation (#55/#67: Spread-aware using SpreadNavigationHelper)
    
    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        
        // #67: Use SpreadNavigationHelper for spread-aware navigation
        if let newIndex = SpreadNavigationHelper.previousIndex(
            from: currentIndex,
            sourceURL: imageSource.url,
            totalCount: entries.count,
            loop: false  // Quick Look doesn't loop
        ) {
            currentIndex = newIndex
        }
    }
    
    private func goToNext() {
        guard currentIndex < entries.count - 1 else { return }
        
        // #67: Use SpreadNavigationHelper for spread-aware navigation
        if let newIndex = SpreadNavigationHelper.nextIndex(
            from: currentIndex,
            sourceURL: imageSource.url,
            totalCount: entries.count,
            loop: false  // Quick Look doesn't loop
        ) {
            currentIndex = newIndex
        }
    }
    
    private func goToPreviousFavorite() {
        guard !favoriteIndices.isEmpty else { return }
        
        // Find the largest favorite index that is less than currentIndex
        let previousFavorites = favoriteIndices.filter { $0 < currentIndex }
        if let targetIndex = previousFavorites.max() {
            currentIndex = targetIndex
        } else if let lastFavorite = favoriteIndices.max(), lastFavorite != currentIndex {
            // Wrap to last favorite
            currentIndex = lastFavorite
        }
    }
    
    private func goToNextFavorite() {
        guard !favoriteIndices.isEmpty else { return }
        
        // Find the smallest favorite index that is greater than currentIndex
        let nextFavorites = favoriteIndices.filter { $0 > currentIndex }
        if let targetIndex = nextFavorites.min() {
            currentIndex = targetIndex
        } else if let firstFavorite = favoriteIndices.min(), firstFavorite != currentIndex {
            // Wrap to first favorite
            currentIndex = firstFavorite
        }
    }
    
    // #55: Toggle single page marker
    private func toggleSinglePageMarker() {
        let added = CacheManager.shared.toggleSinglePageMarker(for: imageSource.url, at: currentIndex)
        print("[ImagePreviewView] Single page marker at \(currentIndex): \(added ? "ON" : "OFF")")
        spreadUpdateTrigger.toggle()
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
    
    func makeNSView(context: Context) -> QuickLookKeyView {
        let view = QuickLookKeyView()
        view.onClose = onClose
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onPreviousFavorite = onPreviousFavorite
        view.onNextFavorite = onNextFavorite
        view.onToggleFullScreen = onToggleFullScreen
        view.onToggleSinglePage = onToggleSinglePage  // #55
        print("[QuickLookKeyHandler] makeNSView called")
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            print("[QuickLookKeyHandler] makeFirstResponder called, success: \(view.window?.firstResponder === view)")
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
    }
    
    class QuickLookKeyView: NSView {
        var onClose: (() -> Void)?
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?
        var onPreviousFavorite: (() -> Void)?
        var onNextFavorite: (() -> Void)?
        var onToggleFullScreen: (() -> Void)?
        var onToggleSinglePage: (() -> Void)?  // #55
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            print("[QuickLookKeyView] keyDown: keyCode=\(event.keyCode), chars='\(event.charactersIgnoringModifiers ?? "nil")'")
            
            switch event.keyCode {
            // Space (49), Escape (53), Enter (36) - close
            case 49, 53, 36:
                print("[QuickLookKeyView] → Close triggered")
                onClose?()
                
            // Left arrow (123)
            case 123:
                print("[QuickLookKeyView] → Previous triggered")
                onPrevious?()
                
            // Right arrow (124)
            case 124:
                print("[QuickLookKeyView] → Next triggered")
                onNext?()
                
            default:
                // Check character keys
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    switch chars {
                    case "a":
                        print("[QuickLookKeyView] → Previous (a) triggered")
                        onPrevious?()
                    case "d":
                        print("[QuickLookKeyView] → Next (d) triggered")
                        onNext?()
                    case "z":
                        print("[QuickLookKeyView] → Previous favorite (z) triggered")
                        onPreviousFavorite?()
                    case "c":
                        print("[QuickLookKeyView] → Next favorite (c) triggered")
                        onNextFavorite?()
                    case "f":
                        print("[QuickLookKeyView] → FullScreen (f) triggered, calling onToggleFullScreen")
                        onToggleFullScreen?()
                    case "v":  // #55
                        print("[QuickLookKeyView] → Toggle single page (v) triggered")
                        onToggleSinglePage?()
                    default:
                        print("[QuickLookKeyView] → Unhandled key, passing to super")
                        super.keyDown(with: event)
                    }
                } else {
                    print("[QuickLookKeyView] → No chars, passing to super")
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
