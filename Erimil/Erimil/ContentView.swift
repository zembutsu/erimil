//
//  ContentView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedFolderURL: URL?
    @State private var selectedZipURL: URL?
    @State private var excludedPaths: Set<String> = []
    @State private var folderReloadTrigger = UUID()  // リロード用トリガー
    
    // 確認ダイアログ用
    @State private var pendingZipURL: URL?
    @State private var showUnsavedAlert = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedFolderURL: $selectedFolderURL,
                selectedZipURL: $selectedZipURL,
                hasUnsavedChanges: !excludedPaths.isEmpty,
                onZipSelectionAttempt: { newURL in
                    handleZipSelectionAttempt(newURL)
                },
                reloadTrigger: folderReloadTrigger
            )
        } detail: {
            if let zipURL = selectedZipURL {
                ThumbnailGridView(
                    zipURL: zipURL,
                    excludedPaths: $excludedPaths,
                    onExportSuccess: {
                        reloadFolder()
                    }
                )
            } else {
                ContentUnavailableView(
                    "ZIPファイルを選択",
                    systemImage: "archivebox",
                    description: Text("左のツリーからZIPファイルを選んでください")
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert("未保存の変更があります", isPresented: $showUnsavedAlert) {
            Button("保存せず移動", role: .destructive) {
                discardAndNavigate()
            }
            Button("キャンセル", role: .cancel) {
                pendingZipURL = nil
            }
        } message: {
            Text("\(excludedPaths.count) 件の除外選択が保存されていません。破棄して別のZIPに移動しますか？")
        }
    }
    
    private func handleZipSelectionAttempt(_ newURL: URL) {
        if newURL == selectedZipURL {
            return
        }
        
        if !excludedPaths.isEmpty {
            pendingZipURL = newURL
            showUnsavedAlert = true
        } else {
            selectedZipURL = newURL
        }
    }
    
    private func discardAndNavigate() {
        excludedPaths.removeAll()
        if let pending = pendingZipURL {
            selectedZipURL = pending
            pendingZipURL = nil
        }
    }
    
    private func reloadFolder() {
        folderReloadTrigger = UUID()
    }
}

#Preview {
    ContentView()
}
