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

    /// Replace detail content immediately.
    /// This is the mechanism that eliminates the 350ms NavigationSplitView delay.
    /// Each call creates a fresh NSHostingView — same safety as .id() recreation.
    func updateContent<V: View>(_ swiftUIView: V) {
        currentHostingView?.removeFromSuperview()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        currentHostingView = hostingView
        
        // Force immediate layout — may kick SwiftUI's onAppear earlier
        view.layoutSubtreeIfNeeded()
    }

    func showPlaceholder() {
        updateContent(
            ContentUnavailableView(
                "ZIPファイルまたはフォルダを選択",
                systemImage: "archivebox",
                description: Text("左のツリーから選んでください")
            )
        )
    }
}
