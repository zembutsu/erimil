//
//  TileSheetCache.swift
//  Erimil
//
//  #24: Tile sheet thumbnail cache for ZIP archives
//  Combines N individual thumbnails into a single JPEG tile sheet,
//  reducing I/O from N reads to 1 read on subsequent opens.
//
//  Storage: ~/Library/Application Support/Erimil/tilesheets/
//    {archiveHash}.jpg   — tile sheet image (multiple: _0, _1, ...)
//    {archiveHash}.json  — metadata (tile positions, content hashes)
//

import Foundation
import AppKit
import CryptoKit
import os

// MARK: - TileSheetCache

class TileSheetCache {
    static let shared = TileSheetCache()

    // MARK: - Configuration

    let tileSize: Int = 120
    let tilesPerSheet: Int = 100
    let columns: Int = 10
    var compressionQuality: CGFloat = 0.6

    // MARK: - Storage

    private let directory: URL
    private let buildQueue = DispatchQueue(
        label: "jp.pocketstudio.zem.Erimil.TileSheetCache.build",
        qos: .utility
    )

    /// Pending builds: archiveHash → PendingBuild
    private var pendingBuilds: [String: PendingBuild] = [:]
    private let pendingLock = NSLock()

    /// Debounce interval: build fires this long after the last registerThumbnail call
    private let buildDebounceInterval: TimeInterval = 2.0

    // MARK: - Init

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        directory = appSupport
            .appendingPathComponent("Erimil", isDirectory: true)
            .appendingPathComponent("tilesheets", isDirectory: true)
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Archive Hash

    /// Lightweight hash from file attributes (no content read).
    /// Invalidates automatically when archive is modified.
    func archiveHash(for url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              let mtime = attrs[.modificationDate] as? Date else {
            return nil
        }
        let raw = "\(size):\(mtime.timeIntervalSince1970)"
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - File Paths

    private func metadataURL(for hash: String) -> URL {
        directory.appendingPathComponent("\(hash).json")
    }

    private func sheetImageURL(for hash: String, sheetIndex: Int) -> URL {
        if sheetIndex == 0 {
            return directory.appendingPathComponent("\(hash).jpg")
        }
        return directory.appendingPathComponent("\(hash)_\(sheetIndex).jpg")
    }

    // MARK: - Public API: Query

    /// Check if a tile sheet exists for the given archive.
    func hasTileSheet(for archiveURL: URL) -> Bool {
        guard let hash = archiveHash(for: archiveURL) else { return false }
        return FileManager.default.fileExists(atPath: metadataURL(for: hash).path)
    }

    // MARK: - Public API: Load

    /// Load all thumbnails from tile sheets into CacheManager memory cache.
    /// Call once per archive open. Returns number of thumbnails loaded.
    @discardableResult
    func loadAllThumbnails(for archiveURL: URL) -> Int {
        guard let hash = archiveHash(for: archiveURL),
              let metadata = loadMetadata(for: hash) else { return 0 }

        let cache = CacheManager.shared
        var loadedCount = 0

        for sheet in metadata.sheets {
            guard let sheetCGImage = loadSheetCGImage(hash: hash, sheetIndex: sheet.index) else {
                Logger.cache.error("TileSheet: failed to load sheet \(sheet.index, privacy: .public)")
                continue
            }

            for tile in sheet.entries {
                let cropRect = CGRect(
                    x: tile.x, y: tile.y,
                    width: tile.w, height: tile.h
                )
                guard let cropped = sheetCGImage.cropping(to: cropRect) else { continue }

                let nsImage = NSImage(
                    cgImage: cropped,
                    size: NSSize(width: tile.w, height: tile.h)
                )

                // Register pathHash → contentHash mapping (idempotent)
                let fullPath = archiveURL.path + "/" + tile.entryPath
                let pathHash = cache.pathHash(for: fullPath)
                cache.registerMapping(pathHash: pathHash, contentHash: tile.contentHash)

                // Memory cache only — tile sheet IS the disk cache
                cache.saveThumbnailToMemory(nsImage, for: tile.contentHash)
                loadedCount += 1
            }
        }

        Logger.cache.info("TileSheet: loaded \(loadedCount, privacy: .public) thumbnails for \(archiveURL.lastPathComponent)")
        return loadedCount
    }

    // MARK: - Public API: Deferred Build (Debounce)

    /// Register a generated thumbnail for deferred tile sheet build.
    /// Auto-creates pending build if needed. Triggers background build
    /// after `buildDebounceInterval` of inactivity (no new registrations).
    func registerThumbnail(
        for archiveURL: URL,
        entryPath: String,
        contentHash: String,
        image: NSImage
    ) {
        guard let hash = archiveHash(for: archiveURL) else { return }

        pendingLock.lock()

        // Auto-create pending build on first registration
        if pendingBuilds[hash] == nil {
            pendingBuilds[hash] = PendingBuild(
                archiveURL: archiveURL,
                archiveHash: hash,
                collected: [],
                buildWorkItem: nil
            )
            Logger.cache.debug("TileSheet: auto-created pending build for \(archiveURL.lastPathComponent)")
        }

        guard var build = pendingBuilds[hash] else {
            pendingLock.unlock()
            return
        }

        // Deduplicate (same entry registered twice)
        guard !build.collected.contains(where: { $0.entryPath == entryPath }) else {
            pendingLock.unlock()
            return
        }

        build.collected.append(CollectedThumbnail(
            entryPath: entryPath,
            contentHash: contentHash,
            image: image
        ))

        // Cancel previous debounce timer, schedule new one
        build.buildWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.triggerBuild(for: hash)
        }
        build.buildWorkItem = workItem
        pendingBuilds[hash] = build
        pendingLock.unlock()

        buildQueue.asyncAfter(
            deadline: .now() + buildDebounceInterval,
            execute: workItem
        )
    }

