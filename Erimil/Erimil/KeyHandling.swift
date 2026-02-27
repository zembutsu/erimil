//
//  KeyHandling.swift
//  Erimil
//
//  Consolidated key handling logic for all viewer modes
//  Session: S031 (2026-02-03) - #72 Consolidate key handlers
//
//  Provides:
//  - Common key action definitions
//  - RTL-aware navigation helpers
//  - Spread-aware navigation calculations
//  - Favorite navigation logic
//

import Foundation
import SwiftUI
import AppKit
import os

// MARK: - Navigation Direction

/// Logical navigation direction (before RTL adjustment)
enum NavigationDirection {
    case forward
    case backward
    
    /// Invert direction for RTL mode
    var inverted: NavigationDirection {
        switch self {
        case .forward: return .backward
        case .backward: return .forward
        }
    }
}

// MARK: - Key Actions

/// All possible key actions across viewer modes
enum KeyAction {
    // Navigation
    case navigate(NavigationDirection)
    case navigateSource(NavigationDirection)
    case navigateFavorite(NavigationDirection)
    
    // #143: N-step navigation (Ctrl+Option)
    case navigateNStep(NavigationDirection)
    case navigateSourceNStep(NavigationDirection)
    case navigateFavoriteNStep(NavigationDirection)
    
    // Position jumps (#72: Ctrl+A/D, Ctrl+1-5)
    case jumpToStart
    case jumpToEnd
    case jumpToPercent(Int)  // 25, 50, 75
    
    // Toggles
    case toggleFavorite
    case toggleSelection
    case toggleSinglePageMarker
    case toggleReadingDirection
    case toggleThumbnailPosition
    case toggleControls
    case toggleDeskew               // #101: Cmd+D
    case adjustDeskew(CGFloat)      // #101: Cmd+[/] (degrees)
    
    // Bookmarks (#62)
    case addOrDeleteBookmark       // Shift+S
    case navigateBookmark(NavigationDirection)  // Shift+A/D
    case showBookmarkList          // Shift+B
    case toggleMetadataInspector   // #140: I key
    
    // Mode transitions
    case close
    case enterSlideMode
    case exitToFiler
    case enterFavoritesMode
    case exitFavoritesMode
}

// MARK: - Navigation Helper

/// Centralized navigation logic with RTL and spread support
struct NavigationHelper {
    
    // MARK: - RTL-Aware Direction
    
    /// Apply RTL inversion to navigation direction
    /// - Parameters:
    ///   - direction: Original direction
    ///   - isRTL: Whether RTL mode is active
    /// - Returns: Adjusted direction
    static func adjustForRTL(_ direction: NavigationDirection, isRTL: Bool) -> NavigationDirection {
        return isRTL ? direction.inverted : direction
    }
    
    // MARK: - Index Navigation (Spread-Aware)
    
    /// Calculate next index with spread-aware stepping
    /// - Parameters:
    ///   - currentIndex: Current position
    ///   - entries: All image entries
    ///   - sourceURL: Source URL for spread detection
    ///   - loopEnabled: Whether to loop at boundaries
    /// - Returns: New index, or nil if no movement possible
    static func nextIndex(
        from currentIndex: Int,
        entries: [ImageEntry],
        sourceURL: URL,
        loopEnabled: Bool = false
    ) -> Int? {
        guard !entries.isEmpty else { return nil }
        guard currentIndex < entries.count - 1 || loopEnabled else { return nil }
        
        // Calculate step using cached aspect ratios
        let isSingle = SpreadNavigationHelper.shouldShowSinglePage(
            for: sourceURL,
            at: currentIndex,
            totalCount: entries.count,
            entries: entries
        )
        let step = isSingle ? 1 : 2
        
        let nextIdx = currentIndex + step
        if nextIdx < entries.count {
            return nextIdx
        } else if currentIndex < entries.count - 1 {
            // Step would overshoot but there's still a page
            return entries.count - 1
        } else if loopEnabled {
            return 0
        }
        return nil
    }
    
