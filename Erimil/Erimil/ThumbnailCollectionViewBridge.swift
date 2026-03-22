//
//  ThumbnailCollectionViewBridge.swift
//  Erimil
//
//  S096: #215 Phase 2 — NSViewRepresentable bridge for NSCollectionView.
//  Step 1.5: Direct thumbnail push via ThumbnailCollectionUpdater.
//  Step 3: Scroll-to-focused-item support.
//  Step 4: Bookmark section headers via Coordinator-side calculation.
//

import SwiftUI
import AppKit

/// Direct thumbnail push — bypasses SwiftUI state update cycle
class ThumbnailCollectionUpdater {
    weak var coordinator: ThumbnailCollectionViewBridge.Coordinator?
    
    func applyBatch(_ batch: [(path: String, image: NSImage)]) {
        coordinator?.applyThumbnailBatch(batch)
    }
    
    func refreshVisibleCells() {
        coordinator?.refreshVisibleCells()
    }
    
    func scrollToItem(at index: Int, animated: Bool = true) {
        coordinator?.scrollToItem(at: index, animated: animated)
    }
    
    func reloadSections() {
        coordinator?.rebuildSectionsAndReload()
    }
    
    func currentColumnCount() -> Int {
        coordinator?.currentColumnCount() ?? 4
    }
}

