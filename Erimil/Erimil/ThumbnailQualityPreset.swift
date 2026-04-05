//
//  ThumbnailQualityPreset.swift
//  Erimil
//
//  #207: Thumbnail quality presets — JPEG compression quality only.
//  #224: Added PNG lossless preset.
//  Tile size is determined by ThumbnailSizePreset in AppSettings.
//
//  Session: S086, S099
//

import Foundation

enum ThumbnailQualityPreset: String, Codable, CaseIterable {
    case low
    case standard
    case high
    case maximum
    case pngLossless

    var compressionQuality: CGFloat {
        switch self {
        case .low:         return 0.4
        case .standard:    return 0.6
        case .high:        return 0.8
        case .maximum:     return 0.95
        case .pngLossless: return 1.0
        }
    }

    /// Whether this preset uses PNG encoding (lossless) instead of JPEG.
    var isPNG: Bool {
        self == .pngLossless
    }

    /// Image format identifier for TileSheet metadata.
    var imageFormat: String {
        isPNG ? "png" : "jpeg"
    }

    var displayName: String {
        switch self {
        case .low:         return String(localized: "thumbnailQuality.low.displayName",
                                         defaultValue: "Low")
        case .standard:    return String(localized: "thumbnailQuality.standard.displayName",
                                         defaultValue: "Standard")
        case .high:        return String(localized: "thumbnailQuality.high.displayName",
                                         defaultValue: "High")
        case .maximum:     return String(localized: "thumbnailQuality.maximum.displayName",
                                         defaultValue: "Maximum")
        case .pngLossless: return String(localized: "thumbnailQuality.pngLossless.displayName",
                                         defaultValue: "PNG (Lossless)")
        }
    }

    // MARK: - UserDefaults Storage

    private static let defaultsKey = "thumbnailQualityPreset"

    static var current: ThumbnailQualityPreset {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let preset = ThumbnailQualityPreset(rawValue: raw) else {
                return .standard
            }
            return preset
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}
