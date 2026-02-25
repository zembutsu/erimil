//
//  MetadataExtractor.swift
//  Erimil
//
//  Metadata extraction for image inspector (#140)
//  Session: S058
//
//  Supports:
//  - JPEG: EXIF, TIFF, IPTC, GPS
//  - PNG: tEXt/iTXt chunks (AI generation parameters, etc.)
//  - PDF: document-level metadata (author, title, creation date)
//

import Foundation
import AppKit
import ImageIO
import PDFKit
import os

// MARK: - Data Model

/// A category of metadata (e.g., "EXIF", "GPS", "PNG")
struct MetadataSection: Identifiable {
    let id = UUID()
    let name: String
    let items: [MetadataItem]
}

/// A single metadata key-value pair
struct MetadataItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

// MARK: - Extractor

struct MetadataExtractor {
    
    private static let logger = Logger.metadata
    
    /// Extract metadata from the current image entry
    /// - Parameters:
    ///   - imageSource: The image source (archive, folder, or PDF)
    ///   - entry: The image entry to inspect
    /// - Returns: Array of metadata sections, empty if extraction fails
    static func extract(from imageSource: any ImageSource, entry: ImageEntry) -> [MetadataSection] {
        switch imageSource.sourceType {
        case .archive:
            return extractFromArchive(imageSource: imageSource, entry: entry)
        case .folder:
            return extractFromFolder(imageSource: imageSource, entry: entry)
        case .pdf:
            return extractFromPDF(imageSource: imageSource)
        }
    }
    
    // MARK: - Archive (ZIP)
    
    private static func extractFromArchive(imageSource: any ImageSource, entry: ImageEntry) -> [MetadataSection] {
        guard let archiveManager = imageSource as? ArchiveManager else {
            logger.error("Failed to cast imageSource to ArchiveManager")
            return []
        }
        guard let data = archiveManager.extractData(for: entry) else {
            logger.error("Failed to extract data for \(entry.name)")
            return []
        }
        return extractFromImageData(data, fileName: entry.name)
    }
    
    // MARK: - Folder
    
    private static func extractFromFolder(imageSource: any ImageSource, entry: ImageEntry) -> [MetadataSection] {
        let fileURL = URL(fileURLWithPath: entry.path)
        
        // Use Data-based extraction (supports PNG tEXt/iTXt chunks)
        if let data = try? Data(contentsOf: fileURL) {
            return extractFromImageData(data, fileName: entry.name)
        }
        
        // Fallback: URL-based (no PNG text chunk support)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            logger.error("Failed to create CGImageSource for \(entry.name)")
            return []
        }
        
        var sections = extractFromCGImageSource(source, fileName: entry.name)
        
        // Prepend basic file info
        var fileItems: [MetadataItem] = [
            MetadataItem(key: "File Name", value: entry.name),
        ]
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64 {
            fileItems.append(MetadataItem(key: "File Size", value: formatFileSize(size)))
        }
        if let uti = CGImageSourceGetType(source) as? String {
            fileItems.append(MetadataItem(key: "Format", value: uti))
        }
        sections.insert(MetadataSection(name: "File", items: fileItems), at: 0)
        
