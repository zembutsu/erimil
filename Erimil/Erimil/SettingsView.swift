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
    
    var body: some View {
        Form {
            // MARK: - Thumbnail Size
            Section {
                Picker("プリセット", selection: $settings.thumbnailSizePreset) {
                    ForEach(ThumbnailSizePreset.allCases, id: \.self) { preset in
                        Text("\(preset.displayName) (\(Int(preset.size))px)").tag(preset)
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
                    in: 0...5
                )
            } header: {
                Text("ビューアモード")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("サムネイル位置はTキーでも切替可能")
                    Text("先読み: 0=無効、大きいほど快適だがメモリ使用増加")
                }
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
        .frame(width: 450, height: 550)
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
