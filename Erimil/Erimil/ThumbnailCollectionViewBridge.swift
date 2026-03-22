//
//  ThumbnailCollectionViewBridge.swift
//  Erimil
//
//  S096: #215 Phase 2 — NSViewRepresentable bridge for NSCollectionView.
//  Wraps NSCollectionView for use in SwiftUI view hierarchy.
//

import SwiftUI
import AppKit

struct ThumbnailCollectionViewBridge: NSViewRepresentable {
    let entries: [ImageEntry]
    let thumbnails: [String: NSImage]
    let itemSize: CGFloat
    let spacing: CGFloat
    var onCellAppear: ((ImageEntry) -> Void)?
    
    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: itemSize, height: itemSize)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = NSEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)
        
        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.register(
            ThumbnailCollectionViewItem.self,
            forItemWithIdentifier: ThumbnailCollectionViewItem.identifier
        )
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = false  // Step 1: selection handled later
        collectionView.backgroundColors = [.clear]
        
        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        context.coordinator.collectionView = collectionView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.entries = entries
        coordinator.thumbnails = thumbnails
        coordinator.onCellAppear = onCellAppear
        
        // Update layout if size changed
        if let layout = coordinator.collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout {
            let newSize = NSSize(width: itemSize, height: itemSize)
            if layout.itemSize != newSize {
                layout.itemSize = newSize
                layout.minimumInteritemSpacing = spacing
                layout.minimumLineSpacing = spacing
            }
        }
        
        // Reload visible items with current thumbnails
        coordinator.collectionView?.reloadData()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        var entries: [ImageEntry] = []
        var thumbnails: [String: NSImage] = [:]
        var onCellAppear: ((ImageEntry) -> Void)?
        weak var collectionView: NSCollectionView?
        
        // Track which entries have triggered onCellAppear
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
            item.configure(thumbnail: thumbnails[entry.path])
            
            // Trigger thumbnail load on first appearance
            if !appearedPaths.contains(entry.path) {
                appearedPaths.insert(entry.path)
                onCellAppear?(entry)
            }
            
            return item
        }
        
        /// Reset appearance tracking on source switch
        func resetAppearanceTracking() {
            appearedPaths.removeAll()
        }
    }
}
