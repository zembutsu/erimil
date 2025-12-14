//
//  SidebarView.swift
//  Erimil
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
        .onAppear {
            // Load tree on initial appear (for restored folder)
            print("[SidebarView] onAppear, selectedFolderURL: \(selectedFolderURL?.path ?? "nil")")
            reloadTree()
        }
        .onChange(of: selectedFolderURL) { oldValue, newValue in
            print("[SidebarView] onChange: \(oldValue?.path ?? "nil") → \(newValue?.path ?? "nil")")
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
        print("[SidebarView] reloadTree called, selectedFolderURL: \(selectedFolderURL?.path ?? "nil")")
        if let url = selectedFolderURL {
            // Verify folder exists
            if FileManager.default.fileExists(atPath: url.path) {
                rootNode = FolderNode(url: url)
                print("[SidebarView] rootNode created, children count: \(rootNode?.children?.count ?? 0)")
            } else {
                print("[SidebarView] ERROR: Folder does not exist: \(url.path)")
                // Fallback to Desktop
                fallbackToDesktop()
            }
        } else {
            rootNode = nil
        }
    }
    
    private func fallbackToDesktop() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        print("[SidebarView] Fallback to Desktop: \(desktop?.path ?? "nil")")
        if let desktop = desktop {
            selectedFolderURL = desktop
            AppSettings.shared.lastOpenedFolderURL = desktop
        }
    }
    
    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "表示するフォルダを選択してください"
        panel.prompt = "選択"
        
        print("[SidebarView] Opening folder picker...")
        
        let response = panel.runModal()
        print("[SidebarView] Folder picker response: \(response == .OK ? "OK" : "Cancel")")
        
        if response == .OK, let url = panel.url {
            print("[SidebarView] Selected folder: \(url.path)")
            
            // Force update even if same folder (by clearing first)
            if selectedFolderURL == url {
                print("[SidebarView] Same folder selected, forcing reload")
                rootNode = nil
            }
            
            selectedFolderURL = url
            AppSettings.shared.lastOpenedFolderURL = url
            
            // Explicit reload in case onChange doesn't fire
            reloadTree()
        } else {
            print("[SidebarView] Folder selection cancelled or failed")
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
