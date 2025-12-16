//
//  ImageViewerCore.swift
//  Erimil
//
//  Created by and for Phase 2.2 - Slide Mode
//  Session: S003 (2025-12-17)
//

import SwiftUI
import AppKit

/// Core image viewer component shared between Quick Look and Slide Mode
/// Provides: image display, a/f navigation, position indicator
struct ImageViewerCore: View {
    let imageSource: any ImageSource
    let entries: [ImageEntry]
    @Binding var currentIndex: Int
    let showPositionIndicator: Bool
    
    @State private var loadedImage: NSImage?
    @State private var isLoading: Bool = true
    
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
            loadCurrentImage()
        }
        .onChange(of: currentIndex) { _, _ in
            loadCurrentImage()
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
        isLoading = true
        loadedImage = nil
        
        // Capture for async
        let capturedSource = imageSource
        let capturedEntry = entry
        
        DispatchQueue.global(qos: .userInitiated).async {
            let image = capturedSource.fullImage(for: capturedEntry)
            
            DispatchQueue.main.async {
                // Verify still the same index
                guard currentIndex >= 0 && currentIndex < entries.count,
                      entries[currentIndex].path == capturedEntry.path else {
                    return
                }
                
                loadedImage = image
                isLoading = false
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
        // TODO: Phase 2.2 Step 4 - implement z/c navigation
        return false
    }
    
    /// Navigate to next favorite (returns true if found and moved)
    func goToNextFavorite() -> Bool {
        // TODO: Phase 2.2 Step 4 - implement z/c navigation
        return false
    }
}

// MARK: - Preview

#Preview {
    ImageViewerCore(
        imageSource: ArchiveManager(zipURL: URL(fileURLWithPath: "/tmp/test.zip")),
        entries: [],
        currentIndex: .constant(0),
        showPositionIndicator: true
    )
}
