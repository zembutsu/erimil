//
//  TileSheetCache.swift
//  Erimil
//
//  #24: Tile sheet thumbnail cache for ZIP archives
//  Combines N individual thumbnails into a single tile sheet image,
//  reducing I/O from N reads to 1 read on subsequent opens.
//
//  #224: PNG lossless support — format-aware encoding and invalidation.
//
//  Storage: ~/Library/Application Support/Erimil/tilesheets/
//    {archiveHash}.ecache  — tile sheet image (multiple: _0, _1, ...)
//    {archiveHash}.ecmeta  — metadata (tile positions, content hashes)
//
//  Files use ERIM magic header to prevent Finder/Quick Look recognition.
//  Format matches CacheManager's .ecache obfuscation pattern.
//

import Foundation
import AppKit
import CryptoKit
import ZIPFoundation
import os

// MARK: - TileSheetCache

class TileSheetCache {
    static let shared = TileSheetCache()

    // MARK: - Configuration

    /// Magic bytes for .ecache/.ecmeta format ("ERIM" header) — matches CacheManager
    private static let ecacheMagic = Data([0x45, 0x52, 0x49, 0x4D])

    var tileSize: Int { Int(AppSettings.shared.effectiveRetinaThumbnailSize) }
    let tilesPerSheet: Int = 100
    let columns: Int = 10
    var compressionQuality: CGFloat { ThumbnailQualityPreset.current.compressionQuality }
    var imageFormat: String { ThumbnailQualityPreset.current.imageFormat }

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

    /// Content-based hash from ZIP Central Directory (entry names + sizes).
    /// Same archive contents produce the same hash regardless of file location or mtime.
    func archiveHash(for url: URL) -> String? {
        guard let archive = try? Archive(url: url, accessMode: .read) else { return nil }

        let raw = archive
            .filter { $0.type == .file }
            .map { "\($0.path):\($0.uncompressedSize)" }
            .sorted()
            .joined(separator: "\n")

        guard !raw.isEmpty else { return nil }
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - File Paths

    private func metadataURL(for hash: String) -> URL {
        directory.appendingPathComponent("\(hash).ecmeta")
    }

    private func sheetImageURL(for hash: String, sheetIndex: Int) -> URL {
        if sheetIndex == 0 {
            return directory.appendingPathComponent("\(hash).ecache")
        }
        return directory.appendingPathComponent("\(hash)_\(sheetIndex).ecache")
    }

    // MARK: - Public API: Query

    /// Check if a tile sheet exists for the given archive.
    func hasTileSheet(for archiveURL: URL, archiveHash hash: String) -> Bool {
        return FileManager.default.fileExists(atPath: metadataURL(for: hash).path)
    }

    // MARK: - Public API: Load

    /// Load all thumbnails from tile sheets into CacheManager memory cache.
    /// Call once per archive open. Returns number of thumbnails loaded.
    @discardableResult
    func loadAllThumbnails(for archiveURL: URL, archiveHash hash: String) -> Int {
        guard let metadata = loadMetadata(for: hash) else { return 0 }

        // #207/#224: Invalidate tile sheet if preset has changed since build
        if metadata.tileSize != tileSize ||
           metadata.compressionQuality != Double(compressionQuality) ||
           metadata.imageFormat != imageFormat {
            Logger.cache.info("TileSheet: preset mismatch (stored: \(metadata.tileSize)/\(metadata.compressionQuality)/\(metadata.imageFormat), current: \(self.tileSize)/\(self.compressionQuality)/\(self.imageFormat)) — will rebuild")
            // Evict stale thumbnails from memory and disk cache so async path
            // regenerates at new size (not falling back to old .ecache on disk)
            let cache = CacheManager.shared
            for sheet in metadata.sheets {
                for tile in sheet.entries {
                    cache.removeThumbnailFromMemory(for: tile.contentHash)
                    cache.removeThumbnailFromDisk(for: tile.contentHash)
                }
            }
            invalidate(for: archiveURL, archiveHash: hash)
            return 0
        }

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
        archiveHash hash: String,
        entryPath: String,
        contentHash: String,
        image: NSImage
    ) {
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
    func invalidate(for archiveURL: URL, archiveHash hash: String) {

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
    
    /// Finalize pending build immediately (cancel debounce timer).
    /// Called when prefetch completes — all entries are registered.
    func finalizeBuild(for hash: String) {
        pendingLock.lock()
        guard let build = pendingBuilds.removeValue(forKey: hash) else {
            pendingLock.unlock()
            return
        }
        build.buildWorkItem?.cancel()
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
            imageFormat: imageFormat,
            sheets: sheets
        )
        saveMetadata(metadata, for: build.archiveHash)

        let totalTiles = sheets.reduce(0) { $0 + $1.entries.count }
        Logger.cache.info("TileSheet: built \(sheets.count, privacy: .public) sheet(s), \(totalTiles, privacy: .public) tiles [\(self.imageFormat)] for \(build.archiveURL.lastPathComponent)")
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

            // Local flip to cancel global context flip (otherwise image content is inverted)
            context.saveGState()
            context.translateBy(x: CGFloat(x), y: CGFloat(y + drawH))
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: drawW, height: drawH))
            context.restoreGState()

            tileEntries.append(TileSheetMetadata.TileEntry(
                entryIndex: baseEntryIndex + i,
                entryPath: item.entryPath,
                contentHash: item.contentHash,
                x: x, y: y, w: drawW, h: drawH
            ))
        }

