// MARK: - AnimatedImageOverlay.swift
// #201 Phase 1: Animated GIF Playback
// SwiftUI ↔ NSView bridge. Displays animated frames via layer.contents.
// Static first frame is rendered by existing pipeline underneath;
// this overlay takes over once playback starts.

import SwiftUI
import Combine

struct AnimatedImageOverlay: NSViewRepresentable {

    let content: AnimatedImageContent
    let controller: AnimationPlaybackController

    func makeNSView(context: Context) -> AnimatedImageNSView {
        let player = AnimationPlayer(content: content)
        let view = AnimatedImageNSView(player: player)
        player.attach(to: view)

        
        // Defer @Published changes to next run loop to avoid publishing during view update
        DispatchQueue.main.async {
            // Register with controller so key handlers can reach the player
            controller.player = player
            // Auto-play (D006: default auto-play with infinite loop)
            player.play()
        }

        return view
    }

    func updateNSView(_ nsView: AnimatedImageNSView, context: Context) {
        // If content identity changed (different page), the whole view is recreated
        // by SwiftUI's diffing, so no update logic needed here.
    }

    static func dismantleNSView(_ nsView: AnimatedImageNSView, coordinator: ()) {
        nsView.player.invalidate()
        // Controller.player will be set to nil or replaced by next overlay
    }
}

// MARK: - AnimatedImageNSView

class AnimatedImageNSView: NSView {

    let player: AnimationPlayer
    private var cancellable: AnyCancellable?

    init(player: AnimationPlayer) {
        self.player = player
        super.init(frame: .zero)

        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = .clear

        // Observe frame changes and push to layer
        cancellable = player.$currentFrame
            .sink { [weak self] frame in
                self?.layer?.contents = frame
            }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
}
