//
//  SourceSelection.swift
//  Erimil
//
//  S050: @Observable model for source selection state
//  S090: Added onSourceChanged callback for immediate detail swap (#215 Phase 1)
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
    
    /// S090: Immediate notification callback — called synchronously from select(),
    /// bypassing SwiftUI's ~350ms @Observable → body → updateNSViewController cycle.
    /// Set by ErimilSplitViewRepresentable's Coordinator.
    var onSourceChanged: ((URL?, (any ImageSource)?) -> Void)?
    
    // MARK: - Prefetch (lock-based, not main-thread-dependent)
    
    /// Lock protecting prefetch buffer — allows background write + main thread read
    private let prefetchLock = NSLock()
    private var _prefetchedEntries: [ImageEntry]?
    private var _prefetchedURL: URL?
    private var prefetchID: UUID?
    
    /// S092: Pending consumer — stored when loadSource requests entries before prefetch completes
    private var pendingConsumer: (([ImageEntry]) -> Void)?
    
    /// S092: Request entries for the given URL.
    /// If prefetch is already complete, calls completion synchronously (prefetch.hit).
    /// Otherwise, stores completion and calls it when prefetch finishes (prefetch.await).
    /// Completion is always called on the main thread.
    func requestEntries(for url: URL, completion: @escaping ([ImageEntry]) -> Void) {
        prefetchLock.lock()
        if let entries = _prefetchedEntries, _prefetchedURL == url {
            // Prefetch ready — consume immediately
            _prefetchedEntries = nil
            _prefetchedURL = nil
            pendingConsumer = nil
            prefetchLock.unlock()
            SourceSwitchTiming.mark("prefetch.hit")
            completion(entries)
            return
        }
        // Not ready — store callback for prefetch completion
        pendingConsumer = completion
        prefetchLock.unlock()
        SourceSwitchTiming.mark("prefetch.await")
    }
    
    func select(url: URL, type: ImageSourceType) {
        guard url != currentURL || type != currentType else {
            Logger.content.debug("[SourceSelection] Same source, skipping: \(url.lastPathComponent)")
            return
        }
        
        SourceSwitchTiming.mark("select.start")
        Logger.content.info("[SourceSelection] select: \(url.lastPathComponent) (type: \(String(describing: type)))")
        
        // Invalidate any in-flight prefetch + pending consumer
        prefetchLock.lock()
        _prefetchedEntries = nil
        _prefetchedURL = nil
        pendingConsumer = nil          // ← S092: added
        prefetchLock.unlock()
        
        // Atomic update
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
        
        SourceSwitchTiming.mark("select.done")
        
        // S091: Save for restoration
        AppSettings.shared.lastSelectedSourcePath = url.path
        AppSettings.shared.lastSelectedSourceType = type.rawValue
        
        // S092: Start prefetch BEFORE onSourceChanged.
        // onSourceChanged → loadSource → requestEntries will store pendingConsumer.
        // When prefetch completes, it delivers entries via that consumer.
        // Result: exactly ONE listImageEntries call per source switch.
        let thisID = UUID()
        prefetchID = thisID
        SourceSwitchTiming.mark("prefetch.start")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = source.listImageEntries()
            
            guard let self, self.prefetchID == thisID else {
                Logger.content.debug("[SourceSelection] Prefetch stale, discarding")
                return
            }
            
            self.prefetchLock.lock()
            self._prefetchedEntries = entries
            self._prefetchedURL = url
            let consumer = self.pendingConsumer
            self.pendingConsumer = nil
            self.prefetchLock.unlock()
            
            SourceSwitchTiming.mark("prefetch.ready(\(entries.count))")
            
            // S092: Deliver to waiting loadSource if it's pending
            if let consumer {
                DispatchQueue.main.async {
                    consumer(entries)
                }
            }
        }
        
        // S090: Immediate detail swap — synchronous from select()
        SourceSwitchTiming.mark("direct.swap")
        onSourceChanged?(url, source)
    }
    
    /// Clear all selection state
    func clear() {
        currentURL = nil
        currentType = nil
        currentSource = nil
        // S091: Clear saved source
        AppSettings.shared.lastSelectedSourcePath = nil
        AppSettings.shared.lastSelectedSourceType = nil

        onSourceChanged?(nil, nil)
        prefetchLock.lock()
        _prefetchedEntries = nil
        _prefetchedURL = nil
        pendingConsumer = nil          // ← S092: added
        prefetchLock.unlock()
        prefetchID = nil
    }
}
