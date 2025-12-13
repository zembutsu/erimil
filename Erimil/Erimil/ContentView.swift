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
    
    var body: some View {
        NavigationSplitView {
            // 左ペイン: フォルダツリー
            SidebarView(
                selectedFolderURL: $selectedFolderURL,
                selectedZipURL: $selectedZipURL
            )
        } detail: {
            // 右ペイン: サムネイルグリッド
            if let zipURL = selectedZipURL {
                ThumbnailGridView(zipURL: zipURL)
            } else {
                ContentUnavailableView(
                    "ZIPファイルを選択",
                    systemImage: "archivebox",
                    description: Text("左のツリーからZIPファイルを選んでください")
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
