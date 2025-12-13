//
//  ImagePreviewView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//


import SwiftUI

struct ImagePreviewView: View {
    let image: NSImage
    let entryName: String
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text(entryName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            // 画像表示
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

#Preview {
    ImagePreviewView(
        image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!,
        entryName: "sample.jpg",
        onClose: {}
    )
}
