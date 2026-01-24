//
//  ImagePrefetcher.swift
//  Erimil
//
//  Prefetches images for smooth navigation in Viewer/Slide modes
//  Session: S016 (2026-01-24)
//
//  Features:
//  - LRU cache with configurable size
//  - Cancellable prefetch tasks
//  - Direction-aware prefetching (prioritizes travel direction)
//  - Thread-safe via serial queue
//

import Foundation
import AppKit

/// Prefetches and caches full-size images for smooth viewer navigation
class ImagePrefetcher {
    
    // MARK: - Properties
    
    /// Serial queue for thread-safe cache access
    private let cacheQueue = DispatchQueue(label: "com.erimil.prefetcher.cache", qos: .userInitiated)
    
    /// Prefetch work queue (lower priority than main image load)
    private let prefetchQueue = DispatchQueue(label: "com.erimil.prefetcher.work", qos: .utility)
    
    /// Image cache: path -> NSImage
    private var cache: [String: NSImage] = [:]
    
    /// LRU access order (most recent at end)
    private var accessOrder: [String] = []
    
    /// Current prefetch task (for cancellation)
    private var currentPrefetchTask: DispatchWorkItem?
    
    /// Last navigation direction: 1 = forward, -1 = backward
    private var lastDirection: Int = 1
    
    /// Maximum cache size (computed from settings)
    private var maxCacheSize: Int {
        let prefetchCount = AppSettings.shared.prefetchCount
        // 1 (current) + prefetchCount (forward) + prefetchCount (backward)
        return max(1, 1 + prefetchCount * 2)
    }
    
    // MARK: - Public Interface
    
    /// Get cached image if available (thread-safe, synchronous)
    /// - Parameter path: Entry path to look up
    /// - Returns: Cached image or nil
    func getCached(for path: String) -> NSImage? {
        return cacheQueue.sync {
            guard let image = cache[path] else { return nil }
            
            // Update LRU order
            if let index = accessOrder.firstIndex(of: path) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(path)
            
            return image
        }
    }
    
    /// Add image to cache (thread-safe)
    /// - Parameters:
    ///   - path: Entry path
    ///   - image: Image to cache
    func addToCache(path: String, image: NSImage) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Add to cache
            self.cache[path] = image
            
            // Update LRU order
            if let index = self.accessOrder.firstIndex(of: path) {
                self.accessOrder.remove(at: index)
            }
            self.accessOrder.append(path)
            
            // Evict oldest if over limit
            self.evictIfNeeded()
        }
    }
    
    /// Start prefetching around the given index
    /// - Parameters:
    ///   - index: Current image index
    ///   - entries: All image entries
    ///   - imageSource: Source to load images from
    ///   - previousIndex: Previous index (to determine direction)
    func prefetchAround(
        index: Int,
        entries: [ImageEntry],
        imageSource: any ImageSource,
        previousIndex: Int
    ) {
        let prefetchCount = AppSettings.shared.prefetchCount
        guard prefetchCount > 0 else { return }
        
        // Cancel previous prefetch task
        currentPrefetchTask?.cancel()
        
        // Determine direction
        let direction: Int
        if index > previousIndex {
            direction = 1
            lastDirection = 1
        } else if index < previousIndex {
            direction = -1
            lastDirection = -1
        } else {
            direction = lastDirection
        }
        
        // Build prefetch list with direction priority
        let indicesToPrefetch = buildPrefetchList(
            currentIndex: index,
            direction: direction,
            count: prefetchCount,
            totalCount: entries.count
        )
        
        // Filter out already cached
        let uncachedIndices = cacheQueue.sync {
            indicesToPrefetch.filter { cache[entries[$0].path] == nil }
        }
        
        guard !uncachedIndices.isEmpty else { return }
        
        // Create cancellable work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            for targetIndex in uncachedIndices {
                // Check cancellation
                if self.currentPrefetchTask?.isCancelled == true {
                    print("[Prefetcher] Prefetch cancelled")
                    return
                }
                
                let entry = entries[targetIndex]
                
                // Skip if already cached (double-check)
                if self.getCached(for: entry.path) != nil {
                    continue
                }
                
                // Load image
                if let image = imageSource.fullImage(for: entry) {
                    self.addToCache(path: entry.path, image: image)
                    print("[Prefetcher] Prefetched: \(entry.name) (index \(targetIndex))")
                }
            }
        }
        
        currentPrefetchTask = workItem
        prefetchQueue.async(execute: workItem)
    }
    
    /// Clear all cached images (call on source change)
    func clearCache() {
        currentPrefetchTask?.cancel()
        currentPrefetchTask = nil
        
        cacheQueue.async { [weak self] in
            self?.cache.removeAll()
            self?.accessOrder.removeAll()
            print("[Prefetcher] Cache cleared")
        }
    }
    
    /// Get current cache statistics
    func getCacheStats() -> (count: Int, paths: [String]) {
        return cacheQueue.sync {
            (cache.count, Array(cache.keys))
        }
    }
    
    // MARK: - Private Helpers
    
    /// Build ordered list of indices to prefetch (direction-aware)
    private func buildPrefetchList(
        currentIndex: Int,
        direction: Int,
        count: Int,
        totalCount: Int
    ) -> [Int] {
        var indices: [Int] = []
        
        // Primary direction first (higher priority)
        for offset in 1...count {
            let primaryIndex = currentIndex + (direction * offset)
            if primaryIndex >= 0 && primaryIndex < totalCount {
                indices.append(primaryIndex)
            }
        }
        
        // Opposite direction second (lower priority)
        for offset in 1...count {
            let secondaryIndex = currentIndex - (direction * offset)
            if secondaryIndex >= 0 && secondaryIndex < totalCount {
                indices.append(secondaryIndex)
            }
        }
        
        return indices
    }
    
    /// Evict oldest entries if cache exceeds max size
    private func evictIfNeeded() {
        // Must be called on cacheQueue
        while cache.count > maxCacheSize && !accessOrder.isEmpty {
            let oldestPath = accessOrder.removeFirst()
            cache.removeValue(forKey: oldestPath)
            print("[Prefetcher] Evicted: \(oldestPath)")
        }
    }
}
