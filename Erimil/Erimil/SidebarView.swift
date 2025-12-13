//
//  SidebarView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedFolderURL: URL?
    @Binding var selectedZipURL: URL?
    let hasUnsavedChanges: Bool
    let onZipSelectionAttempt: (URL) -> Void
    
    @State private var rootNode: FolderNode?
    
    var body: some View {
        VStack(spacing: 0) {
            if let root = rootNode {
                List {
                    OutlineGroup(root.children ?? [], children: \.children) { node in
                        NodeRowView(node: node, isSelected: selectedZipURL == node.url)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if node.isZip {
                                    onZipSelectionAttempt(node.url)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            } else {
                ContentUnavailableView(
                    "フォルダを選択",
                    systemImage: "folder",
                    description: Text("下のボタンからフォルダを選択してください")
                )
                .frame(maxHeight: .infinity)
            }
            
            Divider()
            
            Button("フォルダを開く...") {
                openFolderPicker()
            }
            .padding()
        }
        .navigationTitle("Erimil")
        .onChange(of: selectedFolderURL) { _, newValue in
            if let url = newValue {
                rootNode = FolderNode(url: url)
            } else {
                rootNode = nil
            }
        }
    }
    
    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            selectedFolderURL = panel.url
            // フォルダ変更時は選択をクリア（未保存確認は親で）
        }
    }
}

struct NodeRowView: View {
    let node: FolderNode
    let isSelected: Bool
    
    var body: some View {
        Label {
            Text(node.name)
        } icon: {
            if node.isZip {
                Image(systemName: "doc.zipper")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
}

#Preview {
    SidebarView(
        selectedFolderURL: .constant(nil),
        selectedZipURL: .constant(nil),
        hasUnsavedChanges: false,
        onZipSelectionAttempt: { _ in }
    )
}
