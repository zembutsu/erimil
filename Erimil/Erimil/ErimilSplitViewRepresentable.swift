//
//  ErimilSplitViewRepresentable.swift
//  Erimil
//
//  S090: #215 Phase 1 — NSViewControllerRepresentable bridge.
//  Connects ContentView's @State (SwiftUI) to ErimilSplitViewController (AppKit).
//
//  Source switch flow (after S090 direct swap):
//    select() → onSourceChanged (synchronous) → updateContent() → INSTANT
//    select() → @Observable → SwiftUI body → updateNSVC → guard skips (already done)
//
//  WrapperViewController embeds the split view controller with frame-based layout.
//

import SwiftUI
import os

struct ErimilSplitViewRepresentable: NSViewControllerRepresentable {
    // MARK: - Source state
    let currentURL: URL?
    let currentSource: (any ImageSource)?
    let sourceSelection: SourceSelection

    // MARK: - Sidebar params
    @Binding var selectedFolderURL: URL?
    let folderReloadTrigger: UUID

    // MARK: - Detail bindings
    @Binding var selectedPaths: Set<String>
    @Binding var shouldReopenSlideMode: Bool
    @Binding var shouldReopenViewerMode: Bool
    @Binding var isInViewerMode: Bool

    // MARK: - Callbacks
    let onSourceSelect: (URL, ImageSourceType) -> Void
    let onOpenSlideMode: (URL) -> Void
    let onExportSuccess: () -> Void
    let onRequestNextSource: () -> Void
    let onRequestPreviousSource: () -> Void
    let onRequestSourceJump: (Int) -> Void

    // MARK: - NSViewControllerRepresentable

    func makeNSViewController(context: Context) -> WrapperViewController {
        let splitController = ErimilSplitViewController()
        let sidebarView = makeSidebarView()
        splitController.configure(sidebarView: AnyView(sidebarView))

        let wrapper = WrapperViewController()
        wrapper.embed(splitController)

        let coordinator = context.coordinator
        coordinator.splitController = splitController
        coordinator.currentRepresentable = self

        // Show initial content
        if let imageSource = currentSource {
            let detailView = makeDetailView(imageSource: imageSource)
            splitController.detailController.updateContent(detailView)
            coordinator.lastSourceURL = currentURL
        }

        // S090: Set up immediate source change callback.
        // Called synchronously from SourceSelection.select(), bypassing
        // SwiftUI's ~350ms @Observable → body → updateNSVC cycle.
        sourceSelection.onSourceChanged = { [weak coordinator] url, source in
            coordinator?.handleDirectSwap(url: url, source: source)
        }
        print("[makeNSVC] wrapper.view.bounds: \(wrapper.view.bounds)")
        print("[makeNSVC] splitController.view.frame: \(splitController.view.frame)")
        
        return wrapper
    }

    func updateNSViewController(_ wrapper: WrapperViewController, context: Context) {
        guard let controller = context.coordinator.splitController else { return }
        let coordinator = context.coordinator

        // Keep representable reference fresh (captures current bindings)
        coordinator.currentRepresentable = self

        // --- Sidebar update (always — cheap rootView diff) ---
        controller.updateSidebar(AnyView(makeSidebarView()))

        // --- Detail: source change detection ---
        // S090: If direct swap already handled this URL, skip.
        // This is the ~350ms-delayed SwiftUI path — the view is already on screen.
        if coordinator.lastSourceURL != currentURL {
            coordinator.lastSourceURL = currentURL

            if let imageSource = currentSource {
                let detailView = makeDetailView(imageSource: imageSource)
                controller.detailController.updateContent(detailView)
            } else {
                controller.detailController.showPlaceholder()
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController: WrapperViewController,
        context: Context
    ) -> CGSize? {
        return nil  // Let SwiftUI determine size from parent
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var splitController: ErimilSplitViewController?
        var lastSourceURL: URL?
        /// Current representable — used by direct swap to build detail views.
        /// Bindings inside point to stable @State storage, so they remain valid
        /// even though the Representable struct is a value type.
        var currentRepresentable: ErimilSplitViewRepresentable?

        /// S090: Called synchronously from SourceSelection.select().
        /// Swaps the detail view immediately, before SwiftUI's update cycle.
        func handleDirectSwap(url: URL?, source: (any ImageSource)?) {
            guard lastSourceURL != url else { return }
            lastSourceURL = url

            guard let repr = currentRepresentable else { return }

            if let source = source {
                let detailView = repr.makeDetailView(imageSource: source)
                splitController?.detailController.updateContent(detailView)
                SourceSwitchTiming.mark("direct.swap.done")
            } else {
                splitController?.detailController.showPlaceholder()
            }
        }
    }

    // MARK: - Wrapper ViewController

    class WrapperViewController: NSViewController {
        private var splitController: ErimilSplitViewController?

        override func loadView() {
            self.view = FillView()
        }

        func embed(_ child: ErimilSplitViewController) {
            splitController = child
            addChild(child)
            child.view.frame = view.bounds
            view.addSubview(child.view)
        }
    }

    /// NSSplitView ignores Auto Layout constraints and autoresizingMask
    /// for height when children report small intrinsicContentSize.
    /// This forces the split view to fill parent bounds on every layout pass.
    private class FillView: NSView {
        override func layout() {
            super.layout()
            let child = subviews.first
            print("[FillView.layout] bounds: \(bounds), child.frame before: \(child?.frame ?? .zero)")
            child?.frame = bounds
            print("[FillView.layout] child.frame after: \(child?.frame ?? .zero)")
        }
        
        override func resizeSubviews(withOldSize oldSize: NSSize) {
            super.resizeSubviews(withOldSize: oldSize)
            subviews.first?.frame = bounds
            print("[FillView.resize] bounds: \(bounds), child.frame: \(subviews.first?.frame ?? .zero)")
        }
    }

    // MARK: - View Builders

    private func makeSidebarView() -> SidebarView {
        SidebarView(
            selectedFolderURL: $selectedFolderURL,
            currentSourceURL: currentURL,
            onSourceSelect: onSourceSelect,
            onOpenSlideMode: onOpenSlideMode,
            reloadTrigger: folderReloadTrigger
        )
    }

    func makeDetailView(imageSource: any ImageSource) -> some View {
        let url = imageSource.url
        return ThumbnailGridView(
            imageSource: imageSource,
            selectedPaths: $selectedPaths,
            onExportSuccess: onExportSuccess,
            onRequestNextSource: onRequestNextSource,
            onRequestPreviousSource: onRequestPreviousSource,
            onRequestSourceJump: onRequestSourceJump,
            shouldReopenSlideMode: $shouldReopenSlideMode,
            shouldReopenViewerMode: $shouldReopenViewerMode,
            isInViewerMode: $isInViewerMode,
            consumePrefetchedEntries: {
                sourceSelection.consumePrefetchedEntries(for: url)
            }
        )
    }
}
