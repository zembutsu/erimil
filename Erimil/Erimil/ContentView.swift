//
//  ContentView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//  Updated: S010 (2025-01-11) - Sidebar double-click to open Slide Mode
//  Updated: S050 (2026-02-22) - @Observable SourceSelection model (#93)
//  Updated: S090 (2026-03-21) - #215 Phase 1: NavigationSplitView → NSSplitViewController
//

import SwiftUI
import os

struct ContentView: View {
    @State private var selectedFolderURL: URL?
    // S050: Replaced @State selectedSourceURL / selectedSourceType / currentImageSource
    //       with single @Observable model. Eliminates onChange × 2 chain.
    @State private var sourceSelection = SourceSelection()
    @State private var selectedPaths: Set<String> = []  // User's actual selections
    @State private var folderReloadTrigger = UUID()
    
    // S005: Flag to reopen Slide Mode after source switch
    @State private var shouldReopenSlideMode: Bool = false
    
    // S090: shouldOpenSlideMode removed — was dead code (never set to true).
    //       openSlideModeForSource() uses shouldReopenSlideMode instead.
    
    // S051: Track Viewer Mode state for view recreation (#121)
    @State private var isInViewerMode: Bool = false
    
    // S016: Flag to reopen Viewer Mode after source switch
    @State private var shouldReopenViewerMode: Bool = false
    
    // 確認ダイアログ用
    @State private var pendingSourceURL: URL?
    @State private var pendingSourceType: ImageSourceType?
    @State private var showUnsavedAlert = false
    
