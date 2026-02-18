//
//  DeskewService.swift
//  Erimil
//
//  Orchestrates deskew detection, caching, and correction.
//  Called from SpreadImageViewer and ImageViewerCore after fullImage load.
//  Session: S045 (2026-02-19) — #101
//
//  Usage (from background thread):
//    let corrected = DeskewService.processIfEnabled(
//        image: loadedImage,
//        sourceURL: source.url,
//        entryPath: entry.path
//    )
//

import Foundation
import AppKit
import os

enum DeskewService {
    
    /// Process image with deskew correction if enabled for the source.
    ///
    /// This is the single entry point for all viewers. Call from a background thread.
    ///
    /// Flow:
    /// 1. Check if deskew is enabled for this source → if not, return original
    /// 2. Check angle cache → if cached, apply correction immediately
    /// 3. If not cached, detect angle → cache it → apply correction
    ///
    /// - Parameters:
    ///   - image: Full-size image from `ImageSource.fullImage(for:)`
    ///   - sourceURL: URL of the current source
    ///   - entryPath: Entry path (e.g., "page_001")
    /// - Returns: Corrected image if deskew is active and angle detected, otherwise original image
    static func processIfEnabled(
        image: NSImage,
        sourceURL: URL,
        entryPath: String
    ) -> NSImage {
        let cache = CacheManager.shared
        
        // 1. Check if deskew is enabled for this source
        guard cache.isDeskewEnabled(for: sourceURL) else {
            return image
        }
        
        // 2. Check angle cache
        if cache.hasDeskewAngle(for: sourceURL, entryPath: entryPath) {
            let angle = cache.getDeskewAngle(for: sourceURL, entryPath: entryPath) ?? 0.0
            if abs(angle) <= DeskewDetector.negligibleAngle {
                return image
            }
            return DeskewDetector.applyCorrection(to: image, angle: angle) ?? image
        }
        
        // 3. Detect angle synchronously (we're already on a background thread)
        let detectedAngle = DeskewDetector.detectAngle(from: image)
        
        // Cache result (store 0.0 for "no correction" to avoid re-detection)
        let angle = detectedAngle ?? 0.0
        cache.setDeskewAngle(for: sourceURL, entryPath: entryPath, angle: angle)
        
        // Apply if non-negligible
        if abs(angle) > DeskewDetector.negligibleAngle {
            Logger.deskew.info("Applied deskew for \(entryPath): \(angle * 180 / CGFloat.pi, privacy: .public)°")
            return DeskewDetector.applyCorrection(to: image, angle: angle) ?? image
        }
        
        return image
    }
    
    /// Force re-detection for a source (clears cached angles).
    /// Next time pages are viewed, angles will be re-detected.
    static func resetDetection(for sourceURL: URL) {
        CacheManager.shared.clearDeskewAngles(for: sourceURL)
        Logger.deskew.info("Reset deskew detection for \(sourceURL.lastPathComponent)")
    }
}
