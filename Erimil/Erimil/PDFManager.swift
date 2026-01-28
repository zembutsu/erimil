//
//  PDFManager.swift
//  Erimil
//
//  ImageSource implementation for PDF documents
//  Session: S024 (2026-01-28)
//
//  Features:
//  - Each PDF page treated as an ImageEntry
//  - Lazy page rendering for performance
//  - Uses system PDFKit (no external dependencies)
//

import Foundation
import AppKit
import PDFKit

class PDFManager: ImageSource {
    let url: URL
    let sourceType: ImageSourceType = .pdf
    
    /// Cached PDF document
    private var document: PDFDocument?
    
    /// Serial queue for thread-safe access
    private let accessQueue = DispatchQueue(label: "com.erimil.pdf", qos: .userInitiated)
    
    init(pdfURL: URL) {
        self.url = pdfURL
    }
    
    // MARK: - ImageSource Protocol
    
    /// List all pages as image entries
    func listImageEntries() -> [ImageEntry] {
        return accessQueue.sync {
            print("[PDFManager] listImageEntries called for: \(url.lastPathComponent)")
            
            guard let doc = openDocument() else {
                print("[PDFManager] Failed to open PDF: \(url)")
                return []
            }
            
            let pageCount = doc.pageCount
            print("[PDFManager] PDF has \(pageCount) pages")
            
            var entries: [ImageEntry] = []
            for i in 0..<pageCount {
                // Create entry with page-based path
                // Format: page_001, page_002, etc. (zero-padded for sorting)
                let pageNumber = i + 1
                let path = String(format: "page_%03d", pageNumber)
                let name = "\(pageNumber)ページ"
                
                // Estimate size from page dimensions (for display purposes)
                let estimatedSize: UInt64
                if let page = doc.page(at: i) {
                    let bounds = page.bounds(for: .mediaBox)
                    // Rough estimate: width * height * 4 bytes (RGBA)
                    estimatedSize = UInt64(bounds.width * bounds.height * 4)
                } else {
                    estimatedSize = 0
                }
                
                let entry = ImageEntry(path: path, name: name, size: estimatedSize)
                entries.append(entry)
            }
            
            print("[PDFManager] Created \(entries.count) entries")
            return entries
        }
    }
    
    /// Generate thumbnail for a page
    func thumbnail(for entry: ImageEntry, maxSize: CGFloat = 120) -> NSImage? {
        let cache = CacheManager.shared
        
        // Create unique path identifier: sourceURL + entryPath
        let fullPath = url.path + "/" + entry.path
        let pathHash = cache.pathHash(for: fullPath)
        
        // Check if we have cached thumbnail
        if let contentHash = cache.getContentHash(for: pathHash),
           let cached = cache.getThumbnail(for: contentHash) {
            print("[PDFManager] Cache HIT for \(entry.name)")
            return cached
        }
        
        // Cache miss - render thumbnail
        print("[PDFManager] Cache MISS for \(entry.name), rendering...")
        
        guard let pageIndex = pageIndex(from: entry.path),
              let doc = openDocument(),
              let page = doc.page(at: pageIndex) else {
            print("[PDFManager] Failed to get page for \(entry.path)")
            return nil
        }
        
        // Render thumbnail
        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(maxSize / pageRect.width, maxSize / pageRect.height, 1.0)
        let thumbnailSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )
        
        let thumbnail = page.thumbnail(of: thumbnailSize, for: .mediaBox)
        
        // Use path-based hash as content hash for PDFs
        // (PDF content doesn't change like ZIP extraction might)
        let contentHash = pathHash
        
        // Register mapping and save
        cache.registerMapping(pathHash: pathHash, contentHash: contentHash)
        cache.saveThumbnail(thumbnail, for: contentHash)
        
        print("[PDFManager] Generated and cached thumbnail for \(entry.name)")
        return thumbnail
    }
    
    /// Get full-size image for a page
    func fullImage(for entry: ImageEntry) -> NSImage? {
        return accessQueue.sync {
            guard let pageIndex = pageIndex(from: entry.path),
                  let doc = openDocument(),
                  let page = doc.page(at: pageIndex) else {
                print("[PDFManager] fullImage: Failed to get page for \(entry.path)")
                return nil
            }
            
            // Render at screen resolution (72 dpi base, scaled up for quality)
            let pageRect = page.bounds(for: .mediaBox)
            
            // Scale factor for high-quality rendering
            // 2.0 gives good balance between quality and memory
            let scaleFactor: CGFloat = 2.0
            let renderSize = CGSize(
                width: pageRect.width * scaleFactor,
                height: pageRect.height * scaleFactor
            )
            
            // Create image by rendering PDF page
            let image = NSImage(size: renderSize)
            image.lockFocus()
            
            if let context = NSGraphicsContext.current?.cgContext {
                // White background (PDFs may have transparency)
                context.setFillColor(NSColor.white.cgColor)
                context.fill(CGRect(origin: .zero, size: renderSize))
                
                // Scale and render
                context.scaleBy(x: scaleFactor, y: scaleFactor)
                page.draw(with: .mediaBox, to: context)
            }
            
            image.unlockFocus()
            
            print("[PDFManager] Rendered full image for \(entry.name): \(renderSize)")
            return image
        }
    }
    
    // MARK: - Private Helpers
    
    /// Open or return cached PDF document
    private func openDocument() -> PDFDocument? {
        if document == nil {
            document = PDFDocument(url: url)
            if document == nil {
                print("[PDFManager] Failed to create PDFDocument for: \(url.path)")
            }
        }
        return document
    }
    
    /// Extract page index from entry path
    /// "page_001" -> 0, "page_002" -> 1, etc.
    private func pageIndex(from path: String) -> Int? {
        // Extract number from "page_XXX" format
        guard path.hasPrefix("page_"),
              let numberString = path.split(separator: "_").last,
              let pageNumber = Int(numberString) else {
            print("[PDFManager] Invalid path format: \(path)")
            return nil
        }
        
        // Convert 1-based page number to 0-based index
        return pageNumber - 1
    }
}