struct ThumbnailCollectionViewBridge: NSViewRepresentable {
    let entries: [ImageEntry]
    let thumbnails: [String: NSImage]
    let itemSize: CGFloat
    let spacing: CGFloat
    let isRTL: Bool
    let sourceURL: URL
    var onCellAppear: ((ImageEntry) -> Void)?
    var onCellTap: ((Int) -> Void)?
    var cellStateProvider: ((Int, ImageEntry) -> ThumbnailCellState)?
    let updater: ThumbnailCollectionUpdater
    
    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: itemSize, height: itemSize)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.userInterfaceLayoutDirection = isRTL ? .rightToLeft : .leftToRight
        collectionView.register(
            ThumbnailCollectionViewItem.self,
            forItemWithIdentifier: ThumbnailCollectionViewItem.identifier
        )
        collectionView.register(
            ThumbnailSectionHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: ThumbnailSectionHeaderView.identifier
        )
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        
        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        context.coordinator.collectionView = collectionView
        context.coordinator.sourceURL = sourceURL
        updater.coordinator = context.coordinator
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let entriesChanged = coordinator.entries.map(\.path) != entries.map(\.path)
        
        let newDirection: NSUserInterfaceLayoutDirection = isRTL ? .rightToLeft : .leftToRight
        if coordinator.collectionView?.userInterfaceLayoutDirection != newDirection {
            coordinator.collectionView?.userInterfaceLayoutDirection = newDirection
            coordinator.collectionView?.reloadData()
        }
        
        coordinator.onCellAppear = onCellAppear
        coordinator.onCellTap = onCellTap
        coordinator.cellStateProvider = cellStateProvider
        coordinator.sourceURL = sourceURL
        updater.coordinator = coordinator
        
        // Update layout if size changed
        if let layout = coordinator.collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout {
            let newSize = NSSize(width: itemSize, height: itemSize)
            if layout.itemSize != newSize
                || layout.minimumInteritemSpacing != spacing
                || layout.minimumLineSpacing != spacing {
                layout.itemSize = newSize
                layout.minimumInteritemSpacing = spacing
                layout.minimumLineSpacing = spacing
            }
            coordinator.updateLayoutForWidth()
        }
        
        if entriesChanged {
            coordinator.entries = entries
            coordinator.thumbnails = thumbnails
            coordinator.resetAppearanceTracking()
            coordinator.rebuildSections()
            coordinator.updateLayoutForWidth()
            coordinator.collectionView?.reloadData()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        var entries: [ImageEntry] = []
        var thumbnails: [String: NSImage] = [:]
        var onCellAppear: ((ImageEntry) -> Void)?
        var onCellTap: ((Int) -> Void)?
        var cellStateProvider: ((Int, ImageEntry) -> ThumbnailCellState)?
        weak var collectionView: NSCollectionView?
        var sourceURL: URL?
        
        // MARK: - Section Management
        
        struct SectionInfo {
            let bookmarkName: String?   // nil = no header (pre-bookmark section)
            let range: Range<Int>       // global entry indices
        }
        
        private(set) var sections: [SectionInfo] = []
        private var appearedPaths: Set<String> = []
        
        func rebuildSections() {
            guard !entries.isEmpty else {
                sections = []
                return
            }
            
            guard let sourceURL = sourceURL else {
                sections = [SectionInfo(bookmarkName: nil, range: 0..<entries.count)]
                return
            }
            
            let bookmarks = CacheManager.shared.getBookmarks(for: sourceURL)
            let sorted = bookmarks
                .filter { $0.imageIndex >= 0 && $0.imageIndex < entries.count }
                .sorted { $0.imageIndex < $1.imageIndex }
            
            if sorted.isEmpty {
                sections = [SectionInfo(bookmarkName: nil, range: 0..<entries.count)]
                return
            }
            
            var result: [SectionInfo] = []
            
            // Pre-bookmark section (no header)
            if let first = sorted.first, first.imageIndex > 0 {
                result.append(SectionInfo(bookmarkName: nil, range: 0..<first.imageIndex))
            }
            
            // Each bookmark starts a section
            for (i, bm) in sorted.enumerated() {
                let start = bm.imageIndex
                let end = (i + 1 < sorted.count) ? sorted[i + 1].imageIndex : entries.count
                if start < end {
                    result.append(SectionInfo(bookmarkName: bm.name, range: start..<end))
                }
            }
            
            sections = result
        }
        
        func rebuildSectionsAndReload() {
            rebuildSections()
            updateLayoutForWidth()
            collectionView?.reloadData()
        }
        
        // MARK: - Index Mapping
        
        private func globalIndex(for indexPath: IndexPath) -> Int {
            guard indexPath.section < sections.count else { return indexPath.item }
            return sections[indexPath.section].range.lowerBound + indexPath.item
        }
        
        private func indexPath(forGlobalIndex index: Int) -> IndexPath? {
            for (s, section) in sections.enumerated() {
                if section.range.contains(index) {
                    return IndexPath(item: index - section.range.lowerBound, section: s)
                }
            }
            return nil
        }
        
        // MARK: - Data Source
        
        func numberOfSections(in collectionView: NSCollectionView) -> Int {
            sections.count
        }
        
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            guard section < sections.count else { return 0 }
            return sections[section].range.count
        }
        
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: ThumbnailCollectionViewItem.identifier,
                for: indexPath
            ) as! ThumbnailCollectionViewItem
            
            let gIdx = globalIndex(for: indexPath)
            let entry = entries[gIdx]
            
            if let stateProvider = cellStateProvider {
                item.configure(state: stateProvider(gIdx, entry))
            } else {
                item.configure(thumbnail: thumbnails[entry.path])
            }
            
            if !appearedPaths.contains(entry.path) {
                appearedPaths.insert(entry.path)
                onCellAppear?(entry)
            }
            return item
        }
        
        func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
            guard kind == NSCollectionView.elementKindSectionHeader else {
                return NSView()
            }
            let header = collectionView.makeSupplementaryView(
                ofKind: kind,
                withIdentifier: ThumbnailSectionHeaderView.identifier,
                for: indexPath
            ) as! ThumbnailSectionHeaderView
            
            if indexPath.section < sections.count,
               let name = sections[indexPath.section].bookmarkName {
                header.configure(title: "📖 \(name)")
            } else {
                header.configure(title: "")
            }
            return header
        }
        
        // MARK: - Flow Layout Delegate
        
        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> NSSize {
            guard section < sections.count,
                  sections[section].bookmarkName != nil else {
                return .zero
            }
            return NSSize(width: collectionView.bounds.width, height: 28)
        }
        
        // MARK: - Selection
        
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let indexPath = indexPaths.first else { return }
            collectionView.deselectItems(at: indexPaths)
            onCellTap?(globalIndex(for: indexPath))
        }
        
        func resetAppearanceTracking() {
            appearedPaths.removeAll()
        }
        
        // MARK: - Direct Updates (bypass SwiftUI)
        
        func applyThumbnailBatch(_ batch: [(path: String, image: NSImage)]) {
            guard let collectionView = collectionView else { return }
            
            for item in batch {
                thumbnails[item.path] = item.image
                if let gIdx = entries.firstIndex(where: { $0.path == item.path }),
                   let ip = indexPath(forGlobalIndex: gIdx),
                   let cell = collectionView.item(at: ip) as? ThumbnailCollectionViewItem {
                    cell.configure(thumbnail: item.image)
                }
            }
        }
        
        func refreshVisibleCells() {
            guard let collectionView = collectionView,
                  let stateProvider = cellStateProvider else { return }
            for ip in collectionView.indexPathsForVisibleItems() {
                let gIdx = globalIndex(for: ip)
                guard gIdx < entries.count else { continue }
                if let cell = collectionView.item(at: ip) as? ThumbnailCollectionViewItem {
                    cell.configure(state: stateProvider(gIdx, entries[gIdx]))
                }
            }
        }
        
        func scrollToItem(at index: Int, animated: Bool) {
            guard let collectionView = collectionView,
                  index >= 0, index < entries.count,
                  let ip = indexPath(forGlobalIndex: index),
                  let attrs = collectionView.layoutAttributesForItem(at: ip) else { return }
            
            if animated {
                collectionView.animator().scrollToVisible(attrs.frame)
            } else {
                collectionView.scrollToVisible(attrs.frame)
            }
        }
        
        func currentColumnCount() -> Int {
            guard let cv = collectionView,
                  let layout = cv.collectionViewLayout as? NSCollectionViewFlowLayout else { return 4 }
            let available = cv.visibleRect.width - layout.sectionInset.left - layout.sectionInset.right
            let itemWidth = layout.itemSize.width + layout.minimumInteritemSpacing
            return max(1, Int(available / itemWidth))
        }
        
        func updateLayoutForWidth() {
            guard let cv = collectionView,
                  let layout = cv.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
            let itemW = layout.itemSize.width
            let interitem = layout.minimumInteritemSpacing
            let totalWidth = cv.visibleRect.width
            guard totalWidth > 0 else { return }
            
            // LazyVGrid .adaptive replication: pack as many as fit, absorb remainder into margins
            let columns = max(1, Int((totalWidth + interitem) / (itemW + interitem)))
            let usedWidth = CGFloat(columns) * itemW + CGFloat(columns - 1) * interitem
            let margin = max(0, (totalWidth - usedWidth) / 2)
            
            let newInset = NSEdgeInsets(top: 8, left: margin, bottom: 8, right: margin)
            if layout.sectionInset.left != newInset.left {
                layout.sectionInset = newInset
            }
        }
    }
}
