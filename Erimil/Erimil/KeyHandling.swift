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
import AppKit

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
        
        switch event.keyCode {
        // Arrow keys
        case KeyCode.leftArrow, KeyCode.upArrow:
            if hasControl {
                return .navigateSource(.backward)
            } else if isFavoritesMode {
                return .navigateFavorite(.backward)
            } else {
                return .navigate(.backward)
            }
            
        case KeyCode.rightArrow, KeyCode.downArrow:
            if hasControl {
                return .navigateSource(.forward)
            } else if isFavoritesMode {
                return .navigateFavorite(.forward)
            } else {
                return .navigate(.forward)
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
        case "a", "w":
            if hasControl {
                return .navigateSource(.backward)
            } else if isFavoritesMode {
                return .navigateFavorite(.backward)
            } else {
                return .navigate(.backward)
            }
            
        case "d", "s":
            if hasControl {
                return .navigateSource(.forward)
            } else if isFavoritesMode {
                return .navigateFavorite(.forward)
            } else {
                return .navigate(.forward)
            }
            
        case "z":
            return .navigateFavorite(.backward)
            
        case "c":
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
