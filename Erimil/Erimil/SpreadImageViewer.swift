//
//  SpreadImageViewer.swift
//  Erimil
//
//  Image viewer with spread (two-page) support and double buffering
//  Extracted from SlideWindowController.swift for reuse across modes
//
//  Session: S021 (2026-01-26) - Refactoring #67
//  Original: S020 (2026-01-26) - Spread view implementation #55
//
//  Features:
//  - Double buffering for instant page transitions (no flicker)
//  - Spread (two-page) and single page display
//  - RTL (right-to-left) layout support for manga
//  - Auto-detect wide images as single pages
//  - Manual single page markers via V key
//

import SwiftUI
import AppKit

// MARK: - Spread Navigation Helper

/// Utility functions for spread-aware navigation calculations
/// Used by SlideWindowController, ImagePreviewView, and ViewerView
enum SpreadNavigationHelper {
    
    /// Check if page at given index should be shown as single page (for navigation)
    /// - Parameters:
    ///   - sourceURL: URL of the image source
    ///   - index: Page index to check
    ///   - totalCount: Total number of entries
    /// - Returns: true if page should be displayed as single
    static func shouldShowSinglePage(
        for sourceURL: URL,
        at index: Int,
        totalCount: Int
    ) -> Bool {
        // Spread mode disabled
        if !AppSettings.shared.isSpreadModeEnabled { return true }
        
        // Has single page marker
        if CacheManager.shared.hasSinglePageMarker(for: sourceURL, at: index) { return true }
        
        // Last page
        if index >= totalCount - 1 { return true }
        
        // Next page has marker
        if CacheManager.shared.hasSinglePageMarker(for: sourceURL, at: index + 1) { return true }
        
        return false
    }
    
    /// Calculate navigation step size (1 for single, 2 for spread)
    /// - Parameters:
    ///   - sourceURL: URL of the image source
    ///   - index: Current page index
    ///   - totalCount: Total number of entries
    /// - Returns: Step size (1 or 2)
    static func navigationStep(
        for sourceURL: URL,
        at index: Int,
        totalCount: Int
    ) -> Int {
        return shouldShowSinglePage(for: sourceURL, at: index, totalCount: totalCount) ? 1 : 2
    }
    
    /// Calculate previous index with spread awareness
    /// - Parameters:
    ///   - currentIndex: Current page index
    ///   - sourceURL: URL of the image source
    ///   - totalCount: Total number of entries
    ///   - loop: Whether to loop from first to last
    /// - Returns: New index, or nil if cannot go previous
    static func previousIndex(
        from currentIndex: Int,
        sourceURL: URL,
        totalCount: Int,
        loop: Bool
    ) -> Int? {
        guard totalCount > 0 else { return nil }
        
        // Calculate step based on previous page's spread state
        let step: Int
        if currentIndex >= 2 && !shouldShowSinglePage(for: sourceURL, at: currentIndex - 2, totalCount: totalCount) {
            // Previous spread started at currentIndex - 2
            step = 2
        } else {
            step = 1
        }
        
        if currentIndex >= step {
            return currentIndex - step
        } else if currentIndex > 0 {
            return 0  // Go to first page
        } else if loop {
            return totalCount - 1  // Loop to last
        }
        
        return nil
    }
    
    /// Calculate next index with spread awareness
    /// - Parameters:
    ///   - currentIndex: Current page index
    ///   - sourceURL: URL of the image source
    ///   - totalCount: Total number of entries
    ///   - loop: Whether to loop from last to first
    /// - Returns: New index, or nil if cannot go next
    static func nextIndex(
        from currentIndex: Int,
        sourceURL: URL,
        totalCount: Int,
        loop: Bool
    ) -> Int? {
        guard totalCount > 0 else { return nil }
        
        let step = navigationStep(for: sourceURL, at: currentIndex, totalCount: totalCount)
        let nextIdx = currentIndex + step
        
        if nextIdx < totalCount {
            return nextIdx
        } else if currentIndex < totalCount - 1 {
            return totalCount - 1  // Go to last page
        } else if loop {
            return 0  // Loop to first
        }
        
        return nil
    }
}

// MARK: - Spread Image Viewer

