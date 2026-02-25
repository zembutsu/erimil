import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.erimil.app"

    static let appSettings   = Logger(subsystem: subsystem, category: "AppSettings")
    static let archive       = Logger(subsystem: subsystem, category: "ArchiveManager")
    static let cache         = Logger(subsystem: subsystem, category: "CacheManager")
    static let bookmark      = Logger(subsystem: subsystem, category: "Bookmark")
    static let sidebar       = Logger(subsystem: subsystem, category: "SidebarView")
    static let content       = Logger(subsystem: subsystem, category: "ContentView")
    static let thumbnailGrid = Logger(subsystem: subsystem, category: "ThumbnailGrid")
    static let slideWindow   = Logger(subsystem: subsystem, category: "SlideWindow")
    static let sourceNav     = Logger(subsystem: subsystem, category: "SourceNavigator")
    static let pdf           = Logger(subsystem: subsystem, category: "PDFManager")
    static let prefetcher    = Logger(subsystem: subsystem, category: "Prefetcher")
    static let folder        = Logger(subsystem: subsystem, category: "FolderManager")
    static let zipEncoding   = Logger(subsystem: subsystem, category: "ZIPEncoding")
    static let preview       = Logger(subsystem: subsystem, category: "ImagePreview")
    static let viewer        = Logger(subsystem: subsystem, category: "Viewer")
    static let spread        = Logger(subsystem: subsystem, category: "SpreadViewer")
    static let keyHandling   = Logger(subsystem: subsystem, category: "KeyHandling")
    static let deskew        = Logger(subsystem: subsystem, category: "Deskew")        // #101
    static let metadata      = Logger(subsystem: subsystem, category: "Metadata")   // #140
}
