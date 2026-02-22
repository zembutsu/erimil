//
//  SourceSelection.swift
//  Erimil
//
//  S050: @Observable model for source selection state
//
//  Prefetch uses NSLock for thread-safe direct write from background thread,
//  bypassing DispatchQueue.main.async which gets blocked by SwiftUI re-evaluation.
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
    
    // MARK: - Prefetch (lock-based, not main-thread-dependent)
    
    /// Lock protecting prefetch buffer — allows background write + main thread read
    private let prefetchLock = NSLock()
    private var _prefetchedEntries: [ImageEntry]?
    private var _prefetchedURL: URL?
    private var prefetchID: UUID?
    
    /// Consume prefetched entries if available for the given source URL.
    /// Thread-safe: can be called from main thread while background is writing.
    /// Returns entries and clears the buffer, or nil if not ready/mismatched.
    func consumePrefetchedEntries(for url: URL) -> [ImageEntry]? {
        prefetchLock.lock()
        defer { prefetchLock.unlock() }
        
        guard let entries = _prefetchedEntries, _prefetchedURL == url else {
            return nil
        }
        // Consume — one-time use
        _prefetchedEntries = nil
        _prefetchedURL = nil
        return entries
    }
    
    /// Select a new source — atomic update, no intermediate states
    func select(url: URL, type: ImageSourceType) {
        // Skip if same source already loaded
        guard url != currentURL || type != currentType else {
            Logger.content.debug("[SourceSelection] Same source, skipping: \(url.lastPathComponent)")
            return
        }
        
        // S050: T2 — model update starts
        SourceSwitchTiming.mark("select.start")
        
        Logger.content.info("[SourceSelection] select: \(url.lastPathComponent) (type: \(String(describing: type)))")
        
        // Invalidate any in-flight prefetch
        prefetchLock.lock()
        _prefetchedEntries = nil
        _prefetchedURL = nil
        prefetchLock.unlock()
        
        // Atomic update — all properties set before any view re-evaluation
        currentURL = url
        currentType = type
        
        let source: any ImageSource
        switch type {
        case .archive:
            source = ArchiveManager(zipURL: url)
        case .folder:
            source = FolderManager(folderURL: url)
        case .pdf:
            source = PDFManager(pdfURL: url)
        }
        currentSource = source
        
        // S050: T3 — model update complete, SwiftUI re-evaluation will follow
        SourceSwitchTiming.mark("select.done")
        
        // Start prefetch immediately — writes result via lock, not main thread queue
        let thisID = UUID()
        prefetchID = thisID
        SourceSwitchTiming.mark("prefetch.start")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = source.listImageEntries()
            
            guard let self, self.prefetchID == thisID else {
                Logger.content.debug("[SourceSelection] Prefetch stale, discarding")
                return
            }
            
            // Write directly via lock — available immediately to loadSource()
            self.prefetchLock.lock()
            self._prefetchedEntries = entries
            self._prefetchedURL = url
            self.prefetchLock.unlock()
            
            SourceSwitchTiming.mark("prefetch.ready(\(entries.count))")
        }
    }
    
    /// Clear all selection state
    func clear() {
        currentURL = nil
        currentType = nil
        currentSource = nil
        prefetchLock.lock()
        _prefetchedEntries = nil
        _prefetchedURL = nil
        prefetchLock.unlock()
        prefetchID = nil
    }
}
