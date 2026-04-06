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
            Text(String(localized: "exportConfirm.title", defaultValue: "Export Confirmation"))
                .font(.headline)
            
            // ★ warning
            if selectionMode == .exclude {
                Label("\(String(localized: "exportConfirm.favoritesPrefix", defaultValue: "★")) \(affectedFavoriteCount) \(String(localized: "exportConfirm.willBeExcluded", defaultValue: "will be excluded"))", systemImage: "star.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("\(String(localized: "exportConfirm.favoritesPrefix", defaultValue: "★")) \(affectedFavoriteCount) \(String(localized: "exportConfirm.notIncluded", defaultValue: "will not be included in output"))", systemImage: "star.fill")
                    .foregroundStyle(.orange)
            }
            
            Divider()
            
            // Metadata options
            Text(String(localized: "exportConfirm.metadataCarryOver", defaultValue: "Metadata Carry-Over"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Toggle(String(localized: "exportConfirm.favorites", defaultValue: "★ Favorites"), isOn: $options.favorites)
            Toggle(String(localized: "exportConfirm.bookmarks", defaultValue: "栞 Bookmarks"), isOn: $options.bookmarks)
            Toggle(String(localized: "exportConfirm.readingDirection", defaultValue: "Reading Direction"), isOn: $options.readingDirection)
            Toggle(String(localized: "exportConfirm.singlePageMarkers", defaultValue: "Single Page Markers"), isOn: $options.singlePageMarkers)
            
            Divider()
            
            // Buttons
            HStack {
                Spacer()
                Button(String(localized: "exportConfirm.cancel", defaultValue: "Cancel"), role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button(selectionMode == .exclude ? String(localized: "exportConfirm.exclude", defaultValue: "Exclude") : String(localized: "exportConfirm.proceed", defaultValue: "Proceed")) {
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

