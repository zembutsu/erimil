//
//  ThumbnailCollectionViewBridge.swift
//  Erimil
//
//  S096: #215 Phase 2 — NSViewRepresentable bridge for NSCollectionView.
//  Step 1.5: Direct thumbnail push via ThumbnailCollectionUpdater.
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
}

struct ThumbnailCollectionViewBridge: NSViewRepresentable {
    let entries: [ImageEntry]
    let thumbnails: [String: NSImage]
    let itemSize: CGFloat
    let spacing: CGFloat
    let isRTL: Bool
    var onCellAppear: ((ImageEntry) -> Void)?
    var onCellTap: ((Int) -> Void)?
    var cellStateProvider: ((Int, ImageEntry) -> ThumbnailCellState)?
    let updater: ThumbnailCollectionUpdater
    
    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: itemSize, height: itemSize)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = NSEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)
        
        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        if isRTL {
            collectionView.userInterfaceLayoutDirection = .rightToLeft
        } else {
            collectionView.userInterfaceLayoutDirection = .leftToRight
        }
        collectionView.register(
            ThumbnailCollectionViewItem.self,
            forItemWithIdentifier: ThumbnailCollectionViewItem.identifier
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
        updater.coordinator = coordinator
        
        // Update layout if size changed
        if let layout = coordinator.collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout {
            let newSize = NSSize(width: itemSize, height: itemSize)
            if layout.itemSize != newSize {
                layout.itemSize = newSize
                layout.minimumInteritemSpacing = spacing
                layout.minimumLineSpacing = spacing
            }
        }
        
        if entriesChanged {
            // Source switch — full reload
            coordinator.entries = entries
            coordinator.thumbnails = thumbnails
            coordinator.resetAppearanceTracking()
            coordinator.collectionView?.reloadData()
        }
        // Thumbnail-only changes are handled via applyThumbnailBatch — no reloadData()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        var entries: [ImageEntry] = []
        var thumbnails: [String: NSImage] = [:]
        var onCellAppear: ((ImageEntry) -> Void)?
        var onCellTap: ((Int) -> Void)?
        var cellStateProvider: ((Int, ImageEntry) -> ThumbnailCellState)?
        weak var collectionView: NSCollectionView?
        
        private var appearedPaths: Set<String> = []
        
        func numberOfSections(in collectionView: NSCollectionView) -> Int {
            1
        }
        
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            entries.count
        }
        
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: ThumbnailCollectionViewItem.identifier,
                for: indexPath
            ) as! ThumbnailCollectionViewItem
           
            let entry = entries[indexPath.item]
           
            if let stateProvider = cellStateProvider {
               item.configure(state: stateProvider(indexPath.item, entry))
            } else {
               item.configure(thumbnail: thumbnails[entry.path])
            }
           
            if !appearedPaths.contains(entry.path) {
                appearedPaths.insert(entry.path)
                onCellAppear?(entry)
            }
            return item
        }
        
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let indexPath = indexPaths.first else { return }
            collectionView.deselectItems(at: indexPaths)  // Erimilは独自のフォーカス管理
            onCellTap?(indexPath.item)
        }
        
        func resetAppearanceTracking() {
            appearedPaths.removeAll()
        }
        
        /// Direct thumbnail update — bypasses SwiftUI body re-evaluation
        func applyThumbnailBatch(_ batch: [(path: String, image: NSImage)]) {
            guard let collectionView = collectionView else { return }
            
            var indexPathsToReload: [IndexPath] = []
            for item in batch {
                thumbnails[item.path] = item.image
                if let idx = entries.firstIndex(where: { $0.path == item.path }) {
                    indexPathsToReload.append(IndexPath(item: idx, section: 0))
                }
            }
            
            if !indexPathsToReload.isEmpty {
                // Directly configure visible cells without full reload
                for indexPath in indexPathsToReload {
                    if let cell = collectionView.item(at: indexPath) as? ThumbnailCollectionViewItem {
                        let entry = entries[indexPath.item]
                        cell.configure(thumbnail: thumbnails[entry.path])
                    }
                }
            }
        }
        
        func refreshVisibleCells() {
            guard let collectionView = collectionView,
                  let stateProvider = cellStateProvider else { return }
            for indexPath in collectionView.indexPathsForVisibleItems() {
                guard indexPath.item < entries.count else { continue }
                if let cell = collectionView.item(at: indexPath) as? ThumbnailCollectionViewItem {
                    let entry = entries[indexPath.item]
                    cell.configure(state: stateProvider(indexPath.item, entry))
                }
            }
        }
        
        func scrollToItem(at index: Int, animated: Bool) {
            guard let collectionView = collectionView,
                  index >= 0, index < entries.count else { return }
            let indexPath = IndexPath(item: index, section: 0)
            
            guard let attrs = collectionView.layoutAttributesForItem(at: indexPath) else { return }
            
            if animated {
                collectionView.animator().scrollToVisible(attrs.frame)
            } else {
                collectionView.scrollToVisible(attrs.frame)
            }
        }
    }
}