/// Image viewer with spread (two-page) support
/// Supports both Slide Mode and Quick Look with consistent behavior
struct SpreadImageViewer: View {
    let imageSource: any ImageSource
    let entries: [ImageEntry]
    @Binding var currentIndex: Int
    let favoriteIndices: Set<Int>
    var reloadTrigger: Bool = false  // External trigger for reload
    
    // Double buffering: two layers, switch instantly when ready
    @State private var bufferA: (left: NSImage?, right: NSImage?, index: Int)? = nil
    @State private var bufferB: (left: NSImage?, right: NSImage?, index: Int)? = nil
    @State private var activeBuffer: Int = 0  // 0 = A, 1 = B
    @State private var isLoading: Bool = true
    @State private var spreadUpdateTrigger: Bool = false
    
    /// Check if spread mode is enabled
    private var isSpreadEnabled: Bool {
        AppSettings.shared.isSpreadModeEnabled
    }
    
    /// Get spread threshold for auto-detection
    private var spreadThreshold: Double {
        AppSettings.shared.spreadThreshold
    }
    
    /// Check if current source uses RTL direction
    private var isRTL: Bool {
        CacheManager.shared.getEffectiveReadingDirection(for: imageSource.url) == .rtl
    }
    
    /// Check if an image is wide (likely a spread scan)
    private func isWideImage(_ image: NSImage?) -> Bool {
        guard let image = image else { return false }
        let ratio = image.size.width / image.size.height
        return ratio > spreadThreshold
    }
    
    /// Check if index has single page marker
    private func hasSingleMarker(_ index: Int) -> Bool {
        CacheManager.shared.hasSinglePageMarker(for: imageSource.url, at: index)
    }
    