    var body: some View {
        // S090: Expand @Observable properties explicitly so SwiftUI's dependency
        // tracking fires updateNSViewController when they change.
        let currentURL = sourceSelection.currentURL
        let currentSource = sourceSelection.currentSource

        ErimilSplitViewRepresentable(
            currentURL: currentURL,
            currentSource: currentSource,
            sourceSelection: sourceSelection,
            selectedFolderURL: $selectedFolderURL,
            folderReloadTrigger: folderReloadTrigger,
            selectedPaths: $selectedPaths,
            shouldReopenSlideMode: $shouldReopenSlideMode,
            shouldReopenViewerMode: $shouldReopenViewerMode,
            isInViewerMode: $isInViewerMode,
            onSourceSelect: { url, type in
                handleSourceSelectionAttempt(url: url, type: type)
            },
            onOpenSlideMode: { url in
                openSlideModeForSource(url)
            },
            onExportSuccess: { reloadFolder() },
            onRequestNextSource: { navigateToNextSource() },
            onRequestPreviousSource: { navigateToPreviousSource() },
            onRequestSourceJump: { steps in navigateToSourceBySteps(steps) }
        )
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                } label: {
                    Image(systemName: "sidebar.leading")
                }
            }
        }
        // S050: onChange × 2 chain REMOVED — model.select() handles everything atomically
        .alert("未保存の変更があります", isPresented: $showUnsavedAlert) {
            Button("保存せず移動", role: .destructive) {
                discardAndNavigate()
            }
            Button("キャンセル", role: .cancel) {
                pendingSourceURL = nil
                pendingSourceType = nil
            }
        } message: {
            Text("\(selectedPaths.count) 件の選択が保存されていません。破棄して別の場所に移動しますか？")
        }
        .onAppear {
            restoreLastOpenedFolder()
        }
    }
    
    private func restoreLastOpenedFolder() {
        // Only restore if no folder is currently selected (first launch)
        guard selectedFolderURL == nil else {
            return
        }
        
        // Use security-scoped bookmark restoration
        if let restoredFolder = AppSettings.shared.restoreAndAccessLastOpenedFolder() {
            Logger.content.info("Restored folder with security scope: \(restoredFolder.path)")
            selectedFolderURL = restoredFolder
            // Update the published property (without triggering didSet bookmark save)
            AppSettings.shared.lastOpenedFolderURL = restoredFolder
        } else {
            Logger.content.debug("No folder to restore, or access denied")
        }
    }
    
    // S050: updateImageSource() REMOVED — model.select() replaces it entirely
    
    private func handleSourceSelectionAttempt(url: URL, type: ImageSourceType) {
        // S050: T1 — callback arrived at ContentView
        SourceSwitchTiming.mark("callback")
        
        // 同じソースを選択した場合は何もしない
        if url == sourceSelection.currentURL && type == sourceSelection.currentType {
            return
        }
        
        // 未保存の変更がある場合は確認
        if !selectedPaths.isEmpty {
            pendingSourceURL = url
            pendingSourceType = type
            showUnsavedAlert = true
        } else {
            // S051: Preserve Viewer Mode across view recreation
            if isInViewerMode {
                shouldReopenViewerMode = true
            }
            // S050: Direct model call — atomic, no intermediate @State
            sourceSelection.select(url: url, type: type)
            selectedPaths.removeAll()
        }
    }
    
    private func discardAndNavigate() {
        selectedPaths.removeAll()
        if let url = pendingSourceURL, let type = pendingSourceType {
            if isInViewerMode {
                shouldReopenViewerMode = true
            }
            // S050: Direct model call
            sourceSelection.select(url: url, type: type)
            pendingSourceURL = nil
            pendingSourceType = nil
        }
    }
    
    private func reloadFolder() {
        folderReloadTrigger = UUID()
    }
    
    // MARK: - S010: Open Slide Mode from Sidebar
    
    private func openSlideModeForSource(_ url: URL) {
        Logger.content.debug("openSlideModeForSource: \(url.lastPathComponent)")
        
        // S010: Always set the flag - ThumbnailGridView will handle it via onChange
        shouldReopenSlideMode = true
    }
    
    // MARK: - Source Navigation (S005)
    
    private func navigateToNextSource() {
        guard let currentURL = sourceSelection.currentURL else {
            Logger.content.debug("navigateToNextSource: no current source")
            return
        }
        
        if let nextURL = SourceNavigator.nextSource(from: currentURL) {
            Logger.content.debug("navigateToNextSource: \(currentURL.lastPathComponent) → \(nextURL.lastPathComponent)")
            let type = inferSourceType(nextURL)
            
            // S005: Set flag to reopen mode after source switch
            if SlideWindowController.shared.isOpen {
                shouldReopenSlideMode = true
            }
            // S016: shouldReopenViewerMode is set by ViewerView before calling this
            
            selectedPaths.removeAll()
            // S050: Direct model call
            sourceSelection.select(url: nextURL, type: type)
        } else {
            Logger.content.debug("navigateToNextSource: no next source available")
        }
    }
    
    private func navigateToPreviousSource() {
        guard let currentURL = sourceSelection.currentURL else {
            Logger.content.debug("navigateToPreviousSource: no current source")
            return
        }
        
        if let prevURL = SourceNavigator.previousSource(from: currentURL) {
            Logger.content.debug("navigateToPreviousSource: \(currentURL.lastPathComponent) → \(prevURL.lastPathComponent)")
            let type = inferSourceType(prevURL)
            
            // S005: Set flag to reopen mode after source switch
            if SlideWindowController.shared.isOpen {
                shouldReopenSlideMode = true
            }
            // S016: shouldReopenViewerMode is set by ViewerView before calling this
            
            selectedPaths.removeAll()
            // S050: Direct model call
            sourceSelection.select(url: prevURL, type: type)
        } else {
            Logger.content.debug("navigateToPreviousSource: no previous source available")
        }
    }
    
    /// Infer ImageSourceType from URL (ZIP file or directory)
    private func inferSourceType(_ url: URL) -> ImageSourceType {
        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            return .archive
        } else if ext == "pdf" {
            return .pdf
        } else {
            return .folder
        }
    }
    
    // MARK: - #143: N-Step Source Navigation
    
    private func navigateToSourceBySteps(_ steps: Int) {
        guard let currentURL = sourceSelection.currentURL else { return }
        
        if let targetURL = SourceNavigator.jumpSource(from: currentURL, by: steps) {
            Logger.content.debug("navigateToSourceBySteps(\(steps)): \(currentURL.lastPathComponent) → \(targetURL.lastPathComponent)")
            let type = inferSourceType(targetURL)
            
            if SlideWindowController.shared.isOpen {
                shouldReopenSlideMode = true
            }
            
            selectedPaths.removeAll()
            sourceSelection.select(url: targetURL, type: type)
        }
    }
}

// S090: DetailContainerView struct DELETED.
// Replaced by DetailContainerViewController (AppKit).
// The .id(imageSource.url) pattern is replaced by NSHostingView swap.

#Preview {
    ContentView()
}
