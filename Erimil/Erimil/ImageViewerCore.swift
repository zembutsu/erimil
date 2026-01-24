//
//  ImageViewerCore.swift
//  Erimil
//
//  Created by and for Phase 2.2 - Slide Mode
//  Session: S003 (2025-12-17)
//  Updated: S016 (2026-01-24) - Added prefetch support
//

import SwiftUI
import AppKit

/// Core image viewer component shared between Quick Look and Slide Mode
/// Provides: image display, a/d navigation, z/c favorite jump, position indicator
struct ImageViewerCore: View {
    let imageSource: any ImageSource
    let entries: [ImageEntry]
    @Binding var currentIndex: Int
    let showPositionIndicator: Bool
    let favoriteIndices: Set<Int>  // Indices of favorite entries for z/c navigation
    
    @State private var loadedImage: NSImage?
    @State private var isLoading: Bool = true
    @State private var prefetcher = ImagePrefetcher()
    @State private var previousIndex: Int = 0
    @State private var currentSourceURL: URL?
    
    var body: some View {
        ZStack {
            // Background
            Color.black
            
            // Image display
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView("読み込み中...")
                    .foregroundStyle(.white)
            } else {
                // Failed to load
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text("画像を読み込めませんでした")
                        .foregroundStyle(.white)
                }
            }
            
            // Position indicator (top-right)
            if showPositionIndicator && !entries.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(currentIndex + 1) / \(entries.count)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            // Check for source change
            if currentSourceURL != imageSource.url {
                prefetcher.clearCache()
                currentSourceURL = imageSource.url
            }
            previousIndex = currentIndex
            loadCurrentImage()
        }
        .onChange(of: currentIndex) { oldValue, newValue in
            previousIndex = oldValue
            loadCurrentImage()
        }
        .onChange(of: imageSource.url) { _, newURL in
            // Source changed - clear cache
            prefetcher.clearCache()
            currentSourceURL = newURL
        }
    }
    
    // MARK: - Image Loading
    
    private func loadCurrentImage() {
        guard currentIndex >= 0 && currentIndex < entries.count else {
            loadedImage = nil
            isLoading = false
            return
        }
        
        let entry = entries[currentIndex]
        
        // Check prefetch cache first
        if let cachedImage = prefetcher.getCached(for: entry.path) {
            loadedImage = cachedImage
            isLoading = false
            
            // Trigger prefetch for surrounding images
            prefetcher.prefetchAround(
                index: currentIndex,
                entries: entries,
                imageSource: imageSource,
                previousIndex: previousIndex
            )
            print("[ImageViewerCore] Cache HIT for \(entry.name)")
            return
        }
        
        // Cache miss - load normally
        isLoading = true
        loadedImage = nil
        print("[ImageViewerCore] Cache MISS for \(entry.name), loading...")
        
        // Capture for async
        let capturedSource = imageSource
        let capturedEntry = entry
        let capturedIndex = currentIndex
        
        DispatchQueue.global(qos: .userInitiated).async {
            let image = capturedSource.fullImage(for: capturedEntry)
            
            DispatchQueue.main.async {
                // Verify still the same index
                guard currentIndex == capturedIndex else {
                    return
                }
                
                if let image = image {
                    // Add to cache
                    prefetcher.addToCache(path: capturedEntry.path, image: image)
                }
                
                loadedImage = image
                isLoading = false
                
                // Start prefetching surrounding images
                prefetcher.prefetchAround(
                    index: currentIndex,
                    entries: entries,
                    imageSource: imageSource,
                    previousIndex: previousIndex
                )
            }
        }
    }
    
    // MARK: - Navigation
    
    /// Navigate to previous image (returns true if moved)
    func goToPrevious() -> Bool {
        guard currentIndex > 0 else { return false }
        currentIndex -= 1
        return true
    }
    
    /// Navigate to next image (returns true if moved)
    func goToNext() -> Bool {
        guard currentIndex < entries.count - 1 else { return false }
        currentIndex += 1
        return true
    }
    
    /// Navigate to previous favorite (returns true if found and moved)
    func goToPreviousFavorite() -> Bool {
        guard !favoriteIndices.isEmpty else { return false }
        
        // Find the largest favorite index that is less than currentIndex
        let previousFavorites = favoriteIndices.filter { $0 < currentIndex }
        guard let targetIndex = previousFavorites.max() else {
            // No favorite before current position - wrap to last favorite
            if let lastFavorite = favoriteIndices.max(), lastFavorite != currentIndex {
                currentIndex = lastFavorite
                return true
            }
            return false
        }
        
        currentIndex = targetIndex
        return true
    }
    
    /// Navigate to next favorite (returns true if found and moved)
    func goToNextFavorite() -> Bool {
        guard !favoriteIndices.isEmpty else { return false }
        
        // Find the smallest favorite index that is greater than currentIndex
        let nextFavorites = favoriteIndices.filter { $0 > currentIndex }
        guard let targetIndex = nextFavorites.min() else {
            // No favorite after current position - wrap to first favorite
            if let firstFavorite = favoriteIndices.min(), firstFavorite != currentIndex {
                currentIndex = firstFavorite
                return true
            }
            return false
        }
        
        currentIndex = targetIndex
        return true
    }
}

// MARK: - Preview

#Preview {
    ImageViewerCore(
        imageSource: ArchiveManager(zipURL: URL(fileURLWithPath: "/tmp/test.zip")),
        entries: [],
        currentIndex: .constant(0),
        showPositionIndicator: true,
        favoriteIndices: []
    )
}
