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
//  - #24 S084: Tile sheet integration (same pattern as ArchiveManager)
//

import Foundation
import AppKit
import PDFKit
import os
import CryptoKit
import ZIPFoundation

class PDFManager: ImageSource {
    let url: URL
    let sourceType: ImageSourceType = .pdf
    
    /// Cached PDF document
    private var document: PDFDocument?
    
    /// Serial queue for thread-safe access
    private let accessQueue = DispatchQueue(label: "com.erimil.pdf", qos: .userInitiated)
    
    // MARK: - Tile Sheet State (#24, S084)
    
    /// Tile sheet init + prefetch flags (consolidated block, S083 race fix pattern)
    private var tileSheetInitialized = false
    private var tileSheetAvailable = false
    private var prefetchStarted = false
    private var pdfArchiveHash: String?
    private let prefetchQueue = DispatchQueue(label: "com.erimil.pdf.prefetch", qos: .utility)
    
    init(pdfURL: URL) {
        self.url = pdfURL
    }
    
    // MARK: - ImageSource Protocol
    
    /// List all pages as image entries
    func listImageEntries() -> [ImageEntry] {
        return accessQueue.sync {
            Logger.pdf.debug("listImageEntries called for: \(self.url.lastPathComponent)")
            
            guard let doc = openDocument() else {
                Logger.pdf.error("Failed to open PDF: \(self.url)")
                return []
            }
            
            let pageCount = doc.pageCount
            Logger.pdf.debug("PDF has \(pageCount, privacy: .public) pages")
            
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
            
            Logger.pdf.info("Created \(entries.count, privacy: .public) entries")
            
            // #24 S084: Preload tile sheet into memory cache during entry listing.
            // This runs BEFORE any onAppear → loadThumbnailIfNeeded, ensuring the
            // synchronous memory check (SYNC memory hit) in ThumbnailGridView hits
            // for all tile-sheet-covered pages — no loading icon flash.
            if !tileSheetInitialized {
                tileSheetInitialized = true
                prefetchStarted = true
                if let hash = pdfHash() {
                    pdfArchiveHash = hash
                    let tileSheet = TileSheetCache.shared
                    if tileSheet.hasTileSheet(for: url, archiveHash: hash) {
                        tileSheetAvailable = true
                        let loaded = tileSheet.loadAllThumbnails(for: url, archiveHash: hash)
                        if loaded == 0 {
                            tileSheetAvailable = false
                            prefetchAllThumbnails(entries: entries)
                        } else {
                            Logger.pdf.info("TileSheet: preloaded \(loaded, privacy: .public) thumbnails for \(self.url.lastPathComponent)")
                            if loaded < entries.count {
                                tileSheetAvailable = false
                                Logger.pdf.info("TileSheet: partial coverage (\(loaded)/\(entries.count)) — starting prefetch")
                                prefetchAllThumbnails(entries: entries)
                            }
                        }
                    } else {
                        prefetchAllThumbnails(entries: entries)
                    }
                }
            }
            
            return entries
        }
    }
    
