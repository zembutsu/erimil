//
//  ErimilSplitViewController.swift
//  Erimil
//
//  S090: #215 Phase 1 — NSSplitViewController replacing NavigationSplitView
//

import Cocoa
import SwiftUI

class ErimilSplitViewController: NSSplitViewController {
    private(set) var sidebarController: NSHostingController<AnyView>!
    private(set) var detailController: DetailContainerViewController!

    func configure(sidebarView: AnyView) {
        
        // S091: Replace default NSSplitView — prevent intrinsic size from
        // overriding parent frame when content is small (placeholder state)
        let flexibleSplitView = FlexibleNSSplitView()
        flexibleSplitView.isVertical = true
        flexibleSplitView.autosaveName = "ErimilMainSplit"
        self.splitView = flexibleSplitView

        sidebarController = NSHostingController(rootView: sidebarView)
        // S091: Prevent sidebar intrinsicContentSize from constraining split view height
        sidebarController.sizingOptions = []
        detailController = DetailContainerViewController()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 200
        sidebarItem.canCollapse = true

        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = 400

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        
        // Debug: check item frames after layout
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            print("[SplitVC] splitView.frame: \(self.splitView.frame)")
            for (i, item) in self.splitViewItems.enumerated() {
                let vc = item.viewController
                print("[SplitVC] item[\(i)] view.frame: \(vc.view.frame)")
                print("[SplitVC] item[\(i)] view.fittingSize: \(vc.view.fittingSize)")
            }
        }
    }

    /// Update sidebar content without recreating the controller.
    func updateSidebar(_ sidebarView: AnyView) {
        sidebarController.rootView = sidebarView
    }

    
    func toggleSidebarCollapse() {
        guard let sidebarItem = splitViewItems.first else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            sidebarItem.animator().isCollapsed.toggle()
        }
    }
}

private class FlexibleNSSplitView: NSSplitView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
