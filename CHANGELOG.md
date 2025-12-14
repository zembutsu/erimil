# Changelog

All notable changes to Erimil will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
| 0.2.0 | 2025-12-14 | Phase 2 | Folder viewer, settings, selection modes |
| 0.1.0 | 2025-12-13 | Phase 1 | MVP - ZIP viewer and export |

[Unreleased]: https://github.com/zembutsu/erimil/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/zembutsu/erimil/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/zembutsu/erimil/releases/tag/v0.1.0
