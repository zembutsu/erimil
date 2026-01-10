//
//  ZIPEncodingDetector.swift
//  Erimil
//
//  ZIP file name encoding detection via direct header reading.
//  Detects UTF-8 vs Shift_JIS (CP932) for Japanese filenames.
//
//  ZIP Structure Reference:
//  - End of Central Directory Record (EOCD): signature 0x504B0506
//  - Central Directory File Header: signature 0x504B0102
//  - General Purpose Bit Flag bit 11 (EFS): indicates UTF-8 encoding
//

import Foundation

struct ZIPEncodingDetector {
    
    enum DetectedEncoding {
        case utf8
        case shiftJIS
        case unknown
        
        // MARK: - Future Extension Points
        // - GBK (Simplified Chinese): 0x81-0xFE range, overlaps with Shift_JIS
        // - EUC-KR (Korean): 0x81-0xFE range
        // - CP1252 (Western European): 0x80-0xFF single byte
        // - CP1251 (Cyrillic): 0x80-0xFF single byte
        //
        // For overlapping ranges (e.g., GBK vs Shift_JIS):
        // Consider using locale hints or statistical character frequency analysis.
    }
    
    // MARK: - ZIP Constants
    
    private static let eocdSignature: UInt32 = 0x06054B50  // little-endian: 50 4B 05 06
    private static let centralDirSignature: UInt32 = 0x02014B50  // little-endian: 50 4B 01 02
    private static let eocdMinSize = 22  // Minimum EOCD size (no comment)
    private static let eocdMaxSearchSize = 65557  // Max EOCD size (max comment = 65535)
    
    // MARK: - Public API
    
    /// Detect the file name encoding used in a ZIP archive.
    ///
    /// Reads ZIP headers directly without fully parsing the archive.
    /// Checks EFS flag (bit 11) first, then analyzes byte patterns.
    ///
    /// - Parameter url: URL to the ZIP file
    /// - Returns: Detected encoding type
    static func detect(for url: URL) -> DetectedEncoding {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            print("[ZIPEncodingDetector] Cannot open file: \(url.lastPathComponent)")
            return .unknown
        }
        defer { try? fileHandle.close() }
        
        // Step 1: Find EOCD and get Central Directory offset
        guard let (centralDirOffset, entryCount) = findCentralDirectory(fileHandle: fileHandle) else {
            print("[ZIPEncodingDetector] Cannot locate Central Directory")
            return .unknown
        }
        
        print("[ZIPEncodingDetector] Central Directory at offset \(centralDirOffset), \(entryCount) entries")
        
        // Step 2: Read first few entries from Central Directory
        let samplesToCheck = min(entryCount, 10)  // Check up to 10 entries
        guard let fileNameBytes = readFileNameBytes(
            fileHandle: fileHandle,
            centralDirOffset: centralDirOffset,
            maxEntries: samplesToCheck
        ) else {
            print("[ZIPEncodingDetector] Cannot read file names from Central Directory")
            return .unknown
        }
        