    /// Calculate previous index with spread-aware stepping
    /// - Parameters:
    ///   - currentIndex: Current position
    ///   - entries: All image entries
    ///   - sourceURL: Source URL for spread detection
    ///   - loopEnabled: Whether to loop at boundaries
    /// - Returns: New index, or nil if no movement possible
    static func previousIndex(
        from currentIndex: Int,
        entries: [ImageEntry],
        sourceURL: URL,
        loopEnabled: Bool = false
    ) -> Int? {
        guard !entries.isEmpty else { return nil }
        guard currentIndex > 0 || loopEnabled else { return nil }
        
        // Try to determine step using cached aspect ratios
        if currentIndex >= 2 {
            let prevIndex = currentIndex - 2
            let wouldBeSingle = SpreadNavigationHelper.shouldShowSinglePage(
                for: sourceURL,
                at: prevIndex,
                totalCount: entries.count,
                entries: entries
            )
            
            if !wouldBeSingle {
                return prevIndex
            }
        }
        
        // Fallback: step -1
        if currentIndex > 0 {
            return currentIndex - 1
        } else if loopEnabled {
            return entries.count - 1
        }
        return nil
    }
    
    /// Navigate in a direction with RTL and spread support
    /// - Parameters:
    ///   - direction: Logical direction (forward/backward)
    ///   - currentIndex: Current position
    ///   - entries: All image entries
    ///   - sourceURL: Source URL
    ///   - isRTL: Whether RTL mode is active
    ///   - loopEnabled: Whether to loop at boundaries
    /// - Returns: New index, or nil if no movement possible
    static func navigate(
        direction: NavigationDirection,
        from currentIndex: Int,
        entries: [ImageEntry],
        sourceURL: URL,
        isRTL: Bool,
        loopEnabled: Bool = false
    ) -> Int? {
        let adjustedDirection = adjustForRTL(direction, isRTL: isRTL)
        
        switch adjustedDirection {
        case .forward:
            return nextIndex(from: currentIndex, entries: entries, sourceURL: sourceURL, loopEnabled: loopEnabled)
        case .backward:
            return previousIndex(from: currentIndex, entries: entries, sourceURL: sourceURL, loopEnabled: loopEnabled)
        }
    }
    
    // MARK: - Favorite Navigation
    
    /// Find next favorite index
    /// - Parameters:
    ///   - currentIndex: Current position
    ///   - favoriteIndices: Set of favorite indices
    ///   - wrap: Whether to wrap around
    /// - Returns: Next favorite index, or nil if none
    static func nextFavoriteIndex(
        from currentIndex: Int,
        favoriteIndices: Set<Int>,
        wrap: Bool = true
    ) -> Int? {
        guard !favoriteIndices.isEmpty else { return nil }
        
        // Find smallest favorite > currentIndex
        let nextFavorites = favoriteIndices.filter { $0 > currentIndex }
        if let targetIndex = nextFavorites.min() {
            return targetIndex
        } else if wrap, let firstFavorite = favoriteIndices.min(), firstFavorite != currentIndex {
            // Wrap to first favorite
            return firstFavorite
        }
        return nil
    }
    
    /// Find previous favorite index
    /// - Parameters:
    ///   - currentIndex: Current position
    ///   - favoriteIndices: Set of favorite indices
    ///   - wrap: Whether to wrap around
    /// - Returns: Previous favorite index, or nil if none
    static func previousFavoriteIndex(
        from currentIndex: Int,
        favoriteIndices: Set<Int>,
        wrap: Bool = true
    ) -> Int? {
        guard !favoriteIndices.isEmpty else { return nil }
        
        // Find largest favorite < currentIndex
        let previousFavorites = favoriteIndices.filter { $0 < currentIndex }
        if let targetIndex = previousFavorites.max() {
            return targetIndex
        } else if wrap, let lastFavorite = favoriteIndices.max(), lastFavorite != currentIndex {
            // Wrap to last favorite
            return lastFavorite
        }
        return nil
    }
    
    // MARK: - Spread-Aware Favorite Navigation (#14: unified from 4 viewers)
    
    /// Find previous favorite index with spread leading-page correction (#104)
    /// When a ★ is on a spread's partner page, adjusts to the leading page so
    /// the spread pair is displayed correctly.
    static func previousFavoriteIndexSpreadAware(
        from currentIndex: Int,
        favoriteIndices: Set<Int>,
        sourceURL: URL,
        entries: [ImageEntry],
        wrap: Bool = true
    ) -> Int? {
        guard var targetIndex = previousFavoriteIndex(
            from: currentIndex, favoriteIndices: favoriteIndices, wrap: wrap
        ) else { return nil }
        
        // #129: Snap to correct spread-start using global alignment trace
        targetIndex = SpreadNavigationHelper.spreadStartIndex(
            for: targetIndex, sourceURL: sourceURL, entries: entries)
        
        return targetIndex
    }
    
