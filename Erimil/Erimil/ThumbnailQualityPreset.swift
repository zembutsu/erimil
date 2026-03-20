//
//  ThumbnailQualityPreset.swift
//  Erimil
//
//  #207: Thumbnail quality presets — JPEG compression quality only.
//  Tile size is determined by ThumbnailSizePreset in AppSettings.
//
//  Session: S086
//

import Foundation

enum ThumbnailQualityPreset: String, Codable, CaseIterable {
    case low
    case standard
    case high
    case maximum

    var compressionQuality: CGFloat {
        switch self {
        case .low:      return 0.4
        case .standard: return 0.6
        case .high:     return 0.8
        case .maximum:  return 0.95
        }
    }

    var displayName: String {
        switch self {
        case .low:      return "低画質"
        case .standard: return "標準"
        case .high:     return "高画質"
        case .maximum:  return "最高画質"
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