    // MARK: - Public API: Invalidation

    /// Remove tile sheets for an archive (call when archive is modified externally).
    func invalidate(for archiveURL: URL) {
        guard let hash = archiveHash(for: archiveURL) else { return }

        let fm = FileManager.default
        try? fm.removeItem(at: metadataURL(for: hash))

        // Remove sheet images (could be multiple)
        for i in 0..<100 {
            let url = sheetImageURL(for: hash, sheetIndex: i)
            guard fm.fileExists(atPath: url.path) else { break }
            try? fm.removeItem(at: url)
        }

        // Cancel pending build (including debounce timer)
        pendingLock.lock()
        pendingBuilds[hash]?.buildWorkItem?.cancel()
        pendingBuilds.removeValue(forKey: hash)
        pendingLock.unlock()

        Logger.cache.info("TileSheet: invalidated for \(archiveURL.lastPathComponent)")
    }

    // MARK: - Build

    private func triggerBuild(for hash: String) {
        pendingLock.lock()
        guard let build = pendingBuilds.removeValue(forKey: hash) else {
            pendingLock.unlock()
            return
        }
        pendingLock.unlock()

        buildQueue.async { [weak self] in
            self?.buildTileSheets(build)
        }
    }

    private func buildTileSheets(_ build: PendingBuild) {
        // Sort by entryPath (same order as ArchiveManager.listImageEntries)
        let sorted = build.collected.sorted {
            $0.entryPath.localizedStandardCompare($1.entryPath) == .orderedAscending
        }

        let chunks = stride(from: 0, to: sorted.count, by: tilesPerSheet).map {
            Array(sorted[$0..<min($0 + tilesPerSheet, sorted.count)])
        }

        var sheets: [TileSheetMetadata.SheetInfo] = []

        for (sheetIndex, chunk) in chunks.enumerated() {
            guard let sheetInfo = buildSingleSheet(
                chunk: chunk,
                sheetIndex: sheetIndex,
                baseEntryIndex: sheetIndex * tilesPerSheet,
                archiveHash: build.archiveHash
            ) else { continue }
            sheets.append(sheetInfo)
        }

        guard !sheets.isEmpty else {
            Logger.cache.error("TileSheet: build produced no sheets for \(build.archiveURL.lastPathComponent)")
            return
        }

        // Save metadata
        let metadata = TileSheetMetadata(
            version: 1,
            archiveHash: build.archiveHash,
            tileSize: tileSize,
            compressionQuality: Double(compressionQuality),
            sheets: sheets
        )
        saveMetadata(metadata, for: build.archiveHash)

        let totalTiles = sheets.reduce(0) { $0 + $1.entries.count }
        Logger.cache.info("TileSheet: built \(sheets.count, privacy: .public) sheet(s), \(totalTiles, privacy: .public) tiles for \(build.archiveURL.lastPathComponent)")
    }