    /// Find next favorite index with spread skip correction (#104)
    /// When the next ★ is on the partner page of the current spread (already visible),
    /// skips to the following ★ instead.
    static func nextFavoriteIndexSpreadAware(
        from currentIndex: Int,
        favoriteIndices: Set<Int>,
        sourceURL: URL,
        entries: [ImageEntry],
        isShowingSpread: Bool,
        wrap: Bool = true
    ) -> Int? {
        guard var targetIndex = nextFavoriteIndex(
            from: currentIndex, favoriteIndices: favoriteIndices, wrap: wrap
        ) else { return nil }
        
        // #104: Skip if target is partner of current spread (already visible)
        if isShowingSpread && targetIndex == currentIndex + 1 {
            guard let nextTarget = nextFavoriteIndex(
                from: targetIndex, favoriteIndices: favoriteIndices, wrap: wrap
            ) else { return nil }
            targetIndex = nextTarget
        }
        
        // #129: Snap to correct spread-start using global alignment trace
        targetIndex = SpreadNavigationHelper.spreadStartIndex(
            for: targetIndex, sourceURL: sourceURL, entries: entries)
        
        return targetIndex
    }
    
    /// Navigate to favorite in a direction with RTL support
    /// - Parameters:
    ///   - direction: Logical direction
    ///   - currentIndex: Current position
    ///   - favoriteIndices: Set of favorite indices
    ///   - isRTL: Whether RTL mode is active
    ///   - wrap: Whether to wrap around
    /// - Returns: Target favorite index, or nil if none
    static func navigateFavorite(
        direction: NavigationDirection,
        from currentIndex: Int,
        favoriteIndices: Set<Int>,
        isRTL: Bool,
        wrap: Bool = true
    ) -> Int? {
        let adjustedDirection = adjustForRTL(direction, isRTL: isRTL)
        
        switch adjustedDirection {
        case .forward:
            return nextFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: wrap)
        case .backward:
            return previousFavoriteIndex(from: currentIndex, favoriteIndices: favoriteIndices, wrap: wrap)
        }
    }
    
    // MARK: - Position Jump (#72: Ctrl+A/D, Ctrl+1-5)
    
    /// Calculate index for percentage position
    /// - Parameters:
    ///   - percent: Target percentage (0, 25, 50, 75, 100)
    ///   - totalCount: Total number of entries
    /// - Returns: Target index
    static func indexForPercent(_ percent: Int, totalCount: Int) -> Int {
        guard totalCount > 0 else { return 0 }
        
        switch percent {
        case 0:
            return 0
        case 100:
            return totalCount - 1
        default:
            let index = (totalCount - 1) * percent / 100
            return min(max(0, index), totalCount - 1)
        }
    }
    
    /// Get index for last item
    /// - Parameter totalCount: Total number of entries
    /// - Returns: Last valid index
    static func lastIndex(totalCount: Int) -> Int {
        return max(0, totalCount - 1)
    }
    
    // MARK: - Bookmark Navigation (#62)
    
    /// Navigate to bookmark in a direction with RTL support
    static func navigateBookmark(
        direction: NavigationDirection,
        from currentIndex: Int,
        sourceURL: URL,
        isRTL: Bool,
        wrap: Bool = true
    ) -> Int? {
        let adjustedDirection = adjustForRTL(direction, isRTL: isRTL)
        
        switch adjustedDirection {
        case .forward:
            return CacheManager.shared.nextBookmarkIndex(for: sourceURL, from: currentIndex, wrap: wrap)
        case .backward:
            return CacheManager.shared.previousBookmarkIndex(for: sourceURL, from: currentIndex, wrap: wrap)
        }
    }
    
    // MARK: - N-Step Navigation (#143)
    
    /// Jump N entries forward/backward with boundary clamping
    /// - Parameters:
    ///   - direction: Logical direction (forward/backward)
    ///   - currentIndex: Current position
    ///   - totalCount: Total number of entries
    ///   - stepCount: Number of steps (from AppSettings)
    ///   - isRTL: Whether RTL mode is active
    /// - Returns: New index (always valid, clamped to boundaries)
    static func navigateNStep(
        direction: NavigationDirection,
        from currentIndex: Int,
        totalCount: Int,
        stepCount: Int,
        isRTL: Bool
    ) -> Int? {
        guard totalCount > 0 else { return nil }
        let adjustedDirection = adjustForRTL(direction, isRTL: isRTL)
        
        switch adjustedDirection {
        case .forward:
            let target = currentIndex + stepCount
            return min(target, totalCount - 1)
        case .backward:
            let target = currentIndex - stepCount
            return max(target, 0)
        }
    }
    
    /// Jump N favorites forward/backward with boundary clamping
    /// - Parameters:
    ///   - direction: Logical direction
    ///   - currentIndex: Current position
    ///   - favoriteIndices: Set of favorite indices
    ///   - stepCount: Number of favorites to skip
    ///   - isRTL: Whether RTL mode is active
    /// - Returns: Target favorite index, or nil if no favorites
    static func navigateFavoriteNStep(
        direction: NavigationDirection,
        from currentIndex: Int,
        favoriteIndices: Set<Int>,
        stepCount: Int,
        isRTL: Bool
    ) -> Int? {
        guard !favoriteIndices.isEmpty else { return nil }
        let adjustedDirection = adjustForRTL(direction, isRTL: isRTL)
        let sorted = favoriteIndices.sorted()
        
        switch adjustedDirection {
        case .forward:
            // Find current position in sorted favorites
            let afterCurrent = sorted.filter { $0 > currentIndex }
            if afterCurrent.count <= stepCount {
                return sorted.last  // Clamp to last favorite
            }
            return afterCurrent[stepCount - 1]
        case .backward:
            let beforeCurrent = sorted.filter { $0 < currentIndex }.reversed()
            let beforeArray = Array(beforeCurrent)
            if beforeArray.count <= stepCount {
                return sorted.first  // Clamp to first favorite
            }
            return beforeArray[stepCount - 1]
        }
    }
}

