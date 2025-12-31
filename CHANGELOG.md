# Changelog

All notable changes to Erimil will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.2] - 2025-12-31

### Added
- **Source navigation in Slide Mode**: Ctrl+A/D to navigate between ZIP files and folders while staying in fullscreen (Phase 2.2)
- **Direct Slide Mode entry**: F key from grid view launches fullscreen directly, skipping Quick Look (Phase 2.2)
- `SourceNavigator.swift` - Helper for computing next/previous source

### Known Issues
- Empty source handling: Navigation to folders with 0 images causes key events to stop responding (#21)

### Technical
- SlideWindowController now supports source switching callbacks
- Architecture documentation updated

## [0.3.1] - 2025-12-27

### Added
- **Quick Look mode**: Space key opens preview in sheet window (Phase 2.2)
- **Slide Mode**: f key opens fullscreen presentation view (Phase 2.2)
- **Image navigation**: a/d and arrow keys to browse images in preview (Phase 2.2)
- **Favorite navigation**: z/c keys to jump between favorite images (Phase 2.2)
- **Position indicator**: Shows current position (1/N) in both preview modes (Phase 2.2)
- **Auto-hide controls**: Slide Mode controls hide automatically, toggle with Space (Phase 2.2)
- `ImageViewerCore.swift` - Shared image viewer component
- `SlideWindowController.swift` - Fullscreen window management

### Technical
- D005: Mode Definitions & Component Architecture decision recorded

## [0.3.0] - 2025-12-16

### Added
- **Thumbnail size adjustment**: Configurable in Settings, UI slider in toolbar
- **Cache infrastructure**: Hash-based thumbnail caching in Application Support
- **Keyboard navigation**: wasd/arrow keys for grid navigation, x for selection toggle
- **Space key preview**: Quick preview without double-click
- **Favorite feature**: 
  - ★ (direct) / ☆ (inherited) hybrid system
  - v key to toggle favorite
  - Delete protection for favorited images
  - Content-hash based: same image recognized across different ZIPs
- **Folder restoration**: Remembers last opened folder using Security-Scoped Bookmarks
- **Session logging**: Development logs in `docs/logbook/`

### Fixed
- Black screen on first image preview (#7) - resolved via cache timing improvements

### Technical
- Security-Scoped Bookmarks for sandbox-compatible folder persistence
- `loadID` pattern for async race condition prevention
- `favoritesVersion` pattern for SwiftUI state refresh

## [0.2.0] - 2025-12-14

### Added
- **Folder viewer**: Browse images in folders, not just ZIP archives
- **Folder operations**: Create ZIP from selected images, delete to Trash
- **Settings panel**: Accessible via ⌘, (Erimil > Settings)
  - Selection mode default (除外モード / 選出モード)
  - Default output folder configuration
- **Selection mode toggle**: Click header badge to switch modes
  - 除外モード (Exclude): Selected images are excluded from output
  - 選出モード (Keep): Only selected images are included in output
- **Finder-style navigation**: 
  - ▶ for expand/collapse folders
  - Row click to display contents
- **ImageSource abstraction**: Unified interface for ZIP and folder browsing
- **LOGBOOK.md**: Navigation log for decisions, insights, and learnings

### Changed
- Renamed "保持モード" to "選出モード" for consistency with app name
- Selection state moved to ContentView for accurate unsaved changes detection
- Footer now shows output/exclude counts based on current mode

### Fixed
- False positive "unsaved changes" warning when no images selected
- Mode toggle now preserves user selections

## [0.1.0] - 2025-12-13

### Added
- **Initial MVP release**
- Folder tree navigation with ZIP file recognition
- Thumbnail grid display with lazy loading
- Click-to-exclude selection (red border + ✕ overlay)
- Double-click image preview (modal sheet)
- Export to `_opt.zip` (excludes marked images)
- Unsaved changes confirmation dialog
- Auto-reload folder tree after export

### Technical
- SwiftUI-based UI
- ZIPFoundation for archive operations
- macOS 14+ (Sonoma) required

---

## Version History

| Version | Date | Phase | Highlights |
|---------|------|-------|------------|
| 0.3.2 | 2025-12-31 | Phase 2.2 | Fullscreen source navigation, F key shortcut |
| 0.3.0 | 2025-12-16 | Phase 2.1 | UX improvements, favorites, keyboard nav |
| 0.2.0 | 2025-12-14 | Phase 2 | Folder viewer, settings, selection modes |
| 0.1.0 | 2025-12-13 | Phase 1 | MVP - ZIP viewer and export |

[Unreleased]: https://github.com/zembutsu/erimil/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/zembutsu/erimil/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/zembutsu/erimil/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/zembutsu/erimil/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/zembutsu/erimil/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/zembutsu/erimil/releases/tag/v0.1.0
