//
//  ThumbnailComponents.swift
//  Erimil
//
//  Extracted from ThumbnailGridView.swift (#175 Phase 1)
//  Contains: GridSection, BookmarkDividerView, ThumbnailCell,
//            ThumbnailDisplayItem, ThumbnailItemView, SpreadThumbnailPairView
//

import SwiftUI
import AppKit
import os

// MARK: - Grid Section for Bookmarks (#62)

/// A section of the grid, divided by bookmarks
struct GridSection: Identifiable {
    let id: String  // Stable ID for SwiftUI
    let bookmark: Bookmark?  // nil = first section (before any bookmark)
    let items: [GridEntry]
    
    struct GridEntry: Identifiable {
        let index: Int
        let entry: ImageEntry
        var id: UUID { entry.id }
    }
}

/// Horizontal divider with bookmark name (#62)
/// Click section name to edit inline (Phase 4)
struct BookmarkDividerView: View {
    let bookmark: Bookmark
    let sourceURL: URL
    let isRTL: Bool
    var onNameChanged: (() -> Void)?
    
    @State private var isEditing: Bool = false
    @State private var editingName: String = ""
    @FocusState private var textFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            if isRTL {
                line
                label
            } else {
                label
                line
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }
    
    @ViewBuilder
    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            
            if isEditing {
                TextField("Section name", text: $editingName)
                .font(.caption)
                .fontWeight(.medium)
                .textFieldStyle(.plain)
                .frame(maxWidth: 200)
                .focused($textFieldFocused)
                .onSubmit {
                    commitEdit()
                }
                .onExitCommand {
                    cancelEdit()
                }
                .onAppear {
                    textFieldFocused = true
                }
            } else {
                Text(bookmark.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .onTapGesture {
                        startEdit()
                    }
                    .help("Click to edit section name")
            }
        }
    }
    
    private var line: some View {
        Rectangle()
            .fill(Color.orange.opacity(0.4))
            .frame(height: 1)
    }
    
    private func startEdit() {
        editingName = bookmark.name
        isEditing = true
    }
    
    private func commitEdit() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != bookmark.name {
            CacheManager.shared.updateBookmarkName(for: sourceURL, id: bookmark.id, name: trimmed)
            Logger.bookmark.debug("Renamed '\(bookmark.name)' → '\(trimmed)'")
            onNameChanged?()
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
    }
}

// MARK: - ThumbnailCell

struct ThumbnailCell: View {
    let entry: ImageEntry
    let thumbnail: NSImage?
    let isSelected: Bool
    let isFocused: Bool
    let favoriteStatus: CacheManager.FavoriteStatus
    let selectionMode: SelectionMode
    let size: CGFloat
    let showProtectedFeedback: Bool  // Temporary feedback when trying to select protected item
    let isLastViewed: Bool  // #52: Show bookmark icon for last viewed position
    
    private var overlayColor: Color {
        switch selectionMode {
        case .exclude:
            return .red
        case .keep:
            return .green
        }
    }
    
    private var overlayIcon: String {
        switch selectionMode {
        case .exclude:
            return "xmark.circle.fill"
        case .keep:
            return "checkmark.circle.fill"
        }
    }
    
    private var iconSize: Font {
        if size < 100 {
            return .title2
        } else if size < 150 {
            return .largeTitle
        } else {
            return .system(size: 48)
        }
    }
    
    /// Border color based on state
    private var borderColor: Color {
        if isFocused {
            return .accentColor  // Blue focus ring
        } else if isSelected {
            return overlayColor
        } else {
            return .clear
        }
    }
    
