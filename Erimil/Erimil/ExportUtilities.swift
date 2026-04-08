//
//  ExportUtilities.swift
//  Erimil
//
//  Atomic-safe export utility to prevent data loss when
//  destination path equals source path (#161)
//

import Foundation
import AppKit
import os

enum ExportUtilities {
    
    /// Write to temporary file, then move to destination.
    ///
    /// Caller must ensure `destinationURL` does not already exist (use `guardDestination` first).
    /// - `writeOperation` receives a temporary URL — perform all I/O there.
    /// - On success: moves temp → destination.
    /// - On failure: temp file is cleaned up, no side effects.
    ///
    /// The temp file is created in the same directory as destination to ensure
    /// atomic rename on the same filesystem. Name starts with "." to hide from Finder.
    ///
    /// - Parameters:
    ///   - destinationURL: Final output path (must not exist)
    ///   - writeOperation: Closure that writes output to the provided temp URL
    static func safeExport(
        to destinationURL: URL,
        writeOperation: (URL) throws -> Void
    ) throws {
        let tempFileName = ".\(destinationURL.lastPathComponent).tmp_\(ProcessInfo.processInfo.globallyUniqueString)"
        let tempURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(tempFileName)
        
        Logger.export.debug("safeExport: temp=\(tempURL.lastPathComponent) → dest=\(destinationURL.lastPathComponent)")
        
        do {
            try writeOperation(tempURL)
            
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            Logger.export.info("safeExport: completed → \(destinationURL.lastPathComponent)")
        } catch {
            // Cleanup temp file on any failure
            try? FileManager.default.removeItem(at: tempURL)
            Logger.export.error("safeExport: failed — \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    /// Check that destination does not already exist.
    /// Returns localized error message if blocked, nil if safe to proceed.
    static func guardDestination(_ url: URL) -> String? {
        if FileManager.default.fileExists(atPath: url.path) {
            return "\(url.lastPathComponent) \(String(localized: "error.fileAlreadyExists", defaultValue: "already exists. Please choose a different name."))"
        }
        return nil
    }
}

// MARK: - Logger Extension

extension Logger {
    static let export = Logger(subsystem: "com.erimil.app", category: "Export")
}
