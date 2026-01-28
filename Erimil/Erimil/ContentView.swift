//
//  ContentView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//  Updated: S010 (2025-01-11) - Sidebar double-click to open Slide Mode
//

import SwiftUI

struct ContentView: View {
    @State private var selectedFolderURL: URL?
    @State private var selectedSourceURL: URL?
    @State private var selectedSourceType: ImageSourceType?
    @State private var selectedPaths: Set<String> = []  // User's actual selections
    @State private var folderReloadTrigger = UUID()
    
    // Stable image source (not recreated on every render)
    @State private var currentImageSource: (any ImageSource)?
    
    // S005: Flag to reopen Slide Mode after source switch
    @State private var shouldReopenSlideMode: Bool = false
    
    // S010: Flag to open Slide Mode from sidebar double-click
    @State private var shouldOpenSlideMode: Bool = false
    
    // S016: Flag to reopen Viewer Mode after source switch
    @State private var shouldReopenViewerMode: Bool = false
    
    // 確認ダイアログ用
    @State private var pendingSourceURL: URL?
    @State private var pendingSourceType: ImageSourceType?
    @State private var showUnsavedAlert = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedFolderURL: $selectedFolderURL,
                selectedSourceURL: $selectedSourceURL,  // シンプルに直接バインド
                hasUnsavedChanges: !selectedPaths.isEmpty,
                onZipSelectionAttempt: { url in
                    handleSourceSelectionAttempt(url: url, type: .archive)
                },
                onFolderSelectionAttempt: { url in
                    handleSourceSelectionAttempt(url: url, type: .folder)
                },
                onPdfSelectionAttempt: { url in
                    handleSourceSelectionAttempt(url: url, type: .pdf)
                },
                onOpenSlideMode: { url in
                    openSlideModeForSource(url)
                },
                reloadTrigger: folderReloadTrigger
            )
        } detail: {
            if let imageSource = currentImageSource {
                ThumbnailGridView(
                    imageSource: imageSource,
                    selectedPaths: $selectedPaths,  // Changed: pass selectedPaths
                    onExportSuccess: {
                        reloadFolder()
                    },
                    onRequestNextSource: {
                        navigateToNextSource()
                    },
                    onRequestPreviousSource: {
                        navigateToPreviousSource()
                    },
                    shouldReopenSlideMode: $shouldReopenSlideMode,
                    shouldReopenViewerMode: $shouldReopenViewerMode
                )
                .id(imageSource.url)  // Force View recreation when source changes
                // S010: Trigger Slide Mode open from sidebar
                .onChange(of: shouldOpenSlideMode) { _, newValue in
                    if newValue {
                        shouldOpenSlideMode = false
                        // ThumbnailGridView will handle opening Slide Mode via shouldReopenSlideMode
                    }
                }
            } else {
                ContentUnavailableView(
                    "ZIPファイルまたはフォルダを選択",
                    systemImage: "archivebox",
                    description: Text("左のツリーから選んでください")
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onChange(of: selectedSourceURL) { oldURL, newURL in
            print("[ContentView] onChange(URL): \(oldURL?.lastPathComponent ?? "nil") → \(newURL?.lastPathComponent ?? "nil")")
            // Debounce: only update if both URL and Type are set
            if let _ = newURL, let _ = selectedSourceType {
                updateImageSource()
            } else if newURL == nil {
                currentImageSource = nil
            }
        }
        .onChange(of: selectedSourceType) { oldType, newType in
            print("[ContentView] onChange(Type): \(String(describing: oldType)) → \(String(describing: newType))")
            // Debounce: only update if both URL and Type are set
            if let _ = selectedSourceURL, let _ = newType {
                updateImageSource()
            } else if newType == nil {
                currentImageSource = nil
            }
        }
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
            print("[ContentView] Restored folder with security scope: \(restoredFolder.path)")
            selectedFolderURL = restoredFolder
            // Update the published property (without triggering didSet bookmark save)
            AppSettings.shared.lastOpenedFolderURL = restoredFolder
        } else {
            print("[ContentView] No folder to restore, or access denied")
        }
    }
    
    private func updateImageSource() {
        guard let url = selectedSourceURL, let type = selectedSourceType else {
            print("[ContentView] updateImageSource: no source selected")
            currentImageSource = nil
            return
        }
        
        // Check if already loaded same source
        if let current = currentImageSource, current.url == url {
            print("[ContentView] updateImageSource: same source already loaded, skipping")
            return
        }
        
        print("[ContentView] updateImageSource: creating new source for \(url.lastPathComponent) (type: \(type))")
        
        // Clear selections when switching sources to prevent stale paths
        selectedPaths.removeAll()
        
        switch type {
        case .archive:
            currentImageSource = ArchiveManager(zipURL: url)
        case .folder:
            currentImageSource = FolderManager(folderURL: url)
        case .pdf:
            currentImageSource = PDFManager(pdfURL: url)
        }
    }
    
    private func handleSourceSelectionAttempt(url: URL, type: ImageSourceType) {
        print("[ContentView] handleSourceSelectionAttempt: \(url.lastPathComponent) (type: \(type))")
        
        // 同じソースを選択した場合は何もしない
        if url == selectedSourceURL && type == selectedSourceType {
            print("[ContentView] Same source, ignoring")
            return
        }
        
        // 未保存の変更がある場合は確認
        if !selectedPaths.isEmpty {  // Changed: use selectedPaths
            pendingSourceURL = url
            pendingSourceType = type
            showUnsavedAlert = true
        } else {
            selectedSourceURL = url
            selectedSourceType = type
            selectedPaths.removeAll()
        }
    }
    
    private func discardAndNavigate() {
        selectedPaths.removeAll()
        if let url = pendingSourceURL, let type = pendingSourceType {
            selectedSourceURL = url
            selectedSourceType = type
            pendingSourceURL = nil
            pendingSourceType = nil
        }
    }
    
    private func reloadFolder() {
        folderReloadTrigger = UUID()
    }
    
    // MARK: - S010: Open Slide Mode from Sidebar
    
    private func openSlideModeForSource(_ url: URL) {
        print("[ContentView] openSlideModeForSource: \(url.lastPathComponent)")
        
        // S010: Always set the flag - ThumbnailGridView will handle it via onChange
        shouldReopenSlideMode = true
    }
    
    // MARK: - Source Navigation (S005)
    
    private func navigateToNextSource() {
        guard let currentURL = selectedSourceURL else {
            print("[ContentView] navigateToNextSource: no current source")
            return
        }
        
        if let nextURL = SourceNavigator.nextSource(from: currentURL) {
            print("[ContentView] navigateToNextSource: \(currentURL.lastPathComponent) → \(nextURL.lastPathComponent)")
            let type = inferSourceType(nextURL)
            
            // S005: Set flag to reopen mode after source switch
            if SlideWindowController.shared.isOpen {
                shouldReopenSlideMode = true
            }
            // S016: shouldReopenViewerMode is set by ViewerView before calling this
            
            selectedPaths.removeAll()
            selectedSourceURL = nextURL
            selectedSourceType = type
        } else {
            print("[ContentView] navigateToNextSource: no next source available")
        }
    }
    
    private func navigateToPreviousSource() {
        guard let currentURL = selectedSourceURL else {
            print("[ContentView] navigateToPreviousSource: no current source")
            return
        }
        
        if let prevURL = SourceNavigator.previousSource(from: currentURL) {
            print("[ContentView] navigateToPreviousSource: \(currentURL.lastPathComponent) → \(prevURL.lastPathComponent)")
            let type = inferSourceType(prevURL)
            
            // S005: Set flag to reopen mode after source switch
            if SlideWindowController.shared.isOpen {
                shouldReopenSlideMode = true
            }
            // S016: shouldReopenViewerMode is set by ViewerView before calling this
            
            selectedPaths.removeAll()
            selectedSourceURL = prevURL
            selectedSourceType = type
        } else {
            print("[ContentView] navigateToPreviousSource: no previous source available")
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
}

#Preview {
    ContentView()
}
