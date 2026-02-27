//
//  MetadataInspectorPanelController.swift
//  Erimil
//
//  NSPanel-based metadata inspector (#140)
//  Session: S059
//
//  Standalone floating panel for metadata display.
//  Native drag, resize, and position/size persistence via frameAutosaveName.
//  Used by both Slide Mode (SlideWindowController) and Viewer Mode (ViewerView).
//

import SwiftUI
import AppKit
import Combine
import os

// MARK: - Panel Controller

/// Manages a floating NSPanel that displays image metadata.
/// Shared singleton — one inspector panel across all viewing modes.
class MetadataInspectorPanelController {
    
    static let shared = MetadataInspectorPanelController()
    
    private var panel: NSPanel?
    private let model = MetadataInspectorModel()
    
    /// Whether the inspector panel is currently visible
    var isVisible: Bool { panel?.isVisible ?? false }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Toggle inspector visibility
    func toggle(
        imageSource: (any ImageSource)?,
        entry: ImageEntry?,
        parentWindow: NSWindow?
    ) {
        if isVisible {
            close()
        } else {
            show(imageSource: imageSource, entry: entry, parentWindow: parentWindow)
        }
    }
    
    /// Show the inspector panel with metadata for the given entry
    func show(
        imageSource: (any ImageSource)?,
        entry: ImageEntry?,
        parentWindow: NSWindow?
    ) {
        guard let imageSource, let entry else {
            Logger.metadata.debug("Inspector show: no source or entry")
            return
        }
        
        // Extract metadata
        model.sections = MetadataExtractor.extract(from: imageSource, entry: entry)
        
        // Create panel if needed
        if panel == nil {
            createPanel()
        }
        
        guard let panel else { return }
        
        // Attach to parent window
        if let parentWindow, panel.parent == nil {
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        
        panel.orderFront(nil)
        Logger.metadata.debug("Inspector shown")
    }
    
    /// Update metadata content (call when user navigates to a different image)
    func update(imageSource: (any ImageSource)?, entry: ImageEntry?) {
        guard isVisible, let imageSource, let entry else { return }
        model.sections = MetadataExtractor.extract(from: imageSource, entry: entry)
    }
    
    /// Close the inspector panel
    func close() {
        guard let panel else { return }
        
        // Detach from parent
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        
        panel.orderOut(nil)
        Logger.metadata.debug("Inspector closed")
    }
    
    /// Re-attach panel to a new parent window (e.g., switching between Viewer and Slide)
    func reparent(to newParent: NSWindow?) {
        guard let panel, isVisible else { return }
        
        // Detach from current parent
        if let oldParent = panel.parent {
            oldParent.removeChildWindow(panel)
        }
        
        // Attach to new parent
        if let newParent {
            newParent.addChildWindow(panel, ordered: .above)
        }
    }
    
    // MARK: - Panel Creation
    
    private func createPanel() {
        let contentView = MetadataInspectorPanelView(
            model: model,
            onClose: { [weak self] in self?.close() }
        )
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "Metadata"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false  // Keep visible when app loses focus briefly
        panel.animationBehavior = .utilityWindow
        
        // Size constraints
        panel.minSize = NSSize(width: 280, height: 200)
        panel.maxSize = NSSize(width: 600, height: 800)
        
        // Fullscreen support — appear alongside fullscreen windows
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        
        // Auto-save position and size
        panel.setFrameAutosaveName("ErimilMetadataInspector")
        
        // Set content
        panel.contentView = NSHostingView(rootView: contentView)
        
        // Default position (right side of screen) if no saved frame
        if !panel.setFrameUsingName("ErimilMetadataInspector") {
            positionDefault(panel)
        }
        
        self.panel = panel
        
        Logger.metadata.debug("Inspector panel created")
    }
    
    /// Position panel at right side of the parent or screen
    private func positionDefault(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let x = screenFrame.maxX - panelFrame.width - 20
        let y = screenFrame.midY - panelFrame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Observable Model

/// Reactive model for metadata content updates
class MetadataInspectorModel: ObservableObject {
    @Published var sections: [MetadataSection] = []
}

// MARK: - Panel SwiftUI View

/// SwiftUI view hosted inside the NSPanel.
/// Observes MetadataInspectorModel for reactive content updates.
struct MetadataInspectorPanelView: View {
    @ObservedObject var model: MetadataInspectorModel
    let onClose: () -> Void
    
    var body: some View {
        MetadataInspectorContent(
            sections: model.sections,
            showCloseButton: false,  // Panel title bar provides close
            onClose: onClose
        )
    }
}
