//
//  SidebarOutlineView.swift
//  Erimil
//
//  Created: #277 — Sidebar: migrate from SwiftUI List to NSOutlineView
//

import SwiftUI
import AppKit
import os

// MARK: - SidebarItem (class wrapper for NSOutlineView)

/// NSOutlineView requires reference-type items for identity tracking.
/// Wraps FolderNode (struct) without modifying the model layer.
class SidebarItem: NSObject {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isZip: Bool
    let isPdf: Bool
    private(set) var children: [SidebarItem]?
    private(set) var isChildrenLoaded: Bool = false

    init(node: FolderNode) {
        self.url = node.url
        self.name = node.name
        self.isDirectory = node.isDirectory
        self.isZip = node.isZip
        self.isPdf = node.isPdf
        super.init()
    }

    /// Lazy-load children on first access (same pattern as #216 childrenCache)
    func loadChildrenIfNeeded() {
        guard !isChildrenLoaded, isExpandable else { return }
        isChildrenLoaded = true
        let childNodes = FolderNode.loadChildren(of: url)
        children = childNodes.map { SidebarItem(node: $0) }
    }

    /// Directories (excluding ZIP/PDF) are expandable
    var isExpandable: Bool {
        isDirectory && !isZip && !isPdf
    }

    var childCount: Int {
        children?.count ?? 0
    }

    var sourceType: ImageSourceType {
        if isZip { return .archive }
        if isPdf { return .pdf }
        return .folder
    }
}

// MARK: - SidebarOutlineView (NSViewRepresentable)

struct SidebarOutlineView: NSViewRepresentable {
    let rootChildren: [FolderNode]
    let selectedSourceURL: URL?
    let reloadID: UUID  // Force NSOutlineView reload when this changes
    let onSourceSelect: (URL, ImageSourceType) -> Void
    let onOpenSlideMode: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 14
        outlineView.autoresizesOutlineColumn = false
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator

        // Double-click
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        // Single selection only
        outlineView.allowsMultipleSelection = false

        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView

        // Build initial items and load
        context.coordinator.lastReloadID = reloadID
        context.coordinator.rebuildItems(from: rootChildren)
        outlineView.reloadData()

        // Sync initial selection
        context.coordinator.syncSelection(to: selectedSourceURL)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // DEBUG: #277 reload detection
        print("[SidebarOutlineView.updateNSView] reloadID=\(reloadID), lastReloadID=\(String(describing: coordinator.lastReloadID)), match=\(coordinator.lastReloadID == reloadID)")
        
        // Reload when reloadID changes (covers both content change and same-folder forced reload)
        if coordinator.lastReloadID != reloadID {
            coordinator.lastReloadID = reloadID
            let expandedURLs = coordinator.saveExpandedState()
            coordinator.rebuildItems(from: rootChildren)
            print("[SidebarOutlineView] reloading — outlineView is \(coordinator.outlineView == nil ? "nil ⚠️" : "alive"), rootItems: \(coordinator.rootItems.count)")
            coordinator.outlineView?.reloadData()
            print("[SidebarOutlineView] after reload — numberOfRows: \(coordinator.outlineView?.numberOfRows ?? -1)")
            coordinator.restoreExpandedState(expandedURLs)
        }

        // Sync selection from outside (e.g. source navigation)
        coordinator.syncSelection(to: selectedSourceURL)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: SidebarOutlineView
        var rootItems: [SidebarItem] = []
        weak var outlineView: NSOutlineView?
        /// Tracks the last applied reloadID to detect changes
        var lastReloadID: UUID?
        /// Guard to prevent selection feedback loop
        private var isSyncingSelection = false

        init(parent: SidebarOutlineView) {
            self.parent = parent
            super.init()
        }

        /// Convert FolderNode array to SidebarItem array
        func rebuildItems(from nodes: [FolderNode]) {
            rootItems = nodes.map { SidebarItem(node: $0) }
        }