        // Step 3: Analyze byte patterns
        return analyzeEncoding(fileNameBytes: fileNameBytes)
    }
    
    // MARK: - Private Helpers
    
    /// Find End of Central Directory Record and extract Central Directory location
    private static func findCentralDirectory(fileHandle: FileHandle) -> (offset: UInt64, count: Int)? {
        // Get file size
        guard let fileSize = try? fileHandle.seekToEnd() else { return nil }
        guard fileSize >= eocdMinSize else { return nil }
        
        // Search backwards for EOCD signature
        let searchSize = min(UInt64(eocdMaxSearchSize), fileSize)
        let searchStart = fileSize - searchSize
        
        try? fileHandle.seek(toOffset: searchStart)
        guard let searchData = try? fileHandle.read(upToCount: Int(searchSize)) else { return nil }
        
        // Find EOCD signature (search from end)
        var eocdOffset: Int?
        for i in stride(from: searchData.count - eocdMinSize, through: 0, by: -1) {
            let sig = searchData.subdata(in: i..<(i+4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            if sig == eocdSignature {
                eocdOffset = i
                break
            }
        }
        
        guard let offset = eocdOffset else { return nil }
        
        // Parse EOCD
        // Offset 8-9: number of entries in central directory (this disk)
        // Offset 16-19: offset of central directory
        let entryCountOffset = offset + 10
        let centralDirOffsetPos = offset + 16
        
        guard centralDirOffsetPos + 4 <= searchData.count else { return nil }
        
        let entryCount = searchData.subdata(in: entryCountOffset..<(entryCountOffset+2))
            .withUnsafeBytes { $0.load(as: UInt16.self) }
        let centralDirOffset = searchData.subdata(in: centralDirOffsetPos..<(centralDirOffsetPos+4))
            .withUnsafeBytes { $0.load(as: UInt32.self) }
        
        return (UInt64(centralDirOffset), Int(entryCount))
    }
    
    /// Read file name bytes from Central Directory entries
    private static func readFileNameBytes(
        fileHandle: FileHandle,
        centralDirOffset: UInt64,
        maxEntries: Int
    ) -> [(bytes: Data, hasEFS: Bool)]? {
        try? fileHandle.seek(toOffset: centralDirOffset)
        
        var results: [(bytes: Data, hasEFS: Bool)] = []
        
        for _ in 0..<maxEntries {
            // Read Central Directory File Header (fixed part: 46 bytes)
            guard let headerData = try? fileHandle.read(upToCount: 46) else { break }
            guard headerData.count == 46 else { break }
            
            // Verify signature
            let sig = headerData.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
            guard sig == centralDirSignature else { break }
            
            // General Purpose Bit Flag (offset 8-9)
            let bitFlag = headerData.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }
            let hasEFS = (bitFlag & 0x0800) != 0  // Bit 11
            
            // File name length (offset 28-29)
            let fileNameLength = headerData.subdata(in: 28..<30).withUnsafeBytes { $0.load(as: UInt16.self) }
            
            // Extra field length (offset 30-31)
            let extraFieldLength = headerData.subdata(in: 30..<32).withUnsafeBytes { $0.load(as: UInt16.self) }
            
            // File comment length (offset 32-33)
            let commentLength = headerData.subdata(in: 32..<34).withUnsafeBytes { $0.load(as: UInt16.self) }
            
            // Read file name
            if fileNameLength > 0 {
                guard let fileNameData = try? fileHandle.read(upToCount: Int(fileNameLength)) else { break }
                guard fileNameData.count == Int(fileNameLength) else { break }
                results.append((bytes: fileNameData, hasEFS: hasEFS))
            }
            
            // Skip extra field and comment to reach next entry
            let skipSize = Int(extraFieldLength) + Int(commentLength)
            if skipSize > 0 {
                guard let currentPos = try? fileHandle.offset() else { break }
                try? fileHandle.seek(toOffset: currentPos + UInt64(skipSize))
            }
        }
        
        return results.isEmpty ? nil : results
    }
    
    /// Analyze file name bytes to determine encoding
    private static func analyzeEncoding(fileNameBytes: [(bytes: Data, hasEFS: Bool)]) -> DetectedEncoding {
        // If any entry has EFS flag set, it's UTF-8
        if fileNameBytes.contains(where: { $0.hasEFS }) {
            print("[ZIPEncodingDetector] EFS flag detected → UTF-8")
            return .utf8
        }
        
        // Analyze byte patterns
        var hasHighBytes = false
        var looksLikeShiftJIS = false
        var looksLikeUTF8 = false
        
        for (bytes, _) in fileNameBytes {
            let analysis = analyzeBytePattern(bytes)
            if analysis.hasHighBytes {
                hasHighBytes = true
            }
            if analysis.isValidShiftJIS {
                looksLikeShiftJIS = true
            }
            if analysis.isValidUTF8 {
                looksLikeUTF8 = true
            }
        }
        
        // Decision logic
        if !hasHighBytes {
            // Pure ASCII - either encoding works
            print("[ZIPEncodingDetector] ASCII only → UTF-8 (default)")
            return .utf8
        }
        
        if looksLikeUTF8 && !looksLikeShiftJIS {
            print("[ZIPEncodingDetector] Byte pattern → UTF-8")
            return .utf8
        }
        
        if looksLikeShiftJIS && !looksLikeUTF8 {
            print("[ZIPEncodingDetector] Byte pattern → Shift_JIS")
            return .shiftJIS
        }
        
        // Ambiguous case: prefer UTF-8 (modern default)
        // Modern macOS/Linux ZIPs use UTF-8 without EFS flag
        // Shift_JIS is primarily for legacy Windows archives
        // Future: could use statistical frequency analysis for better detection
        if looksLikeUTF8 {
            print("[ZIPEncodingDetector] Ambiguous, defaulting to UTF-8 (modern default)")
            return .utf8
        }
        
        print("[ZIPEncodingDetector] Cannot determine encoding → unknown")
        return .unknown
    }
    
    /// Analyze byte pattern of a single file name
    private static func analyzeBytePattern(_ data: Data) -> (hasHighBytes: Bool, isValidUTF8: Bool, isValidShiftJIS: Bool) {
        var hasHighBytes = false
        var isValidUTF8 = true
        var isValidShiftJIS = true
        
        let bytes = Array(data)
        var i = 0
        
        // Check for high bytes (non-ASCII)
        for byte in bytes {
            if byte > 0x7F {
                hasHighBytes = true
                break
            }
        }
        
        if !hasHighBytes {
            return (false, true, true)  // Pure ASCII
        }
        
        // Validate as UTF-8
        i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte <= 0x7F {
                i += 1
            } else if byte >= 0xC2 && byte <= 0xDF {
                // 2-byte sequence
                if i + 1 >= bytes.count || bytes[i+1] < 0x80 || bytes[i+1] > 0xBF {
                    isValidUTF8 = false
                    break
                }
                i += 2
            } else if byte >= 0xE0 && byte <= 0xEF {
                // 3-byte sequence (common for Japanese UTF-8)
                if i + 2 >= bytes.count {
                    isValidUTF8 = false
                    break
                }
                if bytes[i+1] < 0x80 || bytes[i+1] > 0xBF || bytes[i+2] < 0x80 || bytes[i+2] > 0xBF {
                    isValidUTF8 = false
                    break
                }
                i += 3
            } else if byte >= 0xF0 && byte <= 0xF4 {
                // 4-byte sequence
                if i + 3 >= bytes.count {
                    isValidUTF8 = false
                    break
                }
                if bytes[i+1] < 0x80 || bytes[i+1] > 0xBF ||
                   bytes[i+2] < 0x80 || bytes[i+2] > 0xBF ||
                   bytes[i+3] < 0x80 || bytes[i+3] > 0xBF {
                    isValidUTF8 = false
                    break
                }
                i += 4
            } else {
                isValidUTF8 = false
                break
            }
        }
        
        // Validate as Shift_JIS
        // Shift_JIS lead byte ranges: 0x81-0x9F, 0xE0-0xFC
        // Trail byte ranges: 0x40-0x7E, 0x80-0xFC
        i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte <= 0x7F {
                // ASCII or single-byte Katakana (0xA1-0xDF)
                i += 1
            } else if byte >= 0xA1 && byte <= 0xDF {
                // Half-width Katakana (single byte)
                i += 1
            } else if (byte >= 0x81 && byte <= 0x9F) || (byte >= 0xE0 && byte <= 0xFC) {
                // Double-byte lead byte
                if i + 1 >= bytes.count {
                    isValidShiftJIS = false
                    break
                }
                let trail = bytes[i+1]
                if (trail >= 0x40 && trail <= 0x7E) || (trail >= 0x80 && trail <= 0xFC) {
                    i += 2
                } else {
                    isValidShiftJIS = false
                    break
                }
            } else {
                isValidShiftJIS = false
                break
            }
        }
        
        return (hasHighBytes, isValidUTF8, isValidShiftJIS)
    }
}