        return sections
    }
    
    // MARK: - PDF
    
    private static func extractFromPDF(imageSource: any ImageSource) -> [MetadataSection] {
        guard let document = PDFDocument(url: imageSource.url) else {
            logger.error("Failed to open PDF: \(imageSource.url.lastPathComponent)")
            return []
        }
        
        var items: [MetadataItem] = []
        
        if let attributes = document.documentAttributes {
            let keyMap: [(String, String)] = [
                (PDFDocumentAttribute.titleAttribute.rawValue, "Title"),
                (PDFDocumentAttribute.authorAttribute.rawValue, "Author"),
                (PDFDocumentAttribute.subjectAttribute.rawValue, "Subject"),
                (PDFDocumentAttribute.creatorAttribute.rawValue, "Creator"),
                (PDFDocumentAttribute.producerAttribute.rawValue, "Producer"),
                (PDFDocumentAttribute.creationDateAttribute.rawValue, "Creation Date"),
                (PDFDocumentAttribute.modificationDateAttribute.rawValue, "Modification Date"),
            ]
            
            for (attrKey, displayName) in keyMap {
                if let value = attributes[attrKey] {
                    let stringValue: String
                    if let date = value as? Date {
                        stringValue = ISO8601DateFormatter().string(from: date)
                    } else {
                        stringValue = "\(value)"
                    }
                    if !stringValue.isEmpty {
                        items.append(MetadataItem(key: displayName, value: stringValue))
                    }
                }
            }
        }
        
        // Page count as metadata
        items.append(MetadataItem(key: "Page Count", value: "\(document.pageCount)"))
        
        // File size
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: imageSource.url.path)[.size] as? Int64 {
            items.append(MetadataItem(key: "File Size", value: formatFileSize(fileSize)))
        }
        
        guard !items.isEmpty else { return [] }
        return [MetadataSection(name: "PDF Document", items: items)]
    }
    
    // MARK: - CGImageSource Processing
    
    private static func extractFromImageData(_ data: Data, fileName: String) -> [MetadataSection] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            logger.error("Failed to create CGImageSource from data for \(fileName)")
            return []
        }
        
        var sections = extractFromCGImageSource(source, fileName: fileName)
        
        // Build file info section
        var fileItems: [MetadataItem] = [
            MetadataItem(key: "File Name", value: fileName),
            MetadataItem(key: "File Size", value: formatFileSize(Int64(data.count))),
        ]
        
        // Image dimensions from CGImageSource
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                fileItems.append(MetadataItem(key: "Dimensions", value: "\(width) × \(height)"))
            }
            if let colorModel = properties[kCGImagePropertyColorModel] as? String {
                fileItems.append(MetadataItem(key: "Color Model", value: colorModel))
            }
            if let depth = properties[kCGImagePropertyDepth] as? Int {
                fileItems.append(MetadataItem(key: "Bit Depth", value: "\(depth)"))
            }
            if let dpiWidth = properties[kCGImagePropertyDPIWidth] as? Double,
               let dpiHeight = properties[kCGImagePropertyDPIHeight] as? Double {
                if dpiWidth == dpiHeight {
                    fileItems.append(MetadataItem(key: "DPI", value: "\(Int(dpiWidth))"))
                } else {
                    fileItems.append(MetadataItem(key: "DPI", value: "\(Int(dpiWidth)) × \(Int(dpiHeight))"))
                }
            }
        }
        
        // UTI / format type
        if let uti = CGImageSourceGetType(source) as? String {
            fileItems.append(MetadataItem(key: "Format", value: uti))
        }
        
        // PNG: parse tEXt/iTXt chunks directly from binary
        // CGImageSource does NOT expose custom tEXt chunks (e.g., A1111 "parameters")
        let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        if data.count > 8 && data.prefix(8).elementsEqual(pngSignature) {
            let textChunks = extractPNGTextChunks(from: data)
            if !textChunks.isEmpty {
                sections.append(MetadataSection(name: "PNG Text Chunks", items: textChunks))
            }
        }
        
        sections.insert(MetadataSection(name: "File", items: fileItems), at: 0)
        return sections
    }
    
    private static func extractFromCGImageSource(_ source: CGImageSource, fileName: String) -> [MetadataSection] {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            logger.debug("No properties found for \(fileName)")
            return []
        }
        
        var sections: [MetadataSection] = []
        
        // EXIF
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            sections.append(buildSection(name: "EXIF", from: exif, keyMap: exifKeyMap))
        }
        
        // TIFF
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            sections.append(buildSection(name: "TIFF", from: tiff, keyMap: tiffKeyMap))
        }
        
        // IPTC
        if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            sections.append(buildSection(name: "IPTC", from: iptc, keyMap: nil))
        }
        
        // GPS
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            sections.append(buildGPSSection(from: gps))
        }
        
        // PNG (standard PNG metadata from CGImageSource)
        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            sections.append(buildSection(name: "PNG", from: png, keyMap: nil))
        }
        
        // JFIF
        if let jfif = properties[kCGImagePropertyJFIFDictionary] as? [CFString: Any] {
            sections.append(buildSection(name: "JFIF", from: jfif, keyMap: nil))
        }
        
        return sections
    }
    
    // MARK: - PNG tEXt/iTXt Chunk Parser
    
    /// Parse PNG tEXt and iTXt chunks directly from binary data.
    /// CGImageSource does not expose custom tEXt chunks (e.g., A1111 "parameters",
    /// ComfyUI workflow data, NovelAI metadata, etc.)
    private static func extractPNGTextChunks(from data: Data) -> [MetadataItem] {
        var items: [MetadataItem] = []
        var offset = 8  // Skip PNG signature
        
        while offset + 12 <= data.count {
            // Chunk structure: 4 bytes length (big-endian) + 4 bytes type + data + 4 bytes CRC
            let length = Int(data[offset]) << 24 | Int(data[offset+1]) << 16 | Int(data[offset+2]) << 8 | Int(data[offset+3])
            let typeData = data[offset+4..<offset+8]
            let typeString = String(bytes: typeData, encoding: .ascii) ?? ""
            
            let chunkDataStart = offset + 8
            let chunkDataEnd = chunkDataStart + length
            
            guard chunkDataEnd + 4 <= data.count else { break }
            
            if typeString == "tEXt" {
                // tEXt: keyword \0 text (Latin-1 encoded)
                let chunkData = data[chunkDataStart..<chunkDataEnd]
                if let nullIndex = chunkData.firstIndex(of: 0) {
                    let keyword = String(data: chunkData[chunkDataStart..<nullIndex], encoding: .isoLatin1) ?? ""
                    let textStart = chunkData.index(after: nullIndex)
                    let text = String(data: chunkData[textStart..<chunkDataEnd], encoding: .isoLatin1) ?? ""
                    if !keyword.isEmpty {
                        items.append(MetadataItem(key: keyword, value: text))
                    }
                }
            } else if typeString == "iTXt" {
                // iTXt: keyword \0 compressionFlag(1) compressionMethod(1) language \0 translatedKeyword \0 text
                let chunkData = data[chunkDataStart..<chunkDataEnd]
                if let nullIndex = chunkData.firstIndex(of: 0) {
                    let keyword = String(data: chunkData[chunkDataStart..<nullIndex], encoding: .utf8) ?? ""
                    // Skip: null + compressionFlag(1) + compressionMethod(1)
                    var pos = chunkData.index(after: nullIndex)
                    guard chunkData.distance(from: pos, to: chunkDataEnd) >= 2 else {
                        offset = chunkDataEnd + 4
                        continue
                    }
                    pos = chunkData.index(pos, offsetBy: 2)
                    // Skip language tag (null-terminated)
                    if let langNull = chunkData[pos..<chunkDataEnd].firstIndex(of: 0) {
                        pos = chunkData.index(after: langNull)
                        // Skip translated keyword (null-terminated)
                        if let transNull = chunkData[pos..<chunkDataEnd].firstIndex(of: 0) {
                            pos = chunkData.index(after: transNull)
                            let text = String(data: chunkData[pos..<chunkDataEnd], encoding: .utf8) ?? ""
                            if !keyword.isEmpty {
                                items.append(MetadataItem(key: keyword, value: text))
                            }
                        }
                    }
                }
            } else if typeString == "IEND" {
                break  // End of PNG, no more chunks
            }
            
            // Advance to next chunk
            offset = chunkDataEnd + 4
        }
        
        logger.debug("PNG text chunks found: \(items.count, privacy: .public)")
        return items
    }
    
    // MARK: - Section Builders
    
    private static func buildSection(
        name: String,
        from dict: [CFString: Any],
        keyMap: [CFString: String]?
    ) -> MetadataSection {
        var items: [MetadataItem] = []
        
        for (key, value) in dict.sorted(by: { ($0.key as String) < ($1.key as String) }) {
            let displayKey = keyMap?[key] ?? (key as String)
            let displayValue = formatValue(value)
            if !displayValue.isEmpty {
                items.append(MetadataItem(key: displayKey, value: displayValue))
            }
        }
        
        return MetadataSection(name: name, items: items)
    }
    
    private static func buildGPSSection(from gps: [CFString: Any]) -> MetadataSection {
        var items: [MetadataItem] = []
        
        // Try to build readable coordinates
        if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
           let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
            let latSign = latRef == "S" ? "-" : ""
            let lonSign = lonRef == "W" ? "-" : ""
            items.append(MetadataItem(
                key: "Coordinates",
                value: "\(latSign)\(String(format: "%.6f", lat)), \(lonSign)\(String(format: "%.6f", lon))"
            ))
        }
        
        if let alt = gps[kCGImagePropertyGPSAltitude] as? Double {
            items.append(MetadataItem(key: "Altitude", value: "\(String(format: "%.1f", alt)) m"))
        }
        
        if let timestamp = gps[kCGImagePropertyGPSTimeStamp] as? String {
            items.append(MetadataItem(key: "GPS Time", value: timestamp))
        }
        
        if let dateStamp = gps[kCGImagePropertyGPSDateStamp] as? String {
            items.append(MetadataItem(key: "GPS Date", value: dateStamp))
        }
        
        // Include remaining keys not already handled
        let handledKeys: Set<String> = [
            kCGImagePropertyGPSLatitude as String,
            kCGImagePropertyGPSLatitudeRef as String,
            kCGImagePropertyGPSLongitude as String,
            kCGImagePropertyGPSLongitudeRef as String,
            kCGImagePropertyGPSAltitude as String,
            kCGImagePropertyGPSTimeStamp as String,
            kCGImagePropertyGPSDateStamp as String,
        ]
        
        for (key, value) in gps.sorted(by: { ($0.key as String) < ($1.key as String) }) {
            if !handledKeys.contains(key as String) {
                items.append(MetadataItem(key: key as String, value: formatValue(value)))
            }
        }
        
        return MetadataSection(name: "GPS", items: items)
    }
    
    // MARK: - Formatting Helpers
    
    private static func formatValue(_ value: Any) -> String {
        switch value {
        case let array as [Any]:
            return array.map { "\($0)" }.joined(separator: ", ")
        case let data as Data:
            return "\(data.count) bytes"
        default:
            return "\(value)"
        }
    }
    
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Copy Helpers
    
    /// Format all sections as plain text for clipboard
    static func formatAsText(_ sections: [MetadataSection]) -> String {
        var lines: [String] = []
        for section in sections {
            lines.append("[\(section.name)]")
            for item in section.items {
                lines.append("  \(item.key): \(item.value)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Key Display Name Maps
    
    private static let exifKeyMap: [CFString: String] = [
        kCGImagePropertyExifExposureTime: "Exposure Time",
        kCGImagePropertyExifFNumber: "F Number",
        kCGImagePropertyExifISOSpeedRatings: "ISO",
        kCGImagePropertyExifDateTimeOriginal: "Date Original",
        kCGImagePropertyExifDateTimeDigitized: "Date Digitized",
        kCGImagePropertyExifShutterSpeedValue: "Shutter Speed",
        kCGImagePropertyExifApertureValue: "Aperture",
        kCGImagePropertyExifBrightnessValue: "Brightness",
        kCGImagePropertyExifExposureBiasValue: "Exposure Bias",
        kCGImagePropertyExifMeteringMode: "Metering Mode",
        kCGImagePropertyExifFlash: "Flash",
        kCGImagePropertyExifFocalLength: "Focal Length",
        kCGImagePropertyExifFocalLenIn35mmFilm: "Focal Length (35mm)",
        kCGImagePropertyExifColorSpace: "Color Space",
        kCGImagePropertyExifPixelXDimension: "Width",
        kCGImagePropertyExifPixelYDimension: "Height",
        kCGImagePropertyExifWhiteBalance: "White Balance",
        kCGImagePropertyExifLensModel: "Lens Model",
        kCGImagePropertyExifLensMake: "Lens Make",
        kCGImagePropertyExifBodySerialNumber: "Body Serial",
        kCGImagePropertyExifLensSerialNumber: "Lens Serial",
    ]
    
    private static let tiffKeyMap: [CFString: String] = [
        kCGImagePropertyTIFFMake: "Make",
        kCGImagePropertyTIFFModel: "Model",
        kCGImagePropertyTIFFSoftware: "Software",
        kCGImagePropertyTIFFDateTime: "Date/Time",
        kCGImagePropertyTIFFImageDescription: "Description",
        kCGImagePropertyTIFFArtist: "Artist",
        kCGImagePropertyTIFFCopyright: "Copyright",
        kCGImagePropertyTIFFOrientation: "Orientation",
        kCGImagePropertyTIFFXResolution: "X Resolution",
        kCGImagePropertyTIFFYResolution: "Y Resolution",
        kCGImagePropertyTIFFResolutionUnit: "Resolution Unit",
    ]
}
