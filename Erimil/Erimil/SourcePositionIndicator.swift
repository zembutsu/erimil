//
//  SourcePositionIndicator.swift
//  Erimil
//
//  Created for Issue #23 - Source position indicator
//  Session: S010 (2025-01-11)
//

import SwiftUI

/// Displays source position as dot bar + numeric indicator
/// Used in Slide Mode to show current position among sibling sources
struct SourcePositionIndicator: View {
    let current: Int      // 1-based current position
    let total: Int        // Total number of sources
    let barWidth: CGFloat // Fixed width to match image bar
    
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
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index == current - 1 ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        } else {
            // Too many sources: show proportional bar with position marker
            let markerPosition = CGFloat(current - 1) / CGFloat(total - 1) * barWidth
            
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

#Preview("Few Sources") {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            SourcePositionIndicator(current: 1, total: 5, barWidth: 144)
            SourcePositionIndicator(current: 3, total: 5, barWidth: 144)
            SourcePositionIndicator(current: 5, total: 5, barWidth: 144)
        }
        .padding()
    }
}

#Preview("Many Sources") {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            SourcePositionIndicator(current: 1, total: 50, barWidth: 144)
            SourcePositionIndicator(current: 25, total: 50, barWidth: 144)
            SourcePositionIndicator(current: 50, total: 50, barWidth: 144)
        }
        .padding()
    }
}

#Preview("Edge Cases") {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            SourcePositionIndicator(current: 1, total: 1, barWidth: 144)
            SourcePositionIndicator(current: 1, total: 12, barWidth: 144)
            SourcePositionIndicator(current: 7, total: 12, barWidth: 144)
            SourcePositionIndicator(current: 1, total: 13, barWidth: 144)
        }
        .padding()
    }
}