    /// Border width based on state
    private var borderWidth: CGFloat {
        if isFocused {
            return 3
        } else if isSelected {
            return 3
        } else {
            return 0
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Thumbnail image
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                } else {
                    ProgressView()
                        .frame(width: size, height: size)
                }
                
                // Selection overlay
                if isSelected {
                    Color.black.opacity(0.4)
                    Image(systemName: overlayIcon)
                        .font(iconSize)
                        .foregroundStyle(.white, overlayColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Favorite star overlay (top-left) and bookmark (top-right)
                // ★ (yellow) = direct favorite in this source
                // 🔖 (bookmark) = last viewed position (#52)
                VStack {
                    HStack {
                        // Left: Favorite star
                        switch favoriteStatus {
                        case .direct:
                            Image(systemName: "star.fill")
                                .font(size < 100 ? .caption : .body)
                                .foregroundStyle(.yellow)
                                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        case .inherited, .none:
                            EmptyView()
                        }
                        
                        Spacer()
                        
                        // Right: Bookmark for last viewed position (#52)
                        if isLastViewed {
                            Image(systemName: "bookmark.fill")
                                .font(size < 100 ? .caption : .body)
                                .foregroundStyle(.orange)
                                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        }
                    }
                    .padding(4)
                    
                    Spacer()
                    
                    HStack {
                        // #201: Animated image badge (bottom-left)
                        if entry.isAnimatedFormat {
                            Text("▶")
                                .font(.system(size: size < 100 ? 8 : 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(3)
                                .padding(4)
                        }
                        
                        Spacer()
                        
                        // PROTECTED label - shown temporarily when trying to select protected item
                        if showProtectedFeedback {
                            Text("PROTECTED")
                                .font(.system(size: size < 100 ? 8 : 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.9))
                                .cornerRadius(3)
                                .padding(.bottom, 4)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .background(isFocused ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            
            Text(entry.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size)
                .foregroundStyle(isFocused ? .primary : .secondary)
        }
    }
}

// MARK: - Thumbnail Display Item (#69)

enum ThumbnailDisplayItem: Identifiable {
    case single(Int)
    case spread(leftIndex: Int, rightIndex: Int)
    
    var id: String {
        switch self {
        case .single(let index):
            return "single-\(index)"
        case .spread(let left, let right):
            return "spread-\(left)-\(right)"
        }
    }
}

struct ThumbnailItemView: View {
    let imageSource: any ImageSource
    let entry: ImageEntry
    let index: Int
    let isCurrent: Bool
    let favoriteStatus: CacheManager.FavoriteStatus
    let isSelected: Bool
    let selectionMode: SelectionMode
    let size: CGFloat
    var onTap: () -> Void
    var onAspectRatioCached: (() -> Void)? = nil
    
    @State private var thumbnail: NSImage? = nil
    
    private var overlayColor: Color {
        switch selectionMode {
        case .exclude:
            return .red
        case .keep:
            return .green
        }
    }
    
    private var overlayIcon: String {
        switch selectionMode {
        case .exclude:
            return "xmark.circle.fill"
        case .keep:
            return "checkmark.circle.fill"
        }
    }
    
    var body: some View {
        ZStack {
            // Thumbnail image
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(.white)
                    }
            }
            
            // Selection overlay (center icon)
            if isSelected {
                Color.black.opacity(0.4)
                Image(systemName: overlayIcon)
                    .font(.title2)
                    .foregroundStyle(.white, overlayColor)
            }
            
            // Favorite star (top-left) - only show direct favorites
            VStack {
                HStack {
                    if favoriteStatus == .direct {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                    }
                    Spacer()
                }
                .padding(3)
                Spacer()
                
                // #201: Animated image badge (bottom-left)
                if entry.isAnimatedFormat {
                    HStack {
                        Text("▶")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(2)
                            .padding(3)
                        Spacer()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isCurrent ? Color.blue : (isSelected ? overlayColor : Color.clear), lineWidth: 3)
        )
        .onTapGesture { onTap() }
        .onAppear { loadThumbnail() }
    }
    
    private func loadThumbnail() {
        DispatchQueue.global(qos: .utility).async {
            let maxSize = max(AppSettings.shared.effectiveRetinaThumbnailSize, 180)
            let image = imageSource.thumbnail(for: entry, maxSize: maxSize)
            if let image = image {
                // #144: Cache aspect ratio for spread detection
                CacheManager.shared.setAspectRatio(
                    for: imageSource.url, path: entry.path,
                    ratio: image.size.width / image.size.height
                )
            }
            DispatchQueue.main.async {
                thumbnail = image
                onAspectRatioCached?()
            }
        }
    }
}

// MARK: - Spread Thumbnail Pair View (#69)

struct SpreadThumbnailPairView: View {
    let imageSource: any ImageSource
    let leftEntry: ImageEntry
    let rightEntry: ImageEntry
    let leftIndex: Int
    let rightIndex: Int
    let currentIndex: Int
    let contentHashes: [String: String]
    let selectedPaths: Set<String>
    let favoritesVersion: Int
    let selectionMode: SelectionMode
    let pairSize: CGFloat  // Total width/height for the pair
    var onSelect: (Int) -> Void
    
    @State private var leftThumbnail: NSImage? = nil
    @State private var rightThumbnail: NSImage? = nil
    
    /// Is this pair currently focused (contains currentIndex)?
    private var isCurrent: Bool {
        currentIndex == leftIndex || currentIndex == rightIndex
    }
    
    /// Size for each thumbnail (half of pair size minus divider)
    private var itemSize: CGFloat {
        floor((pairSize - 1) / 2)  // floor() ensures equal width for left/right
    }
    
    private var leftFavoriteStatus: CacheManager.FavoriteStatus {
        let hash = contentHashes[leftEntry.path]
        return CacheManager.shared.getFavoriteStatus(
            sourceURL: imageSource.url,
            entryPath: leftEntry.path,
            contentHash: hash
        )
    }
    
    private var rightFavoriteStatus: CacheManager.FavoriteStatus {
        let hash = contentHashes[rightEntry.path]
        return CacheManager.shared.getFavoriteStatus(
            sourceURL: imageSource.url,
            entryPath: rightEntry.path,
            contentHash: hash
        )
    }
    
    private var isLeftSelected: Bool {
        selectedPaths.contains(leftEntry.path)
    }
    
    private var isRightSelected: Bool {
        selectedPaths.contains(rightEntry.path)
    }
    
    private var overlayColor: Color {
        switch selectionMode {
        case .exclude: return .red
        case .keep: return .green
        }
    }
    
    var body: some View {
        // HStack with two thumbnails - #116: RTL resolved internally via source reading direction
        let direction = CacheManager.shared.getEffectiveReadingDirection(for: imageSource.url)
        HStack(spacing: 1) {
            // Left side (in LTR: lower index page; in RTL: higher index page)
            thumbnailView(
                entry: leftEntry,
                index: leftIndex,
                thumbnail: leftThumbnail,
                favoriteStatus: leftFavoriteStatus,
                isSelected: isLeftSelected
            )
            
            // #187: 1px center divider between spread pair
            // Rectangle()
            //   .fill(Color.primary.opacity(0.3))
            //   .frame(width: 2)
            
            // Right side
            thumbnailView(
                entry: rightEntry,
                index: rightIndex,
                thumbnail: rightThumbnail,
                favoriteStatus: rightFavoriteStatus,
                isSelected: isRightSelected
            )
        }
        .environment(\.layoutDirection, direction.layoutDirection)  // #116: RTL spread inversion
        .background(Color.black.opacity(0.5))  // #187: subtle gap color between spread pair
        .frame(width: pairSize, height: pairSize)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .onAppear {
            loadThumbnails()
        }
    }
    
    @ViewBuilder
    private func thumbnailView(
        entry: ImageEntry,
        index: Int,
        thumbnail: NSImage?,
        favoriteStatus: CacheManager.FavoriteStatus,
        isSelected: Bool
    ) -> some View {
        ZStack {
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            
            // Favorite indicator
            if favoriteStatus == .direct {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                            .padding(2)
                    }
                    Spacer()
                }
            }
            
            // Selection indicator
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(overlayColor, lineWidth: 2)
            }
        }
        .frame(width: itemSize, height: itemSize * 1.55)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(index)
        }
    }
    
    private func loadThumbnails() {
        let maxSize = max(AppSettings.shared.effectiveRetinaThumbnailSize, 180)
        DispatchQueue.global(qos: .utility).async {
            let leftImage = imageSource.thumbnail(for: leftEntry, maxSize: maxSize)
            DispatchQueue.main.async {
                leftThumbnail = leftImage
            }
        }
        
        DispatchQueue.global(qos: .utility).async {
            let rightImage = imageSource.thumbnail(for: rightEntry, maxSize: maxSize)
            DispatchQueue.main.async {
                rightThumbnail = rightImage
            }
        }
    }
}

