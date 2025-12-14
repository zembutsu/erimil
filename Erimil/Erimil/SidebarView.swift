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
    @State private var selectedNodeID: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            if let root = rootNode {
                List(selection: $selectedNodeID) {
                    OutlineGroup(root.children ?? [], children: \.children) { node in
                        NodeRowView(node: node)
                            .tag(node.id)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selectedNodeID) { _, newValue in
                    if let nodeID = newValue {
                        handleNodeSelection(nodeID)
                    }
                }
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
    
    private func handleNodeSelection(_ nodeID: UUID) {
        guard let node = findNode(by: nodeID, in: rootNode?.children ?? []) else {
            return
        }
        
        if node.isZip {
            onZipSelectionAttempt(node.url)
        } else if node.isDirectory {
            onFolderSelectionAttempt?(node.url)
        }
    }
    
    private func findNode(by id: UUID, in nodes: [FolderNode]) -> FolderNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let children = node.children,
               let found = findNode(by: id, in: children) {
                return found
            }
        }
        return nil
    }
    
    private func reloadTree() {
        selectedNodeID = nil
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
