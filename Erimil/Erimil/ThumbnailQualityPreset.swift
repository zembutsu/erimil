//
//  ThumbnailQualityPreset.swift
//  Erimil
//
//  #207: Thumbnail quality presets for tile sheet generation
//  Defines Low/Standard/High quality levels with corresponding
//  tile size and JPEG compression quality parameters.
//
//  Session: S086
//

import Foundation

enum ThumbnailQualityPreset: String, Codable, CaseIterable {
    case low
    case standard
    case high

    var tileSize: Int {
        switch self {
        case .low:      return 80
        case .standard: return 120
        case .high:     return 180
        }
    }

    var compressionQuality: CGFloat {
        switch self {
        case .low:      return 0.4
        case .standard: return 0.6
        case .high:     return 0.8
        }
    }

    var maxThumbnailSize: CGFloat {
        CGFloat(tileSize)
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
