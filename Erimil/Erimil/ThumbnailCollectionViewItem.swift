//
//  ThumbnailCollectionViewItem.swift
//  Erimil
//
//  S096: #215 Phase 2 — Pure AppKit collection view cell.
//  Step 2: Full overlays (selection, ★, bookmark, animated badge, focus border).
//

import Cocoa

/// All state needed to render a cell
struct ThumbnailCellState {
    let thumbnail: NSImage?
    let isSelected: Bool
    let isFocused: Bool
    let favoriteStatus: CacheManager.FavoriteStatus
    let selectionMode: SelectionMode
    let isLastViewed: Bool
    let isAnimatedFormat: Bool
    let showProtectedFeedback: Bool
}

class ThumbnailCollectionViewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailCollectionViewItem")
    
    private let imageLayer = NSImageView()
    private let progressIndicator = NSProgressIndicator()
    
    // Overlays
    private let selectionOverlay = NSView()
    private let selectionIcon = NSImageView()
    private let starBadge = NSImageView()
    private let bookmarkBadge = NSImageView()
    private let animatedBadge = NSTextField()
    private let borderView = NSView()
    
    private var currentSize: CGFloat = 150
    
    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.masksToBounds = true
        
        // Thumbnail image
        imageLayer.imageScaling = .scaleProportionallyUpOrDown
        imageLayer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageLayer)
        
        // Loading spinner
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.isDisplayedWhenStopped = false
        container.addSubview(progressIndicator)
        
        // Selection overlay (semi-transparent black)
        selectionOverlay.wantsLayer = true
        selectionOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        selectionOverlay.isHidden = true
        container.addSubview(selectionOverlay)
        
        // Selection icon (center)
        selectionIcon.imageScaling = .scaleProportionallyUpOrDown
        selectionIcon.translatesAutoresizingMaskIntoConstraints = false
        selectionIcon.isHidden = true
        container.addSubview(selectionIcon)
        
        // Star badge (top-left)
        starBadge.imageScaling = .scaleProportionallyUpOrDown
        starBadge.translatesAutoresizingMaskIntoConstraints = false
        starBadge.isHidden = true
        let starConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        starBadge.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorite")?
            .withSymbolConfiguration(starConfig)
        starBadge.contentTintColor = .systemYellow
        container.addSubview(starBadge)
        
        // Bookmark badge (top-right)
        bookmarkBadge.imageScaling = .scaleProportionallyUpOrDown
        bookmarkBadge.translatesAutoresizingMaskIntoConstraints = false
        bookmarkBadge.isHidden = true
        let bmConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        bookmarkBadge.image = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: "Last viewed")?
            .withSymbolConfiguration(bmConfig)
        bookmarkBadge.contentTintColor = .systemOrange
        container.addSubview(bookmarkBadge)
        
        // Animated format badge (bottom-left)
        animatedBadge.stringValue = "▶"
        animatedBadge.isEditable = false
        animatedBadge.isBordered = false
        animatedBadge.drawsBackground = true
        animatedBadge.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        animatedBadge.textColor = .white
        animatedBadge.font = .systemFont(ofSize: 9, weight: .bold)
        animatedBadge.alignment = .center
        animatedBadge.translatesAutoresizingMaskIntoConstraints = false
        animatedBadge.wantsLayer = true
        animatedBadge.layer?.cornerRadius = 3
        animatedBadge.isHidden = true
        container.addSubview(animatedBadge)
        
        // Border view (focus/selection ring — on top of everything)
        borderView.wantsLayer = true
        borderView.layer?.borderWidth = 3
        borderView.layer?.cornerRadius = 4
        borderView.layer?.borderColor = NSColor.clear.cgColor
        borderView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(borderView)
        
        NSLayoutConstraint.activate([
            imageLayer.topAnchor.constraint(equalTo: container.topAnchor),
            imageLayer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageLayer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageLayer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            progressIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            selectionOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            selectionOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            selectionIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            selectionIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            selectionIcon.widthAnchor.constraint(equalToConstant: 48),
            selectionIcon.heightAnchor.constraint(equalToConstant: 48),
            
            starBadge.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            starBadge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            starBadge.widthAnchor.constraint(equalToConstant: 16),
            starBadge.heightAnchor.constraint(equalToConstant: 16),
            
            bookmarkBadge.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bookmarkBadge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            bookmarkBadge.widthAnchor.constraint(equalToConstant: 16),
            bookmarkBadge.heightAnchor.constraint(equalToConstant: 16),
            
            animatedBadge.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            animatedBadge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            animatedBadge.widthAnchor.constraint(equalToConstant: 20),
            animatedBadge.heightAnchor.constraint(equalToConstant: 16),
            
            borderView.topAnchor.constraint(equalTo: container.topAnchor),
            borderView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        
        self.view = container
    }
    
    func configure(thumbnail: NSImage?) {
        // Lightweight update — thumbnail only (used by applyThumbnailBatch)
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
    
    func configure(state: ThumbnailCellState) {
        // Full state update
        configure(thumbnail: state.thumbnail)
        
        // Selection overlay
        selectionOverlay.isHidden = !state.isSelected
        selectionIcon.isHidden = !state.isSelected
        if state.isSelected {
            let iconName = state.selectionMode == .exclude ? "xmark.circle.fill" : "checkmark.circle.fill"
            let tintColor: NSColor = state.selectionMode == .exclude ? .systemRed : .systemGreen
            let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
            selectionIcon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            selectionIcon.contentTintColor = tintColor
        }
        
        // Star badge
        starBadge.isHidden = (state.favoriteStatus != .direct)
        
        // Bookmark badge
        bookmarkBadge.isHidden = !state.isLastViewed
        
        // Animated badge
        animatedBadge.isHidden = !state.isAnimatedFormat
        
        // Border
        if state.isFocused {
            borderView.layer?.borderColor = NSColor.controlAccentColor.cgColor
            borderView.layer?.borderWidth = 3
        } else if state.isSelected {
            let color: NSColor = state.selectionMode == .exclude ? .systemRed : .systemGreen
            borderView.layer?.borderColor = color.cgColor
            borderView.layer?.borderWidth = 3
        } else {
            borderView.layer?.borderColor = NSColor.clear.cgColor
            borderView.layer?.borderWidth = 0
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageLayer.image = nil
        imageLayer.isHidden = true
        progressIndicator.stopAnimation(nil)
        selectionOverlay.isHidden = true
        selectionIcon.isHidden = true
        starBadge.isHidden = true
        bookmarkBadge.isHidden = true
        animatedBadge.isHidden = true
        borderView.layer?.borderColor = NSColor.clear.cgColor
        borderView.layer?.borderWidth = 0
    }
}
