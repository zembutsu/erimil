//
//  ImagePreviewView.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import SwiftUI
import AppKit

struct ImagePreviewView: View {
    let image: NSImage
    let entryName: String
    let onClose: () -> Void
    
    var body: some View {
        ZStack {
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
            
            // Key event handler for Space/Escape/Enter (transparent to clicks)
            PreviewKeyEventHandler(onClose: onClose)
                .allowsHitTesting(false)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - Key Event Handler for Preview

struct PreviewKeyEventHandler: NSViewRepresentable {
    let onClose: () -> Void
    
    func makeNSView(context: Context) -> PreviewKeyView {
        let view = PreviewKeyView()
        view.onClose = onClose
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: PreviewKeyView, context: Context) {
        nsView.onClose = onClose
    }
    
    class PreviewKeyView: NSView {
        var onClose: (() -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            // Space (49), Escape (53), or Enter (36)
            if event.keyCode == 49 || event.keyCode == 53 || event.keyCode == 36 {
                onClose?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

#Preview {
    ImagePreviewView(
        image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!,
        entryName: "sample.jpg",
        onClose: {}
    )
}
