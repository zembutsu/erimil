//
//  SourcePositionIndicator.swift
//  Erimil
//
//  Created for Issue #23 - Source position indicator
//  Session: S010 (2025-01-11)
//  Updated: S019 (2026-01-25) - RTL support (#54)
//

import SwiftUI

/// Displays source position as dot bar + numeric indicator
/// Used in Slide Mode to show current position among sibling sources
struct SourcePositionIndicator: View {
    let current: Int      // 1-based current position
    let total: Int        // Total number of sources
    let barWidth: CGFloat // Fixed width to match image bar
    let isRTL: Bool       // #54: RTL direction support
    
    private let maxDots = 12  // Maximum visible dots
    
    var body: some View {
        HStack(spacing: 6) {
            // Dot bar (fixed width)
            dotBar
                .frame(width: barWidth)
            
            Spacer()
            
            // Numeric indicator (right-aligned)
            Text("\(current)/\(total)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
        }
    }
    
    @ViewBuilder
    private var dotBar: some View {
        if total <= maxDots {
            // Show individual dots
            HStack(spacing: 4) {
                let indices = isRTL ? (0..<total).reversed().map { $0 } : Array(0..<total)
                ForEach(indices, id: \.self) { index in
                    Circle()
                        .fill(index == current - 1 ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        } else {
            // Too many sources: show proportional bar with position marker
            let rawPosition = CGFloat(current - 1) / CGFloat(total - 1)
            let markerPosition = (isRTL ? (1.0 - rawPosition) : rawPosition) * barWidth
            
            ZStack(alignment: .leading) {
                // Background bar
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                
                // Position marker
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .offset(x: markerPosition - 5)
            }
            .frame(height: 10)
        }
    }
}

// MARK: - Preview

#Preview("Few Sources LTR") {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            SourcePositionIndicator(current: 1, total: 5, barWidth: 144, isRTL: false)
            SourcePositionIndicator(current: 3, total: 5, barWidth: 144, isRTL: false)
            SourcePositionIndicator(current: 5, total: 5, barWidth: 144, isRTL: false)
        }
        .padding()
    }
}

#Preview("Few Sources RTL") {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            SourcePositionIndicator(current: 1, total: 5, barWidth: 144, isRTL: true)
            SourcePositionIndicator(current: 3, total: 5, barWidth: 144, isRTL: true)
            SourcePositionIndicator(current: 5, total: 5, barWidth: 144, isRTL: true)
        }
        .padding()
    }
}

#Preview("Many Sources") {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            SourcePositionIndicator(current: 1, total: 50, barWidth: 144, isRTL: false)
            SourcePositionIndicator(current: 25, total: 50, barWidth: 144, isRTL: false)
            SourcePositionIndicator(current: 25, total: 50, barWidth: 144, isRTL: true)
            SourcePositionIndicator(current: 50, total: 50, barWidth: 144, isRTL: true)
        }
        .padding()
    }
}
