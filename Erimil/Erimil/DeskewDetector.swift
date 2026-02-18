//
//  DeskewDetector.swift
//  Erimil
//
//  Deskew angle detection and image correction for scanned PDFs.
//  Session: S045 (2026-02-19)
//
//  Detection: Vision.framework VNDetectHorizonRequest (lightweight, no neural engine)
//  Correction: Core Image CIAffineTransform + auto-crop
//
//  Usage:
//    let angle = DeskewDetector.detectAngle(from: image)
//    let corrected = DeskewDetector.applyCorrection(to: image, angle: angle)
//

import Foundation
import AppKit
import Vision
import CoreImage
import os

// MARK: - DeskewDetector

enum DeskewDetector {
    
    // MARK: Configuration
    
    /// Maximum correctable angle in radians (~8.6°)
    /// Beyond this, it's likely a rotated scan (90°/180°), not tilt
    static let maximumAngle: CGFloat = 0.15
    
    /// Angles below this threshold are treated as zero (not worth correcting)
    static let negligibleAngle: CGFloat = 0.001  // ~0.06°
    
    // MARK: - Detection
    
    /// Detect tilt angle from dominant horizontal features in an image.
    ///
    /// Uses VNDetectHorizonRequest — a lightweight geometric analysis that detects
    /// the dominant horizon/baseline angle. No neural engine involved.
    /// Call from a background thread.
    ///
    /// - Parameter image: Source image (typically a rendered PDF page)
    /// - Returns: Detected angle in radians, or `nil` if detection failed or angle is negligible
    static func detectAngle(from image: NSImage) -> CGFloat? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Logger.deskew.error("detectAngle: failed to get CGImage")
            return nil
        }
        
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            Logger.deskew.error("VNDetectHorizonRequest failed: \(error.localizedDescription)")
            return nil
        }
        
        guard let observation = request.results?.first as? VNHorizonObservation else {
            Logger.deskew.debug("No horizon detected")
            return nil
        }
        
        let angle = observation.angle
        
        // Reject if outside correctable range
        guard abs(angle) <= maximumAngle else {
            Logger.deskew.debug("Angle too large: \(angle * 180 / CGFloat.pi, privacy: .public)° — skipping")
            return nil
        }
        
        // Reject negligible angles
        guard abs(angle) > negligibleAngle else {
            Logger.deskew.debug("Angle negligible: \(angle * 180 / CGFloat.pi, privacy: .public)° — skipping")
            return nil
        }
        
        Logger.deskew.info("Detected horizon: \(angle * 180 / CGFloat.pi, privacy: .public)°")
        return angle
    }
    
    // MARK: - Correction
    
    /// Apply deskew rotation to an image with auto-crop to remove black triangles.
    ///
    /// Uses CIAffineTransform for GPU-accelerated rotation, then crops the result
    /// to the largest inscribed axis-aligned rectangle.
    ///
    /// - Parameters:
    ///   - image: Source image
    ///   - angle: Tilt angle in radians (as returned by `detectAngle`)
    /// - Returns: Corrected image, or `nil` if processing failed
    static func applyCorrection(to image: NSImage, angle: CGFloat) -> NSImage? {
        guard abs(angle) > negligibleAngle else {
            return image  // No correction needed
        }
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Logger.deskew.error("applyCorrection: failed to get CGImage")
            return nil
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        let originalWidth = ciImage.extent.width
        let originalHeight = ciImage.extent.height
        
        // VNDetectHorizonRequest.angle returns the tilt from horizontal;
        // applying it directly as rotation corrects the tilt
        let correctionAngle = angle
        let rotated = ciImage.transformed(by: CGAffineTransform(rotationAngle: correctionAngle))
        
        // Auto-crop: calculate largest inscribed rectangle
        let absSin = abs(sin(correctionAngle))
        let absCos = abs(cos(correctionAngle))
        
        // Precise inscribed rectangle for rotated image
        let cropWidth = originalWidth * absCos - originalHeight * absSin
        let cropHeight = originalHeight * absCos - originalWidth * absSin
        
        // If crop dimensions are invalid (extreme angle), fall back to simple inset
        let finalCropWidth: CGFloat
        let finalCropHeight: CGFloat
        if cropWidth > 0 && cropHeight > 0 {
            finalCropWidth = cropWidth
            finalCropHeight = cropHeight
        } else {
            let insetX = originalHeight * absSin
            let insetY = originalWidth * absSin
            finalCropWidth = originalWidth - insetX
            finalCropHeight = originalHeight - insetY
        }
        
        // Center the crop rect on the rotated image
        let rotatedExtent = rotated.extent
        let cropRect = CGRect(
            x: rotatedExtent.midX - finalCropWidth / 2,
            y: rotatedExtent.midY - finalCropHeight / 2,
            width: finalCropWidth,
            height: finalCropHeight
        )
        
        let cropped = rotated.cropped(to: cropRect)
        
        // Render to CGImage
        let context = CIContext(options: [.useSoftwareRenderer: false])  // GPU preferred
        guard let outputCG = context.createCGImage(cropped, from: cropped.extent) else {
            Logger.deskew.error("applyCorrection: CIContext.createCGImage failed")
            return nil
        }
        
        let result = NSImage(cgImage: outputCG, size: NSSize(
            width: outputCG.width,
            height: outputCG.height
        ))
        
        Logger.deskew.debug("Applied correction: \(angle * 180 / CGFloat.pi, privacy: .public)° crop=\(Int(finalCropWidth))x\(Int(finalCropHeight))")
        return result
    }
}
