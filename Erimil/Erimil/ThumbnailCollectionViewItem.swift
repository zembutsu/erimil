//
//  ThumbnailCollectionViewItem.swift
//  Erimil
//
//  S096: #215 Phase 2 — Pure AppKit collection view cell.
//  Step 1: Thumbnail display only. Overlays (selection, ★, bookmark) in later steps.
//

import Cocoa

class ThumbnailCollectionViewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailCollectionViewItem")
    
    private let imageLayer = NSImageView()
    private let progressIndicator = NSProgressIndicator()
    
    override func loadView() {
        let container = NSView()
        
        // Thumbnail image
        imageLayer.imageScaling = .scaleProportionallyUpOrDown
        imageLayer.translatesAutoresizingMaskIntoConstraints = false
        imageLayer.wantsLayer = true
        imageLayer.layer?.cornerRadius = 4
        imageLayer.layer?.masksToBounds = true
        container.addSubview(imageLayer)
        
        // Loading spinner
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.isDisplayedWhenStopped = false
        container.addSubview(progressIndicator)
        
        NSLayoutConstraint.activate([
            imageLayer.topAnchor.constraint(equalTo: container.topAnchor),
            imageLayer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageLayer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageLayer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            progressIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        
        self.view = container
    }
    
    func configure(thumbnail: NSImage?) {
        if let image = thumbnail {
            imageLayer.image = image
            imageLayer.isHidden = false
            progressIndicator.stopAnimation(nil)
        } else {
            imageLayer.image = nil
            imageLayer.isHidden = true
            progressIndicator.startAnimation(nil)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageLayer.image = nil
        imageLayer.isHidden = true
        progressIndicator.stopAnimation(nil)
    }
}
