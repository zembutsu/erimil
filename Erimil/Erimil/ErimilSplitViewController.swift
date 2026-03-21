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
        sidebarController = NSHostingController(rootView: sidebarView)
        detailController = DetailContainerViewController()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 200
        sidebarItem.canCollapse = true

        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = 400

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
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
