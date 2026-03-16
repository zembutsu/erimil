// MARK: - AnimationPlayer.swift
// #201 Phase 1: Animated GIF Playback
// CADisplayLink-based playback engine (macOS 14+ / NSView.displayLink)

import AppKit
import Combine

// MARK: - AnimationPlayer

class AnimationPlayer: NSObject, ObservableObject {

    let content: AnimatedImageContent

    @Published private(set) var currentFrame: CGImage
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var loopEnabled: Bool = true

    private var frameIndex: Int = 0
    private var elapsed: TimeInterval = 0
    private var completedLoops: Int = 0
    private var displayLink: CADisplayLink?
    private weak var hostView: NSView?

    init(content: AnimatedImageContent) {
        self.content = content
        self.currentFrame = content.frames[0].image
        super.init()
    }

    // MARK: - Lifecycle

    /// Attach to an NSView for CADisplayLink creation.
    /// Must be called before play(). The view must be in a window.
    func attach(to view: NSView) {
        hostView = view
    }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        if let link = displayLink {
            link.isPaused = false
        } else {
            guard let hostView else { return }
            let link = hostView.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        displayLink?.isPaused = true
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func toggleLoop() {
        loopEnabled.toggle()
    }

    /// Break the CADisplayLink ↔ AnimationPlayer retain cycle.
    /// Call from dismantleNSView or any teardown path. Safe to call multiple times.
    func invalidate() {
        pause()
        displayLink?.invalidate()
        displayLink = nil
    }

    func reset() {
        pause()
        frameIndex = 0
        elapsed = 0
        completedLoops = 0
        currentFrame = content.frames[0].image
    }

    // MARK: - Display Link Callback

    @objc private func tick(_ link: CADisplayLink) {
        let dt = link.targetTimestamp - link.timestamp
        elapsed += dt

        // Safety: cap frame advances per tick to prevent runaway on resume-from-background
        var advances = 0
        let maxAdvancesPerTick = 10

        while elapsed >= content.frames[frameIndex].duration
                && isPlaying
                && advances < maxAdvancesPerTick {

            elapsed -= content.frames[frameIndex].duration
            let nextIndex = frameIndex + 1

            if nextIndex >= content.frameCount {
                // Cycle complete
                completedLoops += 1

                let shouldStop: Bool
                if !loopEnabled {
                    // User toggled loop off → stop after this cycle
                    shouldStop = true
                } else if content.loopCount > 0 && completedLoops >= content.loopCount {
                    // GIF's own loop count reached
                    shouldStop = true
                } else {
                    shouldStop = false
                }

                if shouldStop {
                    pause()
                    return
                }
                frameIndex = 0
            } else {
                frameIndex = nextIndex
            }

            currentFrame = content.frames[frameIndex].image
            advances += 1
        }

        // If we hit the cap, reset elapsed to prevent accumulation
        if advances >= maxAdvancesPerTick {
            elapsed = 0
        }
    }

    deinit {
        displayLink?.invalidate()
    }
}

// MARK: - AnimationPlaybackController

/// Bridge between key handlers (ViewerView / SlideWindowController) and the active AnimationPlayer.
/// Lives at the viewer level. AnimatedImageOverlay sets/clears the player on appear/disappear.
class AnimationPlaybackController: ObservableObject {

    @Published var player: AnimationPlayer?

    /// True when an animated image is currently displayed (regardless of play state).
    var hasAnimatedContent: Bool { player != nil }

    /// True when animation is actively playing.
    var isPlaying: Bool { player?.isPlaying ?? false }

    func togglePlay() {
        player?.togglePlay()
    }

    func toggleLoop() {
        player?.toggleLoop()
    }
}
