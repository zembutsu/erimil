//
//  MetadataInspectorView.swift
//  Erimil
//
//  Metadata inspector overlay for Viewer Mode / Slide Mode (#140)
//  Session: S058
//
//  Toggle: "i" key or Esc to dismiss
//  Features: category grouping, per-value copy, full copy
//

import SwiftUI
import os

struct MetadataInspectorView: View {
    let sections: [MetadataSection]
    let onClose: () -> Void
    
    @State private var expandedSections: Set<String> = []
    @State private var copiedItemId: UUID? = nil
    @State private var showCopiedAll: Bool = false
    
    var body: some View {
        HStack {
            Spacer()
            panelContent
                .frame(width: 340)
                .frame(maxHeight: 500)
                .background(.regularMaterial)
                .cornerRadius(12)
                .shadow(radius: 20)
                .padding(.trailing, 24)
                .padding(.top, 60)
                .onAppear { expandFirstSection() }
                .onChange(of: sections.map(\.name)) { _, newNames in
                    // Ensure at least the first section is expanded when content changes
                    if !newNames.isEmpty && expandedSections.isDisjoint(with: newNames) {
                        expandedSections.insert(newNames[0])
                    }
                }
        }
    }
    
    // MARK: - Panel Content
    
    @ViewBuilder
    private var panelContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("Metadata")
                    .font(.headline)
                Spacer()
                
                // Copy All button
                Button {
                    copyAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopiedAll ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                        Text(showCopiedAll ? "Copied" : "Copy All")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // Close button
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            if sections.isEmpty {
                emptyState
            } else {
                sectionList
            }
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.questionmark")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No metadata available")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
    
    // MARK: - Section List
    
    @ViewBuilder
    private var sectionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sections) { section in
                    sectionView(section)
                }
            }
        }
    }
    
    @ViewBuilder
    private func sectionView(_ section: MetadataSection) -> some View {
        VStack(spacing: 0) {
            // Section header (tap to expand/collapse)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedSections.contains(section.name) {
                        expandedSections.remove(section.name)
                    } else {
                        expandedSections.insert(section.name)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: expandedSections.contains(section.name) ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 12)
                    Text(section.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(section.items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Items
            if expandedSections.contains(section.name) {
                ForEach(section.items) { item in
                    itemRow(item)
                }
            }
            
            Divider()
                .padding(.leading, 16)
        }
    }
    
    @ViewBuilder
    private func itemRow(_ item: MetadataItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Key
            Text(item.key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
                .lineLimit(2)
            
            // Value
            Text(item.value.count > 1000 ? String(item.value.prefix(1000)) + "…" : item.value)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Copy button
            Button {
                copyItem(item)
            } label: {
                Image(systemName: copiedItemId == item.id ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(copiedItemId == item.id ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // MARK: - Actions
    
    private func expandFirstSection() {
        if let first = sections.first {
            expandedSections.insert(first.name)
        }
    }
    
    private func copyItem(_ item: MetadataItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.value, forType: .string)
        
        copiedItemId = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedItemId == item.id {
                copiedItemId = nil
            }
        }
    }
    
    private func copyAll() {
        let text = MetadataExtractor.formatAsText(sections)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        showCopiedAll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedAll = false
        }
    }
}