        // MARK: Data Source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if let sidebarItem = item as? SidebarItem {
                sidebarItem.loadChildrenIfNeeded()
                return sidebarItem.childCount
            }
            return rootItems.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let sidebarItem = item as? SidebarItem {
                return sidebarItem.children![index]
            }
            return rootItems[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let sidebarItem = item as? SidebarItem else { return false }
            return sidebarItem.isExpandable
        }

        // MARK: Delegate — Row View

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let sidebarItem = item as? SidebarItem else { return nil }

            let cellID = NSUserInterfaceItemIdentifier("SidebarCell")
            let cellView: NSTableCellView

            if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
                cellView = reused
            } else {
                cellView = makeCellView(identifier: cellID)
            }

            configureCellView(cellView, for: sidebarItem)
            return cellView
        }

        private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cellView = NSTableCellView()
            cellView.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(imageView)
            cellView.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.cell?.truncatesLastVisibleLine = true
            cellView.addSubview(textField)
            cellView.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])

            return cellView
        }

        private func configureCellView(_ cellView: NSTableCellView, for item: SidebarItem) {
            cellView.textField?.stringValue = item.name

            let symbolName: String
            let tintColor: NSColor
            if item.isZip {
                symbolName = "doc.zipper"
                tintColor = .systemOrange
            } else if item.isPdf {
                symbolName = "doc.richtext"
                tintColor = .systemRed
            } else {
                symbolName = "folder"
                tintColor = .systemBlue
            }

            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            cellView.imageView?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            cellView.imageView?.contentTintColor = tintColor
        }

        // MARK: Delegate — Selection

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection else { return }
            guard let outlineView = outlineView else { return }

            let row = outlineView.selectedRow
            guard row >= 0,
                  let item = outlineView.item(atRow: row) as? SidebarItem else { return }

            SourceSwitchTiming.start("click")
            SourceSwitchTiming.mark("callback")
            parent.onSourceSelect(item.url, item.sourceType)
        }

        // MARK: Double Click

        @objc func handleDoubleClick(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0,
                  let item = sender.item(atRow: row) as? SidebarItem else { return }

            // Double-click on disclosure triangle (clickedRow valid but expanding)
            // is handled by NSOutlineView itself — we only fire slide mode
            parent.onOpenSlideMode?(item.url)
        }

        // MARK: Selection Sync (external → outline)

        func syncSelection(to url: URL?) {
            guard let outlineView = outlineView else { return }

            guard let url = url else {
                isSyncingSelection = true
                outlineView.deselectAll(nil)
                isSyncingSelection = false
                return
            }

            // Search visible rows for matching URL
            for row in 0..<outlineView.numberOfRows {
                if let item = outlineView.item(atRow: row) as? SidebarItem, item.url == url {
                    guard outlineView.selectedRow != row else { return }
                    isSyncingSelection = true
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                    isSyncingSelection = false
                    return
                }
            }
            // URL not in visible rows — may be inside a collapsed parent.
            // Future: expand parent chain to reveal the item.
        }

        // MARK: Expansion State Preservation (S023 pattern)

        func saveExpandedState() -> Set<URL> {
            guard let outlineView = outlineView else { return [] }
            var expanded = Set<URL>()
            for row in 0..<outlineView.numberOfRows {
                if let item = outlineView.item(atRow: row) as? SidebarItem,
                   outlineView.isItemExpanded(item) {
                    expanded.insert(item.url)
                }
            }
            return expanded
        }

        func restoreExpandedState(_ urls: Set<URL>) {
            guard let outlineView = outlineView, !urls.isEmpty else { return }
            restoreExpansion(items: rootItems, urls: urls, outlineView: outlineView)
        }

        private func restoreExpansion(items: [SidebarItem], urls: Set<URL>, outlineView: NSOutlineView) {
            for item in items {
                if urls.contains(item.url) {
                    item.loadChildrenIfNeeded()
                    outlineView.expandItem(item)
                    // Recurse into children to restore nested expansion
                    if let children = item.children {
                        restoreExpansion(items: children, urls: urls, outlineView: outlineView)
                    }
                }
            }
        }
    }
}
