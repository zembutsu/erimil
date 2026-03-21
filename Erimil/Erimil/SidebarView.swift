//
//  SidebarView.swift
//  Erimil
//
//  Updated: S010 (2025-01-11) - Double-click to open Slide Mode
//  Updated: S023 (2026-01-27) - Preserve expansion state on reload
//  Updated: S050 (2026-02-22) - Unified source selection callback (#93)
//

import SwiftUI
import os

struct SidebarView: View {
    @Binding var selectedFolderURL: URL?
    // S050: Changed from @Binding to read-only — sidebar doesn't write to source selection
    let currentSourceURL: URL?
    // S050: 3 callbacks (onZip/Folder/Pdf) → 1 unified callback
    let onSourceSelect: (URL, ImageSourceType) -> Void
    var onOpenSlideMode: ((URL) -> Void)?  // S010: Double-click to open Slide Mode
    let reloadTrigger: UUID
    
    @State private var rootNode: FolderNode?
    @State private var expandedNodes: Set<URL> = []  // S023: Track expanded folders
    @State private var childrenCache: [URL: [FolderNode]] = [:]  // #216: Lazy-loaded children
    
    var body: some View {
        VStack(spacing: 0) {
            if let root = rootNode {
                List {
                    ForEach(childrenCache[root.url] ?? [], id: \.url) { node in
                        NodeTreeView(
                            node: node,
                            selectedSourceURL: currentSourceURL,
                            expandedNodes: $expandedNodes,
                            childrenCache: childrenCache,
                            onTap: handleNodeTap,
                            onDoubleTap: handleNodeDoubleTap,
                            onLoadChildren: loadChildrenFor
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
            Logger.sidebar.debug("onAppear, selectedFolderURL: \(selectedFolderURL?.path ?? "nil")")
            reloadTree()
        }
        .onChange(of: selectedFolderURL) { oldValue, newValue in
            Logger.sidebar.debug("onChange: \(oldValue?.path ?? "nil") → \(newValue?.path ?? "nil")")
            // S023: Clear expansion state only when root folder changes
            if oldValue != newValue {
                expandedNodes.removeAll()
                childrenCache = [:]  // #216: Clear lazy cache for new root
            }
            reloadTree()
        }
        .onChange(of: reloadTrigger) { _, _ in
            // S023: reloadTree without clearing expandedNodes
            childrenCache = [:]  // #216: Clear lazy cache to pick up changes
            reloadTree()
        }
    }
    
    // S050: Unified handler — determines type from node, calls single callback
    private func handleNodeTap(_ node: FolderNode) {
        if node.isZip {
            onSourceSelect(node.url, .archive)
        } else if node.isPdf {
            onSourceSelect(node.url, .pdf)
        } else if node.isDirectory {
            onSourceSelect(node.url, .folder)
        }
    }
    
    // S010: Double-click handler
    private func handleNodeDoubleTap(_ node: FolderNode) {
        // First select the node (same as single tap)
        if node.isZip {
            onSourceSelect(node.url, .archive)
        } else if node.isPdf {
            onSourceSelect(node.url, .pdf)
        } else if node.isDirectory {
            onSourceSelect(node.url, .folder)
        }
        
        // Then open Slide Mode after a brief delay (to let selection complete)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onOpenSlideMode?(node.url)
        }
    }
    
    private func reloadTree() {
        Logger.sidebar.debug("reloadTree called, selectedFolderURL: \(selectedFolderURL?.path ?? "nil")")
            if let url = selectedFolderURL {
                if FileManager.default.fileExists(atPath: url.path) {
                    let start = CFAbsoluteTimeGetCurrent()
                    // #216: Set cache BEFORE rootNode — ensures children are available
                    // when SwiftUI re-evaluates body on rootNode change
                    let children = FolderNode.loadChildren(of: url)
                    childrenCache[url] = children
                    rootNode = FolderNode(url: url)
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    Logger.sidebar.info("rootNode created, children count: \(children.count, privacy: .public), took \(String(format: "%.0f", elapsed))ms")
            } else {
                Logger.sidebar.error("ERROR: Folder does not exist: \(url.path)")
                // Fallback to Desktop
                fallbackToDesktop()
            }
        } else {
            rootNode = nil
            childrenCache = [:]
        }
    }
    
    /// #216: Load children on demand when DisclosureGroup expands
    private func loadChildrenFor(url: URL) {
        guard childrenCache[url] == nil else { return }
        childrenCache[url] = FolderNode.loadChildren(of: url)
    }
    
    private func fallbackToDesktop() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        Logger.sidebar.debug("Fallback to Desktop: \(desktop?.path ?? "nil")")
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
        
        Logger.sidebar.debug("Opening folder picker...")
        
        let response = panel.runModal()
        Logger.sidebar.debug("Folder picker response: \(response == .OK ? "OK" : "Cancel")")
        
        if response == .OK, let url = panel.url {
            Logger.sidebar.debug("Selected folder: \(url.path)")
            
            // Force update even if same folder (by clearing first)
            if selectedFolderURL == url {
                Logger.sidebar.debug("Same folder selected, forcing reload")
                rootNode = nil
                childrenCache = [:]  // #216: Clear lazy cache
                // S023: Don't clear expandedNodes for same folder reload
            }
            
            selectedFolderURL = url
            AppSettings.shared.lastOpenedFolderURL = url
            
            // Explicit reload in case onChange doesn't fire
            reloadTree()
        } else {
            Logger.sidebar.error("Folder selection cancelled or failed")
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
    let childrenCache: [URL: [FolderNode]]  // #216: Lazy-loaded children
    let onTap: (FolderNode) -> Void
    let onDoubleTap: (FolderNode) -> Void
    let onLoadChildren: (URL) -> Void  // #216: Request children load on expand
    
    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedNodes.contains(node.url) },
            set: { newValue in
                if newValue {
                    expandedNodes.insert(node.url)
                    // #216: Load children on demand when expanding
                    onLoadChildren(node.url)
                } else {
                    expandedNodes.remove(node.url)
                }
            }
        )
    }
    
    private var effectiveChildren: [FolderNode] {
        childrenCache[node.url] ?? []
    }
    
    private var hasChildren: Bool {
        // #216: If children are loaded, check actual count.
        // If not loaded yet, assume directories might have children (show disclosure triangle).
        if let cached = childrenCache[node.url] {
            return !cached.isEmpty
        }
        return node.isDirectory
    }
    
    var body: some View {
        if hasChildren {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(effectiveChildren, id: \.url) { child in
                    NodeTreeView(
                        node: child,
                        selectedSourceURL: selectedSourceURL,
                        expandedNodes: $expandedNodes,
                        childrenCache: childrenCache,
                        onTap: onTap,
                        onDoubleTap: onDoubleTap,
                        onLoadChildren: onLoadChildren
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
        .overlay(
            InstantClickHandler(
                onSingleClick: { onTap(node) },
                onDoubleClick: { onDoubleTap(node) }
            )
        )
    }
}

// MARK: - Instant Click Handler (S036: eliminate tap gesture delay)
// macOS mouseDown fires immediately with clickCount, no disambiguation delay.

struct InstantClickHandler: NSViewRepresentable {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void
    
    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }
    
    func updateNSView(_ nsView: ClickView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
    
    class ClickView: NSView {
        var onSingleClick: (() -> Void)?
        var onDoubleClick: (() -> Void)?
        
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
            } else if event.clickCount == 1 {
                // S050: T0 — click fires
                SourceSwitchTiming.start("click")
                onSingleClick?()
            }
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
        currentSourceURL: nil,
        onSourceSelect: { _, _ in },
        onOpenSlideMode: { _ in },
        reloadTrigger: UUID()
    )
}