// MARK: - Key Code Constants

/// Common key codes for macOS
enum KeyCode {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    
    // Letter keys
    static let a: UInt16 = 0
    static let b: UInt16 = 11   // #62: Bookmark list
    static let d: UInt16 = 2
    static let f: UInt16 = 3
    static let r: UInt16 = 15
    static let q: UInt16 = 12
    static let s: UInt16 = 1
    static let t: UInt16 = 17
    static let v: UInt16 = 9
    static let w: UInt16 = 13
    static let x: UInt16 = 7
    static let z: UInt16 = 6
    static let c: UInt16 = 8
    
    // Number keys (main keyboard, not numpad)
    static let num1: UInt16 = 18
    static let num2: UInt16 = 19
    static let num3: UInt16 = 20
    static let num4: UInt16 = 21
    static let num5: UInt16 = 23
}

// MARK: - Common Key Event Parsing

/// Parse common navigation keys from NSEvent
/// Returns the action if recognized, nil otherwise
struct CommonKeyParser {
    
    /// Parse navigation and common action keys
    /// - Parameters:
    ///   - event: Key event
    ///   - isFavoritesMode: Whether in favorites mode (affects arrow key behavior)
    /// - Returns: Recognized action, or nil
    static func parseNavigationKey(
        _ event: NSEvent,
        isFavoritesMode: Bool = false
    ) -> KeyAction? {
        let hasControl = event.modifierFlags.contains(.control)
        let hasOption = event.modifierFlags.contains(.option)
        
        // #143: Ctrl+Option = N-step navigation (must check before Ctrl alone)
        let hasCtrlOption = hasControl && hasOption
        
        switch event.keyCode {
        // Left arrow - horizontal, RTL-invertible
        case KeyCode.leftArrow:
            if hasCtrlOption {
                return .navigateNStep(.backward)
            } else if hasControl {
                return .navigateSource(.backward)
            } else if isFavoritesMode {
                return .navigateFavorite(.backward)
            } else {
                return .navigate(.backward)
            }
            
        // Right arrow - horizontal, RTL-invertible
        case KeyCode.rightArrow:
            if hasCtrlOption {
                return .navigateNStep(.forward)
            } else if hasControl {
                return .navigateSource(.forward)
            } else if isFavoritesMode {
                return .navigateFavorite(.forward)
            } else {
                return .navigate(.forward)
            }
        
        // Up arrow - vertical, NOT RTL-invertible (#106)
        case KeyCode.upArrow:
            if hasControl {
                return .navigateSource(.backward)
            } else if isFavoritesMode {
                return .navigateFavorite(.backward)
            } else {
                return .navigate(.backward)  // Note: caller must NOT apply RTL inversion
            }
            
        // Down arrow - vertical, NOT RTL-invertible (#106)
        case KeyCode.downArrow:
            if hasControl {
                return .navigateSource(.forward)
            } else if isFavoritesMode {
                return .navigateFavorite(.forward)
            } else {
                return .navigate(.forward)  // Note: caller must NOT apply RTL inversion
            }
            
        case KeyCode.escape:
            return .close
            
        default:
            break
        }
        
        // Character keys
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }
        
