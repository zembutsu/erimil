//
//  ContentView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
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
    
    // 確認ダイアログ用
    @State private var pendingSourceURL: URL?
    @State private var pendingSourceType: ImageSourceType?
    @State private var showUnsavedAlert = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedFolderURL: $selectedFolderURL,
                selectedZipURL: Binding(
                    get: { selectedSourceType == .archive ? selectedSourceURL : nil },
                    set: { _ in }
                ),
                hasUnsavedChanges: !selectedPaths.isEmpty,  // Changed: use selectedPaths
                onZipSelectionAttempt: { url in
                    handleSourceSelectionAttempt(url: url, type: .archive)
                },
                onFolderSelectionAttempt: { url in
                    handleSourceSelectionAttempt(url: url, type: .folder)
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
                    }
                )
                .id(imageSource.url)  // Force View recreation when source changes
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
}

#Preview {
    ContentView()
}