        // Encode to image data, then prepend ERIM header for Finder obfuscation
        guard let sheetCGImage = context.makeImage() else { return nil }

        let usePNG = ThumbnailQualityPreset.current.isPNG
        let uti = usePNG ? "public.png" as CFString : "public.jpeg" as CFString

        let encodedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encodedData, uti, 1, nil
        ) else { return nil }

        if usePNG {
            // PNG: no compression quality option needed (lossless by format)
            CGImageDestinationAddImage(destination, sheetCGImage, nil)
        } else {
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: compressionQuality
            ]
            CGImageDestinationAddImage(destination, sheetCGImage, options as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            Logger.cache.error("TileSheet: \(usePNG ? "PNG" : "JPEG") finalize failed for sheet \(sheetIndex, privacy: .public)")
            return nil
        }

        var output = Self.ecacheMagic
        output.append(encodedData as Data)
        do {
            try output.write(to: sheetImageURL(for: archiveHash, sheetIndex: sheetIndex), options: .atomic)
        } catch {
            Logger.cache.error("TileSheet: write failed for sheet \(sheetIndex, privacy: .public): \(error, privacy: .public)")
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
        guard let raw = try? Data(contentsOf: url) else { return nil }
        // Strip ERIM magic header (with legacy fallback for plain JSON)
        let jsonData = raw.prefix(4) == Self.ecacheMagic ? Data(raw.dropFirst(4)) : raw
        return try? JSONDecoder().decode(TileSheetMetadata.self, from: jsonData)
    }

    private func saveMetadata(_ metadata: TileSheetMetadata, for hash: String) {
        let url = metadataURL(for: hash)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let jsonData = try? encoder.encode(metadata) else { return }
        var output = Self.ecacheMagic
        output.append(jsonData)
        try? output.write(to: url, options: .atomic)
    }

    // MARK: - Sheet Image I/O

    private func loadSheetCGImage(hash: String, sheetIndex: Int) -> CGImage? {
        let url = sheetImageURL(for: hash, sheetIndex: sheetIndex)
        guard let raw = try? Data(contentsOf: url) else { return nil }
        // Strip ERIM magic header (with legacy fallback for raw image data)
        let imageData = raw.prefix(4) == Self.ecacheMagic ? Data(raw.dropFirst(4)) : raw
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
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
    let imageFormat: String   // "jpeg" or "png" (#224)
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

    // MARK: - Initializers

    init(version: Int, archiveHash: String, tileSize: Int,
         compressionQuality: Double, imageFormat: String, sheets: [SheetInfo]) {
        self.version = version
        self.archiveHash = archiveHash
        self.tileSize = tileSize
        self.compressionQuality = compressionQuality
        self.imageFormat = imageFormat
        self.sheets = sheets
    }

    /// Backward compatibility: decode existing metadata that lacks imageFormat field (pre-#224, always JPEG).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        archiveHash = try container.decode(String.self, forKey: .archiveHash)
        tileSize = try container.decode(Int.self, forKey: .tileSize)
        compressionQuality = try container.decode(Double.self, forKey: .compressionQuality)
        imageFormat = try container.decodeIfPresent(String.self, forKey: .imageFormat) ?? "jpeg"
        sheets = try container.decode([SheetInfo].self, forKey: .sheets)
    }
}
