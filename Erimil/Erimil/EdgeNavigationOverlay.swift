//
//  EdgeNavigationOverlay.swift
//  Erimil
//
//  Created for #255 - Edge-click chevron overlay
//  Session: S114 (2026-04-11)
//  Shared between Slide Mode and Reader Mode (Viewer Mode)
//

import SwiftUI

/// #255: Transparent edge-click navigation with hover chevron fade-in.
/// Click area: left/right halves of the view.
/// Chevron display: only when hovering within `chevronZoneWidth` of the edge.
/// Parent must apply `.environment(\.layoutDirection)` for RTL support.
struct EdgeNavigationOverlay: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    var chevronZoneWidth: CGFloat = 240
    
    @Environment(\.layoutDirection) private var layoutDirection
    
    private var isRTL: Bool { layoutDirection == .rightToLeft }
    
    @State private var isHoveringBack = false
    @State private var isHoveringForward = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Leading half — back
            Button(action: { if canGoBack { onBack() } }) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        chevronZone(
                            systemName: isRTL ? "chevron.right" : "chevron.left",
                            isHovering: $isHoveringBack,
                            visible: canGoBack,
                            iconAlignment: .leading
                        )
                    }
            }
            .buttonStyle(.plain)
            
            // Trailing half — forward
            Button(action: { if canGoForward { onForward() } }) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        chevronZone(
                            systemName: isRTL ? "chevron.left" : "chevron.right",
                            isHovering: $isHoveringForward,
                            visible: canGoForward,
                            iconAlignment: .trailing
                        )
                    }
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func chevronZone(
        systemName: String,
        isHovering: Binding<Bool>,
        visible: Bool,
        iconAlignment: Alignment
    ) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: chevronZoneWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovering.wrappedValue = $0 }
            .overlay {
                Image(systemName: systemName)
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 0)
                    .opacity(visible && isHovering.wrappedValue ? 0.6 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering.wrappedValue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: iconAlignment)
                    .padding(.horizontal, 16)
            }
    }
}
