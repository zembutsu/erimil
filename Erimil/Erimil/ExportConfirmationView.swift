//
//  ExportConfirmationView.swift
//  Erimil
//
//  Extracted from ThumbnailGridView.swift (#175 Phase 1)
//  Contains: ExportConfirmationView
//

import SwiftUI

// MARK: - Export Confirmation View (#105)

/// Sheet dialog for export confirmation with metadata carry-over options
struct ExportConfirmationView: View {
    let affectedFavoriteCount: Int
    let selectionMode: SelectionMode
    @Binding var options: MetadataCarryOverOptions
    let onCancel: () -> Void
    let onExport: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text("エクスポートの確認")
                .font(.headline)
            
            // ★ warning
            if selectionMode == .exclude {
                Label("★付き \(affectedFavoriteCount) 件が除外されます", systemImage: "star.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("★付き \(affectedFavoriteCount) 件が出力に含まれません", systemImage: "star.fill")
                    .foregroundStyle(.orange)
            }
            
            Divider()
            
            // Metadata options
            Text("メタデータの引き継ぎ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Toggle("★ お気に入り", isOn: $options.favorites)
            Toggle("栞 ブックマーク", isOn: $options.bookmarks)
            Toggle("読み取り方向", isOn: $options.readingDirection)
            Toggle("単独表示マーカー", isOn: $options.singlePageMarkers)
            
            Divider()
            
            // Buttons
            HStack {
                Spacer()
                Button("キャンセル", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button(selectionMode == .exclude ? "除外する" : "続行") {
                    onExport()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

