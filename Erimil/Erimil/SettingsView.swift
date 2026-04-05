//
//  SettingsView.swift
//  Erimil
//
//  Settings panel UI (accessible via Erimil > Settings or ⌘,)
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var cacheInfo: (fileCount: Int, totalSize: Int64) = (0, 0)
    @AppStorage("thumbnailQualityPreset") private var thumbnailQualityRaw: String = ThumbnailQualityPreset.standard.rawValue
    
    var body: some View {
        Form {
            // MARK: - Thumbnail Size
            Section {
                Picker(String(localized: "settings.thumbnailSize.preset", defaultValue: "Preset"), selection: $settings.thumbnailSizePreset) {
                    ForEach(ThumbnailSizePreset.allCases, id: \.self) { preset in
                        if preset == .custom {
                            Text(preset.displayName).tag(preset)
                        } else {
                            Text("\(preset.displayName) (\(Int(preset.size))px)").tag(preset)
                        }
                    }
                }
                .pickerStyle(.radioGroup)
                
                if settings.thumbnailSizePreset == .custom {
                    HStack {
                        Text(String(localized: "settings.thumbnailSize.sizeLabel", defaultValue: "Size:"))
                        Slider(value: $settings.thumbnailSize, in: 60...300, step: 10)
                        Text("\(Int(settings.thumbnailSize))px")
                            .frame(width: 50, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text(String(localized: "settings.thumbnailSize.header", defaultValue: "Thumbnail Size"))
            } footer: {
                Text(String(localized: "settings.thumbnailSize.footer", defaultValue: "Applied when you next open a source. Retina displays automatically generate higher resolution thumbnails."))
                    .font(.caption)
            }
            
            // MARK: - Grid Spacing (#212)
            Section {
                HStack {
                    Text(String(localized: "settings.gridSpacing.spacingLabel", defaultValue: "Spacing:"))
                    Slider(value: $settings.gridSpacing, in: 0...24, step: 2)
                    Text("\(Int(settings.gridSpacing))px")
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                }
            } header: {
                Text(String(localized: "settings.gridSpacing.header", defaultValue: "Grid Spacing"))
            } footer: {
                Text(String(localized: "settings.gridSpacing.footer", defaultValue: "Space between thumbnails. Applied immediately."))
                    .font(.caption)
            }
            
            // MARK: - Thumbnail Quality (#207, #224)
            Section {
                Picker(String(localized: "settings.thumbnailQuality.preset", defaultValue: "Quality Preset"), selection: Binding(
                    get: { ThumbnailQualityPreset(rawValue: thumbnailQualityRaw) ?? .standard },
                    set: { thumbnailQualityRaw = $0.rawValue }
                )) {
                    ForEach(ThumbnailQualityPreset.allCases, id: \.self) { preset in
                        if preset.isPNG {
                            Text(preset.displayName)
                                .tag(preset)
                        } else {
                            Text("\(preset.displayName) (JPEG \(String(format: "%.0f%%", preset.compressionQuality * 100)))")
                                .tag(preset)
                        }
                    }
                }
                .pickerStyle(.radioGroup)
                
                Picker(String(localized: "settings.thumbnailQuality.prefetchPageLimit", defaultValue: "PDF Prefetch Limit"), selection: $settings.prefetchPageLimit) {
                    Text(String(localized: "settings.thumbnailQuality.pages100", defaultValue: "100 pages")).tag(100)
                    Text(String(localized: "settings.thumbnailQuality.pages250", defaultValue: "250 pages")).tag(250)
                    Text(String(localized: "settings.thumbnailQuality.pages500", defaultValue: "500 pages")).tag(500)
                    Text(String(localized: "settings.thumbnailQuality.pages1000", defaultValue: "1000 pages")).tag(1000)
                    Text(String(localized: "settings.thumbnailQuality.unlimited", defaultValue: "Unlimited")).tag(0)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(String(localized: "settings.thumbnailQuality.header", defaultValue: "Thumbnail Quality"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.thumbnailQuality.footer1", defaultValue: "Applied when you next open a source."))
                    Text(String(localized: "settings.thumbnailQuality.footer2", defaultValue: "PNG (lossless) provides higher quality but increases TileSheet disk usage."))
                    Text(String(localized: "settings.thumbnailQuality.footer3", defaultValue: "PDF prefetch limit: restricts TileSheet generation page count for large PDFs."))
                }
                .font(.caption)
            }
            
            // MARK: - Cache Management
            Section {
                HStack {
                    Text(String(localized: "settings.cache.fileCountLabel", defaultValue: "Cache files:"))
                    Spacer()
                    Text("\(cacheInfo.fileCount) \(String(localized: "settings.cache.filesUnit", defaultValue: "files"))")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text(String(localized: "settings.cache.sizeLabel", defaultValue: "Cache size:"))
                    Spacer()
                    Text(formatBytes(cacheInfo.totalSize))
                        .foregroundStyle(.secondary)
                }
                
                Button(String(localized: "settings.cache.clearButton", defaultValue: "Clear Cache")) {
                    CacheManager.shared.clearAllCache()
                    updateCacheInfo()
                }
                .foregroundStyle(.orange)
            } header: {
                Text(String(localized: "settings.cache.header", defaultValue: "Cache"))
            } footer: {
                Text(String(localized: "settings.cache.footer", defaultValue: "Deletes thumbnail cache. Favorites are preserved."))
                    .font(.caption)
            }
            
            // MARK: - Selection Mode
            Section {
                Picker(String(localized: "settings.selectionMode.picker", defaultValue: "Selection Mode"), selection: $settings.selectionMode) {
                    ForEach(SelectionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text(settings.selectionMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "settings.selectionMode.header", defaultValue: "Selection Mode"))
            }
            
            // MARK: - Viewer Thumbnail Position
            Section {
                Picker(String(localized: "settings.viewerMode.thumbnailPosition", defaultValue: "Thumbnail Position"), selection: $settings.viewerThumbnailPosition) {
                    ForEach(ViewerThumbnailPosition.allCases, id: \.self) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.radioGroup)
                Stepper(
                    "\(String(localized: "settings.viewerMode.prefetchCountLabel", defaultValue: "Prefetch Count")): \(settings.prefetchCount)",
                    value: $settings.prefetchCount,
                    in: 0...10
                )
                Toggle(String(localized: "settings.viewerMode.loopNavigation", defaultValue: "Loop Navigation Within Source"), isOn: $settings.loopWithinSource)
                Stepper(
                    "\(String(localized: "settings.viewerMode.nStepLabel", defaultValue: "N-step Jump Width")): \(settings.navigationStepCount)",
                    value: $settings.navigationStepCount,
                    in: 2...50
                )
            } header: {
                Text(String(localized: "settings.viewerMode.header", defaultValue: "Viewer Mode"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.viewerMode.footer1", defaultValue: "Thumbnail position can also be toggled with T key"))
                    Text(String(localized: "settings.viewerMode.footer2", defaultValue: "Prefetch: 0=disabled, higher values are smoother but use more memory"))
                    Text(String(localized: "settings.viewerMode.footer3", defaultValue: "Loop: navigate from last→first, first→last"))
                    Text(String(localized: "settings.viewerMode.footer4", defaultValue: "N-step: jump distance with Ctrl+Option+arrow keys"))
                }
                .font(.caption)
            }

            // MARK: - Auto-Slide (#172)
            Section {
                HStack {
                    Text("Normal:")
                        .frame(width: 55, alignment: .leading)
                    Slider(value: $settings.autoSlideIntervalNormal, in: 1.0...10.0, step: 0.5)
                    Text(String(format: "%.1fs", settings.autoSlideIntervalNormal))
                        .frame(width: 45, alignment: .trailing)
                        .monospacedDigit()
                }
                HStack {
                    Text("Fast:")
                        .frame(width: 55, alignment: .leading)
                    Slider(value: $settings.autoSlideIntervalFast, in: 0.1...2.0, step: 0.1)
                    Text(String(format: "%.1fs", settings.autoSlideIntervalFast))
                        .frame(width: 45, alignment: .trailing)
                        .monospacedDigit()
                }
                HStack {
                    Text("Turbo:")
                        .frame(width: 55, alignment: .leading)
                    Slider(value: $settings.autoSlideIntervalTurbo, in: 0.1...3.0, step: 0.1)
                    Text(String(format: "%.1fs", settings.autoSlideIntervalTurbo))
                        .frame(width: 45, alignment: .trailing)
                        .monospacedDigit()
                }
                Toggle(String(localized: "settings.autoSlide.loopAtEnd", defaultValue: "Loop at End"), isOn: $settings.autoSlideLoops)
                HStack {
                    Spacer()
                    Button(String(localized: "settings.autoSlide.resetButton", defaultValue: "Reset to Defaults")) {
                        settings.autoSlideIntervalNormal = 5.0
                        settings.autoSlideIntervalFast   = 0.5
                        settings.autoSlideIntervalTurbo  = 1.5
                        settings.autoSlideLoops          = true
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Auto-Slide")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.autoSlide.footer1", defaultValue: "Space×1=Normal, Space×2=Fast, Space×3=Turbo"))
                    Text(String(localized: "settings.autoSlide.footer2", defaultValue: "Press Space again to stop. O key toggles overlay"))
                    Text(String(localized: "settings.autoSlide.footer3", defaultValue: "Auto-stops at end when Loop at End is OFF"))
                }
                .font(.caption)
            }
            
            // MARK: - Reading Direction (#54)
            Section {
                Picker(String(localized: "settings.readingDirection.defaultDirection", defaultValue: "Default Direction"), selection: $settings.defaultReadingDirection) {
                    ForEach(ReadingDirection.allCases, id: \.self) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(String(localized: "settings.readingDirection.header", defaultValue: "Reading Direction"))
            } footer: {
                Text(String(localized: "settings.readingDirection.footer", defaultValue: "Default when opening a new source. Toggle per source with Ctrl+R"))
                    .font(.caption)
            }
            
            // MARK: - Spread Mode (#55)
            Section {
                Toggle(String(localized: "settings.spreadMode.toggle", defaultValue: "Spread View"), isOn: $settings.isSpreadModeEnabled)
                
                if settings.isSpreadModeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "settings.spreadMode.thresholdLabel", defaultValue: "Landscape Detection Threshold:"))
                            Spacer()
                            Text(String(format: "%.1f", settings.spreadThreshold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.spreadThreshold, in: 1.0...2.0, step: 0.1)
                        Text(String(localized: "settings.spreadMode.thresholdDescription", defaultValue: "Images with width/height > threshold are displayed as single pages"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "settings.spreadMode.header", defaultValue: "Spread Mode"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.spreadMode.footer1", defaultValue: "Press V to mark specific pages as single-page display"))
                    Text(String(localized: "settings.spreadMode.footer2", defaultValue: "Landscape images (spread scans) are automatically detected"))
                }
                .font(.caption)
            }
            
            // MARK: - Metadata Carry-Over (#105)
            Section {
                Toggle(String(localized: "settings.metadataCarryOver.favorites", defaultValue: "★ Favorites"), isOn: $settings.metadataCarryOverFavorites)
                Toggle(String(localized: "settings.metadataCarryOver.bookmarks", defaultValue: "🔖 Bookmarks"), isOn: $settings.metadataCarryOverBookmarks)
                Toggle(String(localized: "settings.metadataCarryOver.readingDirection", defaultValue: "Reading Direction"), isOn: $settings.metadataCarryOverDirection)
                Toggle(String(localized: "settings.metadataCarryOver.singlePageMarkers", defaultValue: "Single-Page Markers"), isOn: $settings.metadataCarryOverMarkers)
            } header: {
                Text(String(localized: "settings.metadataCarryOver.header", defaultValue: "Metadata Carry-Over on Export"))
            } footer: {
                Text(String(localized: "settings.metadataCarryOver.footer", defaultValue: "Types of metadata to copy to the export destination"))
                    .font(.caption)
            }
            
            // MARK: - Output Folder
            Section {
                Toggle(String(localized: "settings.outputFolder.useDefault", defaultValue: "Use Default Output Folder"), isOn: $settings.useDefaultOutputFolder)
                
                if settings.useDefaultOutputFolder {
                    HStack {
                        if let folder = settings.defaultOutputFolder {
                            Text(folder.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "settings.outputFolder.notSet", defaultValue: "Not Set"))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(String(localized: "settings.outputFolder.selectButton", defaultValue: "Choose...")) {
                            selectOutputFolder()
                        }
                    }
                }
            } header: {
                Text(String(localized: "settings.outputFolder.header", defaultValue: "Output Folder"))
            } footer: {
                Text(String(localized: "settings.outputFolder.footer", defaultValue: "When off, files are saved to the same folder as the original"))
                    .font(.caption)
            }
            
            // MARK: - Reset
            Section {
                Button(String(localized: "settings.reset.button", defaultValue: "Reset Settings")) {
                    settings.resetToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 1150)
        .navigationTitle(String(localized: "settings.title", defaultValue: "Settings"))
        .onAppear {
            updateCacheInfo()
        }
    }
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "settings.outputFolder.panelTitle", defaultValue: "Choose Default Output Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            settings.defaultOutputFolder = panel.url
        }
    }
    
    private func updateCacheInfo() {
        cacheInfo = CacheManager.shared.getCacheInfo()
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    SettingsView()
}
