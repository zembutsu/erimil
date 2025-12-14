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
    @State private var excludedPaths: Set<String> = []
    @State private var folderReloadTrigger = UUID()
    
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
                hasUnsavedChanges: !excludedPaths.isEmpty,
                onZipSelectionAttempt: { url in
                    handleSourceSelectionAttempt(url: url, type: .archive)
                },
                onFolderSelectionAttempt: { url in
                    handleSourceSelectionAttempt(url: url, type: .folder)
                },
                reloadTrigger: folderReloadTrigger
            )
        } detail: {
            if let sourceURL = selectedSourceURL, let sourceType = selectedSourceType {
                ThumbnailGridView(
                    imageSource: createImageSource(url: sourceURL, type: sourceType),
                    excludedPaths: $excludedPaths,
                    onExportSuccess: {
                        reloadFolder()
                    }
                )
            } else {
                ContentUnavailableView(
                    "ZIPファイルまたはフォルダを選択",
                    systemImage: "archivebox",
                    description: Text("左のツリーから選んでください")
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert("未保存の変更があります", isPresented: $showUnsavedAlert) {
            Button("保存せず移動", role: .destructive) {
                discardAndNavigate()
            }
            Button("キャンセル", role: .cancel) {
                pendingSourceURL = nil
                pendingSourceType = nil
            }
        } message: {
            Text("\(excludedPaths.count) 件の除外選択が保存されていません。破棄して別の場所に移動しますか？")
        }
    }
    
    private func createImageSource(url: URL, type: ImageSourceType) -> any ImageSource {
        switch type {
        case .archive:
            return ArchiveManager(zipURL: url)
        case .folder:
            return FolderManager(folderURL: url)
        }
    }
    
    private func handleSourceSelectionAttempt(url: URL, type: ImageSourceType) {
        // 同じソースを選択した場合は何もしない
        if url == selectedSourceURL && type == selectedSourceType {
            return
        }
        
        // 未保存の変更がある場合は確認
        if !excludedPaths.isEmpty {
            pendingSourceURL = url
            pendingSourceType = type
            showUnsavedAlert = true
        } else {
            selectedSourceURL = url
            selectedSourceType = type
            excludedPaths.removeAll()
        }
    }
    
    private func discardAndNavigate() {
        excludedPaths.removeAll()
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