    /// Determine if page at given index should be shown as single (based on loaded images)
    /// Note: This differs from SpreadNavigationHelper.shouldShowSinglePage as it considers
    /// the actual loaded image dimensions for wide image detection
    private func shouldShowSingle(atIndex index: Int, left: NSImage?, right: NSImage?) -> Bool {
        // Spread mode disabled
        if !isSpreadEnabled { return true }
        
        // Page has marker
        if hasSingleMarker(index) { return true }
        
        // Page is wide (auto-detect)
        if isWideImage(left) { return true }
        
        // No next page
        if index + 1 >= entries.count { return true }
        
        // Next page has marker
        if hasSingleMarker(index + 1) { return true }
        
        // Next page is wide
        if isWideImage(right) { return true }
        
        // No right image loaded
        if right == nil { return true }
        
        return false
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            // Only render the active buffer (prevents flash from old buffer)
            if activeBuffer == 0 {
                if let buffer = bufferA {
                    bufferView(buffer: buffer)
                }
            } else {
                if let buffer = bufferB {
                    bufferView(buffer: buffer)
                }
            }
            
            // Loading indicator (only on initial load)
            if isLoading && bufferA == nil && bufferB == nil {
                ProgressView("読み込み中...")
                    .foregroundStyle(.white)
                    .zIndex(2)
            }
        }
        .onAppear {
            loadImages()
        }
        .onChange(of: currentIndex) { _, _ in
            loadImages()
        }
        .onChange(of: imageSource.url) { _, _ in
            loadImages()
        }
        .onChange(of: reloadTrigger) { _, _ in
            loadImages()
        }
        .onChange(of: spreadUpdateTrigger) { _, _ in
            loadImages()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlideWindowSpreadChanged"))) { _ in
            spreadUpdateTrigger.toggle()
        }
    }
    
    @ViewBuilder
    private func bufferView(buffer: (left: NSImage?, right: NSImage?, index: Int)) -> some View {
        if let left = buffer.left {
            if shouldShowSingle(atIndex: buffer.index, left: left, right: buffer.right) {
                singlePageView(image: left)
            } else if let right = buffer.right {
                spreadPageView(leftImage: left, rightImage: right)
            } else {
                singlePageView(image: left)
            }
        }
    }
    
    @ViewBuilder
    private func singlePageView(image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .drawingGroup()  // Render offscreen first, then display at once
    }
    
    @ViewBuilder
    private func spreadPageView(leftImage: NSImage, rightImage: NSImage) -> some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height
            let availableWidth = geometry.size.width
            
            // Calculate optimal size for each page to fit within half width
            let leftRatio = leftImage.size.width / leftImage.size.height
            let rightRatio = rightImage.size.width / rightImage.size.height
            
            // Each page gets at most half the width
            let maxPageWidth = availableWidth / 2
            
            // Calculate height-constrained dimensions
            let leftHeightConstrained = (width: availableHeight * leftRatio, height: availableHeight)
            let rightHeightConstrained = (width: availableHeight * rightRatio, height: availableHeight)
            
            // Apply width constraint if needed
            let leftFinal = leftHeightConstrained.width > maxPageWidth
                ? (width: maxPageWidth, height: maxPageWidth / leftRatio)
                : leftHeightConstrained
            let rightFinal = rightHeightConstrained.width > maxPageWidth
                ? (width: maxPageWidth, height: maxPageWidth / rightRatio)
                : rightHeightConstrained
            
            // Use the smaller height to keep both pages aligned
            let finalHeight = min(leftFinal.height, rightFinal.height)
            let leftWidth = finalHeight * leftRatio
            let rightWidth = finalHeight * rightRatio
            
            HStack(spacing: 0) {
                if isRTL {
                    // RTL: right page (currentIndex+1) on left, left page (currentIndex) on right
                    Image(nsImage: rightImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: rightWidth, height: finalHeight)
                    
                    Image(nsImage: leftImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: leftWidth, height: finalHeight)
                } else {
                    // LTR: left page (currentIndex) on left, right page (currentIndex+1) on right
                    Image(nsImage: leftImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: leftWidth, height: finalHeight)
                    
                    Image(nsImage: rightImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: rightWidth, height: finalHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)  // Center in available space
            .drawingGroup()  // Render offscreen first, then display at once
        }
    }
    
    private func loadImages() {
        guard currentIndex >= 0 && currentIndex < entries.count else {
            bufferA = nil
            bufferB = nil
            isLoading = false
            return
        }
        
        let capturedSource = imageSource
        let capturedIndex = currentIndex
        let leftEntry = entries[currentIndex]
        let rightEntry = currentIndex + 1 < entries.count ? entries[currentIndex + 1] : nil
        let needsSpread = isSpreadEnabled && rightEntry != nil && !hasSingleMarker(currentIndex) && !hasSingleMarker(currentIndex + 1)
        
        // Determine which buffer to load into (the inactive one)
        let loadIntoA = activeBuffer == 1
        
        if needsSpread, let rightEntry = rightEntry {
            // Load both images in parallel
            var loadedLeft: NSImage?
            var loadedRight: NSImage?
            let group = DispatchGroup()
            
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                loadedLeft = capturedSource.fullImage(for: leftEntry)
                group.leave()
            }
            
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                loadedRight = capturedSource.fullImage(for: rightEntry)
                group.leave()
            }
            
            group.notify(queue: .main) {
                guard currentIndex == capturedIndex else { return }
                
                // Update buffer and switch instantly (no animation)
                withTransaction(Transaction(animation: nil)) {
                    if loadIntoA {
                        bufferA = (left: loadedLeft, right: loadedRight, index: capturedIndex)
                        activeBuffer = 0
                    } else {
                        bufferB = (left: loadedLeft, right: loadedRight, index: capturedIndex)
                        activeBuffer = 1
                    }
                    isLoading = false
                }
            }
        } else {
            // Single page mode
            DispatchQueue.global(qos: .userInitiated).async {
                let left = capturedSource.fullImage(for: leftEntry)
                
                DispatchQueue.main.async {
                    guard currentIndex == capturedIndex else { return }
                    
                    // Update buffer and switch instantly (no animation)
                    withTransaction(Transaction(animation: nil)) {
                        if loadIntoA {
                            bufferA = (left: left, right: nil, index: capturedIndex)
                            activeBuffer = 0
                        } else {
                            bufferB = (left: left, right: nil, index: capturedIndex)
                            activeBuffer = 1
                        }
                        isLoading = false
                    }
                }
            }
        }
    }
}
