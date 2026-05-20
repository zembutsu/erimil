//
//  SidebarView.swift
//  Erimil
//
//  Updated: S010 (2025-01-11) - Double-click to open Slide Mode
//  Updated: S023 (2026-01-27) - Preserve expansion state on reload
//  Updated: S050 (2026-02-22) - Unified source selection callback (#93)
//  Updated: #277 — Migrated from SwiftUI List to NSOutlineView
//

import SwiftUI
import os

struct SidebarView: View {
    @Binding var selectedFolderURL: URL?
    // S050: Changed from @Binding to read-only — sidebar doesn't write to source selection
    let sourceSelection: SourceSelection
    // S050: 3 callbacks (onZip/Folder/Pdf) → 1 unified callback
    let onSourceSelect: (URL, ImageSourceType) -> Void
    var onOpenSlideMode: ((URL) -> Void)?  // S010: Double-click to open Slide Mode
    let reloadTrigger: UUID

    // #277: Root-level children for NSOutlineView.
    // Replaces childrenCache + expandedNodes — both now managed inside SidebarOutlineView.
    @State private var rootNode: FolderNode?
    @State private var rootChildren: [FolderNode] = []
    @State private var sidebarReloadID = UUID()

    var body: some View {
        let _ = SourceSwitchTiming.count("sidebar.body")
        VStack(spacing: 0) {
            if rootNode != nil {
                // #277: NSOutlineView replaces List + DisclosureGroup + NodeTreeView
                SidebarOutlineView(
                    rootChildren: rootChildren,
                    selectedSourceURL: sourceSelection.currentURL,
                    reloadID: sidebarReloadID,
                    onSourceSelect: onSourceSelect,
                    onOpenSlideMode: onOpenSlideMode
                )
            } else {
                ContentUnavailableView(
                    String(localized: "sidebar.selectFolder", defaultValue: "Select a Folder"),
                    systemImage: "folder",
                    description: Text(String(localized: "sidebar.selectFolderDescription", defaultValue: "Choose a folder from the button below"))
                )
                .frame(maxHeight: .infinity)
            }

            Divider()

            Button(String(localized: "sidebar.openFolder", defaultValue: "Open Folder...")) {
                openFolderPicker()
            }
            .padding()
        }
        .navigationTitle("Erimil")
        .onAppear {
            Logger.sidebar.debug("onAppear, selectedFolderURL: \(selectedFolderURL?.path ?? "nil")")
            reloadTree()
        }
        .onChange(of: selectedFolderURL) { oldValue, newValue in
            SourceSwitchTiming.mark("sidebar.onChange.in")
            Logger.sidebar.debug("onChange: \(oldValue?.path ?? "nil") → \(newValue?.path ?? "nil")")
            reloadTree()
            SourceSwitchTiming.mark("sidebar.onChange.out")
        }
        .onChange(of: reloadTrigger) { _, _ in
            // S023: reloadTree without clearing expansion (NSOutlineView preserves it internally)
            reloadTree()
        }
    }

    // MARK: - Tree Loading

    private func reloadTree() {
        Logger.sidebar.debug("reloadTree called, selectedFolderURL: \(selectedFolderURL?.path ?? "nil")")
        if let url = selectedFolderURL {
            if FileManager.default.fileExists(atPath: url.path) {
                let start = CFAbsoluteTimeGetCurrent()
                let children = FolderNode.loadChildren(of: url)
                rootChildren = children
                rootNode = FolderNode(url: url)
                sidebarReloadID = UUID()  // #277: Force NSOutlineView reload
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                Logger.sidebar.info("rootNode created, children count: \(children.count, privacy: .public), took \(String(format: "%.0f", elapsed))ms")
            } else {
                Logger.sidebar.error("ERROR: Folder does not exist: \(url.path)")
                fallbackToDesktop()
            }
        } else {
            rootNode = nil
            rootChildren = []
        }
    }

    // MARK: - Folder Picker

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
        panel.message = String(localized: "sidebar.panel.message", defaultValue: "Select a folder to display")
        panel.prompt = String(localized: "sidebar.panel.prompt", defaultValue: "Select")

        Logger.sidebar.debug("Opening folder picker...")

        let response = panel.runModal()
        Logger.sidebar.debug("Folder picker response: \(response == .OK ? "OK" : "Cancel")")

        if response == .OK, let url = panel.url {
            Logger.sidebar.debug("Selected folder: \(url.path)")

            // Force update even if same folder (by clearing first)
            if selectedFolderURL == url {
                Logger.sidebar.debug("Same folder selected, forcing reload")
                // #277: Reset to fresh state — same as opening a new folder
                sourceSelection.clear()
                let children = FolderNode.loadChildren(of: url)
                rootChildren = children
                sidebarReloadID = UUID()
                return
            }

            selectedFolderURL = url
            AppSettings.shared.lastOpenedFolderURL = url

            // Explicit reload in case onChange doesn't fire
            reloadTree()
        } else {
            Logger.sidebar.error("Folder selection cancelled or failed")
        }
    }
}

// MARK: - #277: NodeTreeView, NodeRowView, InstantClickHandler REMOVED
// Replaced by SidebarOutlineView (NSOutlineView wrapper).
// Row rendering, selection, double-click, expansion — all handled by NSOutlineView natively.

#Preview {
    SidebarView(
        selectedFolderURL: .constant(nil),
        sourceSelection: SourceSelection(),
        onSourceSelect: { _, _ in },
        onOpenSlideMode: { _ in },
        reloadTrigger: UUID()
    )
}
