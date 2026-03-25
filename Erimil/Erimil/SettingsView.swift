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
                Picker("プリセット", selection: $settings.thumbnailSizePreset) {
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
                        Text("サイズ:")
                        Slider(value: $settings.thumbnailSize, in: 60...300, step: 10)
                        Text("\(Int(settings.thumbnailSize))px")
                            .frame(width: 50, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("サムネイルサイズ")
            } footer: {
                Text("次回ソースを開いた時に反映されます。Retinaディスプレイでは自動的に高解像度で生成されます。")
                    .font(.caption)
            }
            
            // MARK: - Grid Spacing (#212)
            Section {
                HStack {
                    Text("間隔:")
                    Slider(value: $settings.gridSpacing, in: 0...24, step: 2)
                    Text("\(Int(settings.gridSpacing))px")
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                }
            } header: {
                Text("グリッド間隔")
            } footer: {
                Text("サムネイル間の余白。即座に反映されます。")
                    .font(.caption)
            }
            
            // MARK: - Thumbnail Quality (#207, #224)
            Section {
                Picker("画質プリセット", selection: Binding(
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
                
                Picker("PDF先読み上限", selection: $settings.prefetchPageLimit) {
                    Text("100 ページ").tag(100)
                    Text("250 ページ").tag(250)
                    Text("500 ページ").tag(500)
                    Text("1000 ページ").tag(1000)
                    Text("無制限").tag(0)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("サムネイル画質")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("次回ソースを開いた時に反映されます。")
                    Text("PNG（ロスレス）は高画質ですが、TileSheetのディスク使用量が増加します。")
                    Text("PDF先読み上限: 大きなPDFのTileSheet生成ページ数を制限します。")
                }
                .font(.caption)
            }
            
            // MARK: - Cache Management
            Section {
                HStack {
                    Text("キャッシュファイル数:")
                    Spacer()
                    Text("\(cacheInfo.fileCount) 件")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("キャッシュサイズ:")
                    Spacer()
                    Text(formatBytes(cacheInfo.totalSize))
                        .foregroundStyle(.secondary)
                }
                
                Button("キャッシュをクリア") {
                    CacheManager.shared.clearAllCache()
                    updateCacheInfo()
                }
                .foregroundStyle(.orange)
            } header: {
                Text("キャッシュ")
            } footer: {
                Text("サムネイルのキャッシュを削除します。お気に入りは保持されます。")
                    .font(.caption)
            }
            
            // MARK: - Selection Mode
            Section {
                Picker("選択モード", selection: $settings.selectionMode) {
                    ForEach(SelectionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text(settings.selectionMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("選択モード")
            }
            
            // MARK: - Viewer Thumbnail Position
            Section {
                Picker("サムネイル位置", selection: $settings.viewerThumbnailPosition) {
                    ForEach(ViewerThumbnailPosition.allCases, id: \.self) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.radioGroup)
                Stepper(
                    "先読み枚数: \(settings.prefetchCount)",
                    value: $settings.prefetchCount,
                    in: 0...10
                )
                Toggle("ソース内ループナビゲーション", isOn: $settings.loopWithinSource)
                Stepper(
                    "N-stepジャンプ幅: \(settings.navigationStepCount)",
                    value: $settings.navigationStepCount,
                    in: 2...50
                )
            } header: {
                Text("ビューアモード")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("サムネイル位置はTキーでも切替可能")
                    Text("先読み: 0=無効、大きいほど快適だがメモリ使用増加")
                    Text("ループ: 末尾→先頭、先頭→末尾のナビゲーション")
                    Text("N-step: Ctrl+Option+キーでジャンプする幅")
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
                Toggle("末尾でループ", isOn: $settings.autoSlideLoops)
                HStack {
                    Spacer()
                    Button("初期値に戻す") {
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
                    Text("Space×1=Normal、Space×2=Fast、Space×3=Turbo")
                    Text("Space（再押し）で停止。Oキーでオーバーレイ切替")
                    Text("「末尾でループ」OFF時は末尾で自動停止")
                }
                .font(.caption)
            }
            
            // MARK: - Reading Direction (#54)
            Section {
                Picker("デフォルト方向", selection: $settings.defaultReadingDirection) {
                    ForEach(ReadingDirection.allCases, id: \.self) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("読み取り方向")
            } footer: {
                Text("新しいソースを開いた時のデフォルト。Ctrl+Rでソースごとに切替可能")
                    .font(.caption)
            }
            
            // MARK: - Spread Mode (#55)
            Section {
                Toggle("見開き表示", isOn: $settings.isSpreadModeEnabled)
                
                if settings.isSpreadModeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("横長検出しきい値:")
                            Spacer()
                            Text(String(format: "%.1f", settings.spreadThreshold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.spreadThreshold, in: 1.0...2.0, step: 0.1)
                        Text("幅/高さ > しきい値 の画像は自動で単独表示")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("見開きモード")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vキーで特定ページを単独表示に指定可能")
                    Text("横長画像（見開きスキャン）は自動で検出されます")
                }
                .font(.caption)
            }
            
            // MARK: - Metadata Carry-Over (#105)
            Section {
                Toggle("★ お気に入り", isOn: $settings.metadataCarryOverFavorites)
                Toggle("栞 ブックマーク", isOn: $settings.metadataCarryOverBookmarks)
                Toggle("読み取り方向", isOn: $settings.metadataCarryOverDirection)
                Toggle("単独表示マーカー", isOn: $settings.metadataCarryOverMarkers)
            } header: {
                Text("エクスポート時のメタデータ引き継ぎ")
            } footer: {
                Text("エクスポート先にコピーするメタデータの種類")
                    .font(.caption)
            }
            
            // MARK: - Output Folder
            Section {
                Toggle("デフォルトの出力先を使用", isOn: $settings.useDefaultOutputFolder)
                
                if settings.useDefaultOutputFolder {
                    HStack {
                        if let folder = settings.defaultOutputFolder {
                            Text(folder.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("未設定")
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("選択...") {
                            selectOutputFolder()
                        }
                    }
                }
            } header: {
                Text("出力先")
            } footer: {
                Text("オフの場合、元ファイルと同じフォルダに保存されます")
                    .font(.caption)
            }
            
            // MARK: - Reset
            Section {
                Button("設定をリセット") {
                    settings.resetToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 1150)
        .navigationTitle("設定")
        .onAppear {
            updateCacheInfo()
        }
    }
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "デフォルトの出力先を選択"
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