        switch chars {
        // A - horizontal, RTL-invertible
        case "a":
            if hasCtrlOption {
                return .navigateNStep(.backward)
            } else if hasControl {
                return .navigateSource(.backward)
            } else if isFavoritesMode {
                return .navigateFavorite(.backward)
            } else {
                return .navigate(.backward)
            }
        
        // D - horizontal, RTL-invertible
        case "d":
            if hasCtrlOption {
                return .navigateNStep(.forward)
            } else if hasControl {
                return .navigateSource(.forward)
            } else if isFavoritesMode {
                return .navigateFavorite(.forward)
            } else {
                return .navigate(.forward)
            }
        
        // W - vertical, NOT RTL-invertible (#106)
        case "w":
            if hasControl {
                return .navigateSource(.backward)
            } else if isFavoritesMode {
                return .navigateFavorite(.backward)
            } else {
                return .navigate(.backward)  // Note: caller must NOT apply RTL inversion
            }
            
        // S - vertical, NOT RTL-invertible (#106)
        case "s":
            if hasControl {
                return .navigateSource(.forward)
            } else if isFavoritesMode {
                return .navigateFavorite(.forward)
            } else {
                return .navigate(.forward)  // Note: caller must NOT apply RTL inversion
            }
            
        case "z":
            if hasCtrlOption {
                return .navigateFavoriteNStep(.backward)
            }
            return .navigateFavorite(.backward)
            
        case "c":
            if hasCtrlOption {
                return .navigateFavoriteNStep(.forward)
            }
            return .navigateFavorite(.forward)
            
        case "v":
            return .toggleSinglePageMarker
            
        case "x":
            return .toggleSelection
            
        case "q":
            return .close  // Mode-specific handling for FavoritesMode done at call site
            
        case "r":
            if hasControl {
                return .toggleReadingDirection
            } else {
                return .exitToFiler
            }
            
        default:
            return nil
        }
    }
}

// MARK: - Bookmark Dialog Helper (#62)

/// Utility for bookmark add/delete dialogs
/// Uses NSAlert for consistency across all viewer modes
struct BookmarkDialogHelper {
    
    /// Show add bookmark dialog
    /// - Parameters:
    ///   - defaultName: Default name (typically filename)
    ///   - window: Parent window (nil for app-modal)
    ///   - completion: Called with the name if confirmed, nil if cancelled
    static func showAddDialog(
        defaultName: String,
        window: NSWindow? = nil,
        completion: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Add Bookmark (栞)"
        alert.informativeText = "Enter a name for this bookmark:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = defaultName
        textField.isEditable = true
        textField.isSelectable = true
        textField.selectText(nil)
        alert.accessoryView = textField
        
        // Make text field first responder
        alert.window.initialFirstResponder = textField
        
        let response: NSApplication.ModalResponse
        if let window = window {
            alert.beginSheetModal(for: window) { modalResponse in
                if modalResponse == .alertFirstButtonReturn {
                    let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(name.isEmpty ? defaultName : name)
                } else {
                    completion(nil)
                }
            }
            return
        } else {
            response = alert.runModal()
        }
        
        if response == .alertFirstButtonReturn {
            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(name.isEmpty ? defaultName : name)
        } else {
            completion(nil)
        }
    }
    
    /// Show delete bookmark confirmation dialog
    /// - Parameters:
    ///   - bookmarkName: Name of the bookmark to delete
    ///   - window: Parent window (nil for app-modal)
    ///   - completion: Called with true if confirmed
    static func showDeleteDialog(
        bookmarkName: String,
        window: NSWindow? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Delete Bookmark"
        alert.informativeText = "Delete bookmark \"\(bookmarkName)\"?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        let response: NSApplication.ModalResponse
        if let window = window {
            alert.beginSheetModal(for: window) { modalResponse in
                completion(modalResponse == .alertFirstButtonReturn)
            }
            return
        } else {
            response = alert.runModal()
        }
        
        completion(response == .alertFirstButtonReturn)
    }
    
