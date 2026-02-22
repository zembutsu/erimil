//
//  SourceSelection.swift
//  Erimil
//
//  S050: @Observable model for source selection state
//
//  Eliminates the @State × 2 + onChange × 2 chain in ContentView.
//  Property-level tracking ensures only views that read specific
//  properties are re-evaluated when those properties change.
//

import Foundation
import os

@Observable
class SourceSelection {
    /// Currently loaded image source (read by detail view)
    private(set) var currentSource: (any ImageSource)?
    
    /// Current source URL (read by sidebar for highlight)
    private(set) var currentURL: URL?
    
    /// Current source type
    private(set) var currentType: ImageSourceType?
    
    /// Select a new source — atomic update, no intermediate states
    /// - Parameters:
    ///   - url: Source URL (ZIP, folder, or PDF)
    ///   - type: Source type
    func select(url: URL, type: ImageSourceType) {
        // Skip if same source already loaded
        guard url != currentURL || type != currentType else {
            Logger.content.debug("[SourceSelection] Same source, skipping: \(url.lastPathComponent)")
            return
        }
        
        Logger.content.info("[SourceSelection] select: \(url.lastPathComponent) (type: \(String(describing: type)))")
        
        // Atomic update — all properties set before any view re-evaluation
        currentURL = url
        currentType = type
        
        switch type {
        case .archive:
            currentSource = ArchiveManager(zipURL: url)
        case .folder:
            currentSource = FolderManager(folderURL: url)
        case .pdf:
            currentSource = PDFManager(pdfURL: url)
        }
    }
    
    /// Clear all selection state
    func clear() {
        currentURL = nil
        currentType = nil
        currentSource = nil
    }
}