    /// Generate thumbnail for a page
    func thumbnail(for entry: ImageEntry, maxSize: CGFloat = AppSettings.shared.effectiveRetinaThumbnailSize) -> NSImage? {
        let cache = CacheManager.shared
        
        // Create unique path identifier: sourceURL + entryPath
        let fullPath = url.path + "/" + entry.path
        let pathHash = cache.pathHash(for: fullPath)
        
        // #24 S084: Fallback init — normally tile sheet is preloaded in listImageEntries().
        // This block fires only if thumbnail() is called before listImageEntries() (edge case).
        if !tileSheetInitialized {
            tileSheetInitialized = true
            prefetchStarted = true  // Set simultaneously to eliminate race window
            
            if let hash = pdfHash() {
                pdfArchiveHash = hash
                let tileSheet = TileSheetCache.shared
                if tileSheet.hasTileSheet(for: url, archiveHash: hash) {
                    // Set BEFORE loadAllThumbnails — other threads hitting cache HIT path
                    // must not registerThumbnail while load is in progress (causes rebuild
                    // with partial page set, overwriting complete tile sheet on disk)
                    tileSheetAvailable = true
                    let loaded = tileSheet.loadAllThumbnails(for: url, archiveHash: hash)
                    if loaded == 0 {
                        tileSheetAvailable = false  // Revert on load failure
                    } else {
                        Logger.pdf.info("TileSheet: preloaded for \(self.url.lastPathComponent)")
                    }
                }
            }
        }
        
        // Check if we have cached thumbnail (tile sheet load populates memory cache)
        if let contentHash = cache.getContentHash(for: pathHash),
           let cached = cache.getThumbnail(for: contentHash) {
            // #24 S084: Register for tile sheet even on cache hit (individual cache may exist
            // before tile sheet is built — without this, tile sheet never gets constructed)
            if !tileSheetAvailable, let hash = pdfArchiveHash {
                TileSheetCache.shared.registerThumbnail(
                    for: url, archiveHash: hash,
                    entryPath: entry.path, contentHash: contentHash,
                    image: cached
                )
            }
            Logger.pdf.debug("Cache HIT for \(entry.name)")
            return cached
        }
        
        // Cache miss - render thumbnail
        Logger.pdf.debug("Cache MISS for \(entry.name), rendering...")
        
        guard let pageIndex = pageIndex(from: entry.path),
              let doc = openDocument(),
              let page = doc.page(at: pageIndex) else {
            Logger.pdf.error("Failed to get page for \(entry.path)")
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
        
        // #24 S084: Register for deferred tile sheet build
        if !tileSheetAvailable, let hash = pdfArchiveHash {
            TileSheetCache.shared.registerThumbnail(
                for: url,
                archiveHash: hash,
                entryPath: entry.path,
                contentHash: contentHash,
                image: thumbnail
            )
        }
        
        Logger.pdf.debug("Generated and cached thumbnail for \(entry.name)")
        return thumbnail
    }
    
    func registerThumbnailForTileSheet(for entry: ImageEntry, contentHash: String, image: NSImage) {
        guard !tileSheetAvailable, let hash = pdfArchiveHash else { return }
        TileSheetCache.shared.registerThumbnail(
            for: url, archiveHash: hash, entryPath: entry.path,
            contentHash: contentHash, image: image
        )
    }
    
    /// Get full-size image for a page
    func fullImage(for entry: ImageEntry) -> NSImage? {
        // #165: Check memory cache first (prevents redundant render on SwiftUI re-evaluation)
        let cache = CacheManager.shared
        let fullPath = url.path + "/" + entry.path
        let pathHash = cache.pathHash(for: fullPath)
        if let contentHash = cache.getContentHash(for: pathHash),
           let cached = cache.getFullImageFromMemory(for: contentHash) {
            Logger.pdf.info("★PERF★ fullImage CACHE HIT \(entry.name)")
            return cached
        }
        
        return accessQueue.sync {
            // Double-check: another thread may have cached while we waited
            if let contentHash = cache.getContentHash(for: pathHash),
               let cached = cache.getFullImageFromMemory(for: contentHash) {
                Logger.pdf.info("★PERF★ fullImage CACHE HIT (queued) \(entry.name)")
                return cached
            }
            
            let t0 = CFAbsoluteTimeGetCurrent()
            
            guard let pageIndex = pageIndex(from: entry.path),
                  let doc = openDocument(),
                  let page = doc.page(at: pageIndex) else {
                Logger.pdf.error("fullImage: Failed to get page for \(entry.path)")
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
            
            let renderMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Logger.pdf.info("★PERF★ fullImage \(entry.name): render=\(String(format: "%.1f", renderMs))ms size=\(renderSize.debugDescription, privacy: .public)")
            
            // #165: Cache rendered image — pathHash as contentHash (PDF content is stable)
            let contentHash = pathHash
            cache.registerMapping(pathHash: pathHash, contentHash: contentHash)
            cache.cacheFullImage(image, for: contentHash)
            
            return image
        }
    }

    func fileURL(for entry: ImageEntry) -> URL? {
        nil
    }
    
    // MARK: - Private Helpers
    
    /// Open or return cached PDF document
    private func openDocument() -> PDFDocument? {
        if document == nil {
            document = PDFDocument(url: url)
            if document == nil {
                Logger.pdf.error("Failed to create PDFDocument for: \(self.url.path)")
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
            Logger.pdf.error("Invalid path format: \(path)")
            return nil
        }
        
        // Convert 1-based page number to 0-based index
        return pageNumber - 1
    }
    
    // MARK: - Tile Sheet Prefetch (#223)
    /// #223: entries passed as parameter to avoid accessQueue deadlock when called from listImageEntries().
    private func prefetchAllThumbnails(entries: [ImageEntry]) {
        let pdfURL = self.url
        let maxSize: CGFloat = AppSettings.shared.effectiveRetinaThumbnailSize
        guard let hash = pdfArchiveHash else { return }
        let settingsLimit = AppSettings.shared.prefetchPageLimit
        let limit = settingsLimit == 0 ? entries.count : min(entries.count, settingsLimit)

        prefetchQueue.async { [weak self] in
            guard let self = self else { return }
            let cache = CacheManager.shared
            let tileCache = TileSheetCache.shared

            Logger.pdf.info("TileSheet prefetch: starting \(limit, privacy: .public)/\(entries.count, privacy: .public) pages for \(pdfURL.lastPathComponent)")

            for i in 0..<limit {
                let entry = entries[i]
                let fullPath = pdfURL.path + "/" + entry.path
                let pathHash = cache.pathHash(for: fullPath)

                // Try existing cache first
                if let contentHash = cache.getContentHash(for: pathHash),
                   let cached = cache.getThumbnail(for: contentHash) {
                    tileCache.registerThumbnail(
                        for: pdfURL, archiveHash: hash, entryPath: entry.path,
                        contentHash: contentHash, image: cached
                    )
                    continue
                }

                // Cache miss — render page
                guard let pageIndex = self.pageIndex(from: entry.path),
                      let doc = self.openDocument(),
                      let page = doc.page(at: pageIndex) else { continue }

                let pageRect = page.bounds(for: .mediaBox)
                let scale = min(maxSize / pageRect.width, maxSize / pageRect.height, 1.0)
                let thumbnailSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
                let thumbnail = page.thumbnail(of: thumbnailSize, for: .mediaBox)

                let contentHash = pathHash
                cache.registerMapping(pathHash: pathHash, contentHash: contentHash)
                cache.saveThumbnail(thumbnail, for: contentHash)

                tileCache.registerThumbnail(
                    for: pdfURL, archiveHash: hash, entryPath: entry.path,
                    contentHash: contentHash, image: thumbnail
                )
            }

            Logger.pdf.info("TileSheet prefetch: completed \(limit, privacy: .public) pages")
            tileCache.finalizeBuild(for: hash)
        }
    }
    
    /// #24 S084: Content-based hash from PDF structure (page count + mediaBox dimensions).
    /// Same PDF structure produces the same hash regardless of file location.
    /// Analogous to TileSheetCache.archiveHash(for:) for ZIP archives.
    private func pdfHash() -> String? {
        guard let doc = openDocument() else { return nil }
        let pageCount = doc.pageCount
        guard pageCount > 0 else { return nil }
        
        var raw = "\(pageCount)"
        for i in 0..<pageCount {
            if let page = doc.page(at: i) {
                let box = page.bounds(for: .mediaBox)
                raw += ":\(Int(box.width))x\(Int(box.height))"
            }
        }
        
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Export Operations (#100)
    
    /// Export PDF excluding specified pages, creating an optimized PDF
    /// Uses atomic safe export to prevent data loss when destination == source (#161)
    /// - Parameters:
    ///   - pathsToRemove: Set of page paths to exclude (e.g., "page_001", "page_003")
    ///   - outputURL: Destination URL for the optimized PDF
    func exportOptimizedPDF(excluding pathsToRemove: Set<String>, to outputURL: URL) throws {
        let sourceDoc: PDFDocument? = accessQueue.sync { openDocument() }
        
        guard let sourceDoc else {
            throw PDFExportError.cannotOpenDocument
        }
        
        try ExportUtilities.safeExport(to: outputURL) { tempURL in
            let newDoc = PDFDocument()
            var insertIndex = 0
            
            for i in 0..<sourceDoc.pageCount {
                let pagePath = String(format: "page_%03d", i + 1)
                if pathsToRemove.contains(pagePath) {
                    Logger.pdf.debug("Excluding page \(i + 1, privacy: .public)")
                    continue
                }
                
                guard let page = sourceDoc.page(at: i) else {
                    Logger.pdf.error("Failed to get page at index \(i, privacy: .public)")
                    continue
                }
                
                newDoc.insert(page, at: insertIndex)
                insertIndex += 1
            }
            
            guard insertIndex > 0 else {
                throw PDFExportError.noRemainingPages
            }
            
            guard newDoc.write(to: tempURL) else {
                throw PDFExportError.writeFailed(tempURL)
            }
            
            Logger.pdf.info("Exported _opt.pdf: \(insertIndex, privacy: .public) pages to \(outputURL.lastPathComponent)")
        }
    }
    
    /// Export PDF pages as individual PNG images at 300dpi
    /// - Parameters:
    ///   - pathsToRemove: Set of page paths to exclude
    ///   - outputDirectory: Directory where subfolder will be created
    ///   - subfolder: Name of the subfolder (default: "{pdfName}_pages")
    /// - Returns: Number of exported pages
    @discardableResult
    func exportPagesAsPNG(excluding pathsToRemove: Set<String>, to outputDirectory: URL, subfolder: String? = nil) throws -> Int {
        let sourceDoc: PDFDocument? = accessQueue.sync { openDocument() }
        
        guard let sourceDoc else {
            throw PDFExportError.cannotOpenDocument
        }
        
        // Create subfolder
        let folderName = subfolder ?? "\(url.deletingPathExtension().lastPathComponent)_pages"
        let pagesDir = outputDirectory.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)
        
        let dpi: CGFloat = 300.0
        let scaleFactor = dpi / 72.0  // 4.1667
        var exportedCount = 0
        
        for i in 0..<sourceDoc.pageCount {
            let pagePath = String(format: "page_%03d", i + 1)
            if pathsToRemove.contains(pagePath) {
                continue
            }
            
            guard let page = sourceDoc.page(at: i) else {
                Logger.pdf.error("PNG export: failed to get page \(i + 1, privacy: .public)")
                continue
            }
            
            let mediaBox = page.bounds(for: .mediaBox)
            let renderWidth = Int(mediaBox.width * scaleFactor)
            let renderHeight = Int(mediaBox.height * scaleFactor)
            
            guard let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: renderWidth,
                pixelsHigh: renderHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                Logger.pdf.error("PNG export: failed to create bitmap for page \(i + 1, privacy: .public)")
                continue
            }
            
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
            NSGraphicsContext.current = context
            
            if let cgContext = context?.cgContext {
                // White background
                cgContext.setFillColor(NSColor.white.cgColor)
                cgContext.fill(CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight))
                
                // Scale and render
                cgContext.scaleBy(x: scaleFactor, y: scaleFactor)
                page.draw(with: .mediaBox, to: cgContext)
            }
            
            NSGraphicsContext.restoreGraphicsState()
            
            guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                Logger.pdf.error("PNG export: failed to create PNG data for page \(i + 1, privacy: .public)")
                continue
            }
            
            let fileName = String(format: "page_%03d.png", i + 1)
            let fileURL = pagesDir.appendingPathComponent(fileName)
            try pngData.write(to: fileURL)
            exportedCount += 1
        }
        
        guard exportedCount > 0 else {
            throw PDFExportError.noRemainingPages
        }
        
        Logger.pdf.info("Exported \(exportedCount, privacy: .public) PNG pages to \(pagesDir.lastPathComponent)")
        return exportedCount
    }
    
    /// Export PDF pages as PNG images packaged in a ZIP archive
    /// Uses atomic safe export to prevent data loss (#161)
    /// - Parameters:
    ///   - pathsToRemove: Set of page paths to exclude
    ///   - outputURL: Destination URL for the ZIP file (e.g., "sample_png.zip")
    /// - Returns: Number of exported pages
    @discardableResult
    func exportPagesAsPNGZip(excluding pathsToRemove: Set<String>, to outputURL: URL) throws -> Int {
        let sourceDoc: PDFDocument? = accessQueue.sync { openDocument() }
        
        guard let sourceDoc else {
            throw PDFExportError.cannotOpenDocument
        }
        
        var exportedCount = 0
        
        try ExportUtilities.safeExport(to: outputURL) { tempURL in
            // Create ZIP archive
            guard let archive = Archive(url: tempURL, accessMode: .create) else {
                throw PDFExportError.writeFailed(tempURL)
            }
            
            let dpi: CGFloat = 300.0
            let scaleFactor = dpi / 72.0
            
            for i in 0..<sourceDoc.pageCount {
                let pagePath = String(format: "page_%03d", i + 1)
                if pathsToRemove.contains(pagePath) {
                    continue
                }
                
                guard let page = sourceDoc.page(at: i) else {
                    Logger.pdf.error("PNG ZIP export: failed to get page \(i + 1, privacy: .public)")
                    continue
                }
                
                let mediaBox = page.bounds(for: .mediaBox)
                let renderWidth = Int(mediaBox.width * scaleFactor)
                let renderHeight = Int(mediaBox.height * scaleFactor)
                
                guard let bitmapRep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: renderWidth,
                    pixelsHigh: renderHeight,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                ) else {
                    Logger.pdf.error("PNG ZIP export: failed to create bitmap for page \(i + 1, privacy: .public)")
                    continue
                }
                
                NSGraphicsContext.saveGraphicsState()
                let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
                NSGraphicsContext.current = context
                
                if let cgContext = context?.cgContext {
                    cgContext.setFillColor(NSColor.white.cgColor)
                    cgContext.fill(CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight))
                    cgContext.scaleBy(x: scaleFactor, y: scaleFactor)
                    page.draw(with: .mediaBox, to: cgContext)
                }
                
                NSGraphicsContext.restoreGraphicsState()
                
                guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                    Logger.pdf.error("PNG ZIP export: failed to create PNG data for page \(i + 1, privacy: .public)")
                    continue
                }
                
                // Original page number preserved (飛び番)
                let fileName = String(format: "page_%03d.png", i + 1)
                try archive.addEntry(
                    with: fileName,
                    type: .file,
                    uncompressedSize: Int64(pngData.count),
                    provider: { position, size in
                        pngData.subdata(in: Int(position)..<Int(position) + size)
                    }
                )
                exportedCount += 1
            }
            
            guard exportedCount > 0 else {
                throw PDFExportError.noRemainingPages
            }
            
            Logger.pdf.info("Exported \(exportedCount, privacy: .public) PNG pages to ZIP: \(outputURL.lastPathComponent)")
        }
        
        return exportedCount
    }
}

// MARK: - PDF Export Errors (#100)

enum PDFExportError: LocalizedError {
    case cannotOpenDocument
    case noRemainingPages
    case writeFailed(URL)
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenDocument:
            return "PDFファイルを開けませんでした"
        case .noRemainingPages:
            return "出力するページがありません（すべて除外されています）"
        case .writeFailed(let url):
            return "PDFの書き込みに失敗しました: \(url.lastPathComponent)"
        }
    }
}