    /// Handle Shift+S action: add or delete bookmark at current index
    /// - Parameters:
    ///   - sourceURL: Source URL
    ///   - imageIndex: Current image index
    ///   - defaultName: Default bookmark name (filename)
    ///   - window: Parent window for sheet dialog
    ///   - onChanged: Called after bookmark is added or deleted
    static func handleShiftS(
        sourceURL: URL,
        imageIndex: Int,
        defaultName: String,
        window: NSWindow? = nil,
        onChanged: (() -> Void)? = nil
    ) {
        if let existing = CacheManager.shared.getBookmark(for: sourceURL, at: imageIndex) {
            // Delete existing bookmark
            showDeleteDialog(bookmarkName: existing.name, window: window) { confirmed in
                if confirmed {
                    CacheManager.shared.removeBookmark(for: sourceURL, id: existing.id)
                    Logger.bookmark.debug("Deleted '\(existing.name)' at index \(imageIndex, privacy: .public)")
                    onChanged?()
                }
            }
        } else {
            // Add new bookmark
            showAddDialog(defaultName: defaultName, window: window) { name in
                if let name = name {
                    CacheManager.shared.addBookmark(for: sourceURL, at: imageIndex, name: name)
                    Logger.bookmark.debug("Added '\(name)' at index \(imageIndex, privacy: .public)")
                    onChanged?()
                }
            }
        }
    }
}

// MARK: - Bookmark List Key Handler (#62 Phase 5)

/// Shared key handling logic for bookmark list overlay
struct BookmarkListKeyHandler {
    enum Action {
        case moveCursor(Int)
        case selectAndClose(Int)  // imageIndex to jump to
        case close
        case consumed  // key consumed but no action needed
    }
    
    /// Handle a key event while bookmark list is showing
    static func handle(event: NSEvent, bookmarks: [Bookmark], cursor: Int) -> Action {
        // Special keys first
        switch event.keyCode {
        case 53: // ESC
            return .close
        case 36: // Enter
            guard !bookmarks.isEmpty, cursor >= 0, cursor < bookmarks.count else { return .close }
            return .selectAndClose(bookmarks[cursor].imageIndex)
        case 126, 123: // Up, Left
            guard !bookmarks.isEmpty else { return .consumed }
            return .moveCursor(max(0, cursor - 1))
        case 125, 124: // Down, Right
            guard !bookmarks.isEmpty else { return .consumed }
            return .moveCursor(min(bookmarks.count - 1, cursor + 1))
        default:
            break
        }
        
        // Character keys
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return .consumed
        }
        
        switch chars {
        case "w":
            guard !bookmarks.isEmpty else { return .consumed }
            return .moveCursor(max(0, cursor - 1))
        case "s":
            guard !bookmarks.isEmpty else { return .consumed }
            return .moveCursor(min(bookmarks.count - 1, cursor + 1))
        case "q":
            return .close
        case "b":
            if event.modifierFlags.contains(.shift) {
                return .close  // Toggle off
            }
            return .consumed
        default:
            return .consumed
        }
    }
}

// MARK: - Bookmark List Overlay View (#62 Phase 5)

/// Shared overlay view for displaying bookmark list
struct BookmarkListOverlayView: View {
    let bookmarks: [Bookmark]
    let selectedCursor: Int
    let onSelect: (Int) -> Void  // called with imageIndex
    let onClose: () -> Void
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            // Center panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(.orange)
                    Text("Bookmarks (栞)")
                        .font(.headline)
                    Spacer()
                    Text("ESC to close")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                Divider()
                
                if bookmarks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bookmark")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No bookmarks")
                            .foregroundStyle(.secondary)
                        Text("Press Shift+S to add a bookmark")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(bookmarks.enumerated()), id: \.element.id) { index, bookmark in
                                    HStack {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                        Text(bookmark.name)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("page \(bookmark.imageIndex + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(index == selectedCursor ? Color.accentColor.opacity(0.3) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelect(bookmark.imageIndex)
                                    }
                                    .id(index)
                                }
                            }
                        }
                        .onAppear {
                            // Scroll to selected cursor on appear
                            if selectedCursor > 0 {
                                proxy.scrollTo(selectedCursor, anchor: .center)
                            }
                        }
                        .onChange(of: selectedCursor) { _, newIndex in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 400, maxHeight: 500)
            .background(.regularMaterial)
            .cornerRadius(12)
            .shadow(radius: 20)
        }
    }
}
