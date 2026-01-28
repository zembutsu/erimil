//
//  SidebarView.swift
//  Erimil
//
//  Updated: S010 (2025-01-11) - Double-click to open Slide Mode
//  Updated: S023 (2026-01-27) - Preserve expansion state on reload
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedFolderURL: URL?
    @Binding var selectedSourceURL: URL?
    let hasUnsavedChanges: Bool
    let onZipSelectionAttempt: (URL) -> Void
    var onFolderSelectionAttempt: ((URL) -> Void)?
    var onPdfSelectionAttempt: ((URL) -> Void)?
    var onOpenSlideMode: ((URL) -> Void)?  // S010: Double-click to open Slide Mode
    let reloadTrigger: UUID
    
    @State private var rootNode: FolderNode?
    @State private var expandedNodes: Set<URL> = []  // S023: Track expanded folders
    
    var body: some View {
        VStack(spacing: 0) {
            if let root = rootNode {
                List {
                    ForEach(root.children ?? [], id: \.url) { node in
                        NodeTreeView(
                            node: node,
                            selectedSourceURL: selectedSourceURL,
                            expandedNodes: $expandedNodes,
                            onTap: handleNodeTap,
                            onDoubleTap: handleNodeDoubleTap
                        )
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
            
            let cacheInfo = CacheManager.shared.getCacheInfo()
            if cacheInfo.fileCount > 0 {
                HStack {
                    Image(systemName: "photo.stack")
                        .foregroundStyle(.secondary)
                    Text("\(cacheInfo.fileCount)枚キャッシュ済")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("(\(formatBytes(cacheInfo.totalSize)))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
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
            // S023: Clear expansion state only when root folder changes
            if oldValue != newValue {
                expandedNodes.removeAll()
            }
            reloadTree()
        }
        .onChange(of: reloadTrigger) { _, _ in
            // S023: reloadTree without clearing expandedNodes
            reloadTree()
        }
    }
    
    private func handleNodeTap(_ node: FolderNode) {
        if node.isZip {
            onZipSelectionAttempt(node.url)
        } else if node.isPdf {
            onPdfSelectionAttempt?(node.url)
        } else if node.isDirectory {
            // フォルダの場合、画像があれば右ペインに表示
            onFolderSelectionAttempt?(node.url)
        }
    }
    
    // S010: Double-click handler
    private func handleNodeDoubleTap(_ node: FolderNode) {
        // First select the node (same as single tap)
        if node.isZip {
            onZipSelectionAttempt(node.url)
        } else if node.isPdf {
            onPdfSelectionAttempt?(node.url)
        } else if node.isDirectory {
            onFolderSelectionAttempt?(node.url)
        }
        
        // Then open Slide Mode after a brief delay (to let selection complete)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onOpenSlideMode?(node.url)
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
                // S023: Don't clear expandedNodes for same folder reload
            }
            
            selectedFolderURL = url
            AppSettings.shared.lastOpenedFolderURL = url
            
            // Explicit reload in case onChange doesn't fire
            reloadTree()
        } else {
            print("[SidebarView] Folder selection cancelled or failed")
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - NodeTreeView (S023: Recursive tree with preserved expansion)

struct NodeTreeView: View {
    let node: FolderNode
    let selectedSourceURL: URL?
    @Binding var expandedNodes: Set<URL>
    let onTap: (FolderNode) -> Void
    let onDoubleTap: (FolderNode) -> Void
    
    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedNodes.contains(node.url) },
            set: { newValue in
                if newValue {
                    expandedNodes.insert(node.url)
                } else {
                    expandedNodes.remove(node.url)
                }
            }
        )
    }
    
    private var hasChildren: Bool {
        guard let children = node.children else { return false }
        return !children.isEmpty
    }
    
    var body: some View {
        if hasChildren {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children ?? [], id: \.url) { child in
                    NodeTreeView(
                        node: child,
                        selectedSourceURL: selectedSourceURL,
                        expandedNodes: $expandedNodes,
                        onTap: onTap,
                        onDoubleTap: onDoubleTap
                    )
                }
            } label: {
                nodeLabel
            }
        } else {
            nodeLabel
        }
    }
    
    private var nodeLabel: some View {
        NodeRowView(
            node: node,
            isSelected: selectedSourceURL == node.url
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleTap(node)
        }
        .onTapGesture(count: 1) {
            onTap(node)
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
            } else if node.isPdf {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.red)
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
        selectedSourceURL: .constant(nil),
        hasUnsavedChanges: false,
        onZipSelectionAttempt: { _ in },
        onFolderSelectionAttempt: { _ in },
        onOpenSlideMode: { _ in },
        reloadTrigger: UUID()
    )
}
