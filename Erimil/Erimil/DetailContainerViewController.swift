//
//  DetailContainerViewController.swift
//  Erimil
//
//  S090: #215 Phase 1 — Detail pane manager.
//  Source switch = removeFromSuperview() + addSubview() → instant, no framework delay.
//

import Cocoa
import SwiftUI

class DetailContainerViewController: NSViewController {
    private var currentHostingView: NSView?

    override func loadView() {
        self.view = NSView()
        showPlaceholder()
    }

    func updateContent<V: View>(_ swiftUIView: V) {
        currentHostingView?.removeFromSuperview()
        let hostingView = FlexibleHostingView(rootView: swiftUIView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        currentHostingView = hostingView
        
        // Force immediate layout
        //view.layoutSubtreeIfNeeded()
    }

    func showPlaceholder() {
        updateContent(
            ContentUnavailableView(
                String(localized: "detail.selectSource", defaultValue: "Select a ZIP File or Folder"),
                systemImage: "archivebox",
                description: Text(String(localized: "detail.selectSourceDescription", defaultValue: "Choose from the tree on the left"))
            )
        )
    }
}

/// NSHostingView that does not report intrinsic content size.
/// Prevents NSSplitView from shrinking to fit content height.
private class FlexibleHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