    private func buildSingleSheet(
        chunk: [CollectedThumbnail],
        sheetIndex: Int,
        baseEntryIndex: Int,
        archiveHash: String
    ) -> TileSheetMetadata.SheetInfo? {
        let rows = (chunk.count + columns - 1) / columns
        let sheetWidth = columns * tileSize
        let sheetHeight = rows * tileSize

        guard let context = CGContext(
            data: nil,
            width: sheetWidth,
            height: sheetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            Logger.cache.error("TileSheet: CGContext creation failed for sheet \(sheetIndex, privacy: .public)")
            return nil
        }

        // Flip to top-left origin
        context.translateBy(x: 0, y: CGFloat(sheetHeight))
        context.scaleBy(x: 1, y: -1)

        var tileEntries: [TileSheetMetadata.TileEntry] = []

        for (i, item) in chunk.enumerated() {
            guard let cgImage = item.image.cgImage(
                forProposedRect: nil, context: nil, hints: nil
            ) else { continue }

            let col = i % columns
            let row = i / columns
            let x = col * tileSize
            let y = row * tileSize

            // Fit within tileSize maintaining aspect ratio
            let imgW = CGFloat(cgImage.width)
            let imgH = CGFloat(cgImage.height)
            let scale = min(CGFloat(tileSize) / imgW, CGFloat(tileSize) / imgH, 1.0)
            let drawW = Int(imgW * scale)
            let drawH = Int(imgH * scale)

            context.draw(cgImage, in: CGRect(x: x, y: y, width: drawW, height: drawH))

            tileEntries.append(TileSheetMetadata.TileEntry(
                entryIndex: baseEntryIndex + i,
                entryPath: item.entryPath,
                contentHash: item.contentHash,
                x: x, y: y, w: drawW, h: drawH
            ))
        }

        // Encode as JPEG
        guard let sheetCGImage = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  sheetImageURL(for: archiveHash, sheetIndex: sheetIndex) as CFURL,
                  "public.jpeg" as CFString, 1, nil
              ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, sheetCGImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            Logger.cache.error("TileSheet: JPEG finalize failed for sheet \(sheetIndex, privacy: .public)")
            return nil
        }

        return TileSheetMetadata.SheetInfo(
            index: sheetIndex,
            columns: columns,
            rows: rows,
            width: sheetWidth,
            height: sheetHeight,
            entries: tileEntries
        )
    }

    // MARK: - Metadata I/O

    private func loadMetadata(for hash: String) -> TileSheetMetadata? {
        let url = metadataURL(for: hash)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TileSheetMetadata.self, from: data)
    }

    private func saveMetadata(_ metadata: TileSheetMetadata, for hash: String) {
        let url = metadataURL(for: hash)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(metadata) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Sheet Image I/O

    private func loadSheetCGImage(hash: String, sheetIndex: Int) -> CGImage? {
        let url = sheetImageURL(for: hash, sheetIndex: sheetIndex)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - Pending Build Types

private extension TileSheetCache {

    struct PendingBuild {
        let archiveURL: URL
        let archiveHash: String
        var collected: [CollectedThumbnail]
        var buildWorkItem: DispatchWorkItem?
    }

    struct CollectedThumbnail {
        let entryPath: String
        let contentHash: String
        let image: NSImage
    }
}

// MARK: - Metadata Types

struct TileSheetMetadata: Codable {
    let version: Int
    let archiveHash: String
    let tileSize: Int
    let compressionQuality: Double
    let sheets: [SheetInfo]

    struct SheetInfo: Codable {
        let index: Int
        let columns: Int
        let rows: Int
        let width: Int
        let height: Int
        let entries: [TileEntry]
    }

    struct TileEntry: Codable {
        let entryIndex: Int
        let entryPath: String
        let contentHash: String
        let x: Int
        let y: Int
        let w: Int
        let h: Int
    }
}
