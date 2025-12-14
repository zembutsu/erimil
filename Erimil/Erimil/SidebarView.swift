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
    var onFolderSelectionAttempt: ((URL) -> Void)?
    let reloadTrigger: UUID
    
    @State private var rootNode: FolderNode?
    @State private var selectedNodeURL: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            if let root = rootNode {
                List {
                    OutlineGroup(root.children ?? [], children: \.children) { node in
                        NodeRowView(
                            node: node,
                            isSelected: selectedNodeURL == node.url
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleNodeTap(node)
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
        .onChange(of: selectedFolderURL) { _, _ in
            reloadTree()
        }
        .onChange(of: reloadTrigger) { _, _ in
            reloadTree()
        }
    }
    
    private func handleNodeTap(_ node: FolderNode) {
        selectedNodeURL = node.url
        
        if node.isZip {
            onZipSelectionAttempt(node.url)
        } else if node.isDirectory {
            // フォルダの場合、画像があれば右ペインに表示
            onFolderSelectionAttempt?(node.url)
        }
    }
    
    private func reloadTree() {
        if let url = selectedFolderURL {
            rootNode = FolderNode(url: url)
        } else {
            rootNode = nil
        }
    }
    
    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            selectedFolderURL = panel.url
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
        onZipSelectionAttempt: { _ in },
        onFolderSelectionAttempt: { _ in },
        reloadTrigger: UUID()
    )
}
