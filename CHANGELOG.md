# Changelog

All notable changes to Erimil will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.6] - 2026-05-18

### Added
- **Sort feature**: Sort thumbnails by name, date modified, or file size with ascending/descending toggle via menu (#267)
- **Sort localization**: Japanese locale support for sort menu labels (名前 / 更新日 / サイズ / 昇順 / 降順)
- **Source/View layer framework**: Design philosophy documentation for separating source data order from view presentation order (DESIGN-PHILOSOPHY.md)

### Fixed
- **xcstrings key alignment**: Corrected localization key names to match `String(localized:)` references, preventing silent English fallback in non-English locales

### Known Issues
- Bookmark divider may not display correctly under date or size sort (#276)

## [0.3.5] - 2026-04-25

### Added
- **Edge-click chevron overlay navigation**: Click left/right screen edges to navigate between images in Viewer and Slide Modes (#255)
- **Source N-step navigation**: Option+W/S to jump by configurable step count between sources (#259, #260)
- **i18n infrastructure**: Localization framework with 240 keys (#244)

### Changed
- **N-step key binding**: Ctrl+Option+←/→ → Option+←/→ for file/favorite N-step navigation (#257)
- **Grid view architecture**: Migrated thumbnail grid from SwiftUI Grid to NSCollectionView (#215)

### Performance
- **Folder TileSheet caching**: Folder sources now use the same prefetch → TileSheet pipeline as ZIP/PDF archives (#236)

### Fixed
- **N-step navigation rendering**: Apply render gate to N-step and favorite N-step navigation in Viewer and Slide Modes (#263)
- **Startup delay**: Removed synchronous filesystem walk from sidebar body; startup improved by 15-24× (#265)

## [0.3.4] - 2026-03-21

### Added
- **Auto-Slide mode**: Automatic image slideshow with multi-speed tap control in Slide and Viewer Modes (#172)
- **Auto-Slide reverse playback**: Shift+Space for reverse direction (#178)
- **Animated image support (Phase 1)**: GIF playback in Viewer and Slide Modes with Space pause/resume and L key loop toggle; animated indicator badge in Grid (#201)
- **Metadata inspector**: "i" key opens draggable/resizable NSPanel with image metadata in Viewer and Slide Modes (#140)
- **Grid spacing setting**: Configurable thumbnail gap via Settings slider (#212)
- **Thumbnail quality presets**: Unified thumbnail size/quality with Retina support and Settings UI (#207)
- **N-step navigation**: Ctrl+Option jump by configurable step count for files and favorites, with Settings UI (#143)
- **Cmd+A select/deselect all** in Grid View (#164)
- **3-level overlay controls** in Slide Mode — Space key cycles through visibility levels (#151)
- **Auto-hide mouse cursor** in Slide Mode (#145)
- **Render-gated navigation**: Z/C favorite navigation waits for frame render before accepting next input (#154)
- **R key opens Viewer** from currently focused thumbnail instead of last bookmark (#185)
- **Spread thumbnail improvements**: Tightened pair gap with 1px center divider and focus border fix (#187)
- **Tile-based thumbnail cache** for ZIP and PDF archives — debounce-based generation, content-based hash, Finder obfuscation (#24)
- **Hyperscaler PoC**: CoreML Real-ESRGAN super-resolution experiment (#40)

### Changed
- **Thumbnail cache format**: Migrated to CGImageDestination + `.ecache` format for size optimization (#146)
- **QuickLook removed**: Space key no longer opens QuickLook in Grid View; deprecated in favor of Auto-Slide (#176)
- **ThumbnailGridView split**: Refactored into 4 files — ViewerView, ExportConfirmationView, key handling extracted (#175)
- **Key handling consolidated**: ThumbnailGridView.handleKeyEvent integrated into CommonKeyParser (#169)

### Fixed
- **Export data loss prevention**: Block overwrite when NSSavePanel targets same filename (#161)
- **Export empty file prevention**: Block export when all items are excluded (#163)
- **Grid scroll tracking**: Scroll follows focus in real-time during keyboard navigation (#158)
- **Viewer Mode spread layout**: Debounced re-evaluation + unknown aspect ratio treated as single page (#144)
- **Ctrl+R in Slide Mode**: RTL toggle now refreshes display immediately (#150)
- **Double-click thumbnail**: Single click sets focus only, double-click enters Viewer Mode correctly (#194)
- **Export confirmation**: Sheet now always appears regardless of selection state (#195)
- **Grid focus restoration**: Scroll position restored when exiting Viewer Mode (#193)
- **Source switch spinner**: Prevent stale timer from firing after source switch (#196)

### Performance
- **Startup time 8,300× faster**: Lazy tree loading for FolderNode (16.7s → 2ms) + async CacheManager initialization (#216)
- **Selection tap delay**: Removed selectedPaths from `.id()` to avoid view recreation; ThumbnailCoalescer reduces body re-evaluations by 95-98% (#138)
- **PDF memory cache**: Added memory cache to PDFManager.fullImage() with double-checked locking (#165)
- **Thumbnail disk cache**: Synchronous disk cache check in loadThumbnailIfNeeded; 1-frame navigation gate prevents key-repeat page skip (#160)
- **Archive tile sheets**: Preload in listImageEntries, fix race condition with serial queue, fix preload block placement (#24)

## [0.3.3] - 2026-01-31

### Added
- **PDF support**: View PDF documents as image sequences, each page treated as an image (S024)
- **Spread (two-page) view**: Display two pages side-by-side for books (#55)
  - Auto-detect wide images as single pages
  - Manual single page markers via V key (#56)
  - Configurable aspect ratio threshold
- **RTL (right-to-left) support**: Reading direction setting for Japanese vertical text (#54, #76)
  - Per-source reading direction memory
  - Navigation keys inverted in RTL mode
- **ViewerView**: In-grid image viewer with thumbnail sidebar (S014)
  - Thumbnail position: left, bottom, or hidden (Ctrl+T to cycle)
  - Spread-aware navigation integrated
- **Image prefetcher**: Direction-aware image prefetching for smooth navigation (S016)
  - LRU cache with configurable size
  - Cancellable prefetch tasks
- **Aspect ratio cache**: In-memory cache for spread detection (#67)

### Changed
- Source settings now stored per-source (lastPosition, readingDirection, singlePageIndices)
- Spread navigation calculates step size based on current display mode

### Technical
- `PDFManager.swift` - ImageSource implementation for PDFs
- `SpreadImageViewer.swift` - Double-buffered spread view with RTL support
- `ImagePrefetcher.swift` - LRU cache with direction-aware prefetching
- `SpreadNavigationHelper` - Utility for spread-aware calculations
- CacheManager extended with aspect ratio caching

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
| 0.3.6 | 2026-05-18 | Phase 2.5 | Sort by name/date/size, Source/View layer framework |
| 0.3.5 | 2026-04-25 | Phase 2.5 | i18n infrastructure, NSCollectionView migration, edge-click navigation, startup 24× faster |
| 0.3.4 | 2026-03-21 | Phase 2.4 | Startup 8300×, Auto-Slide, GIF playback, tile cache, metadata inspector |
| 0.3.3 | 2026-01-31 | Phase 2.3 | PDF support, Spread view, RTL, ViewerView |
| 0.3.2 | 2025-12-31 | Phase 2.2 | Fullscreen source navigation, F key shortcut |
| 0.3.0 | 2025-12-16 | Phase 2.1 | UX improvements, favorites, keyboard nav |
| 0.2.0 | 2025-12-14 | Phase 2 | Folder viewer, settings, selection modes |
| 0.1.0 | 2025-12-13 | Phase 1 | MVP - ZIP viewer and export |


[Unreleased]: https://github.com/zembutsu/erimil/compare/v0.3.6...HEAD
[0.3.6]: https://github.com/zembutsu/erimil/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/zembutsu/erimil/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/zembutsu/erimil/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/zembutsu/erimil/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/zembutsu/erimil/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/zembutsu/erimil/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/zembutsu/erimil/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/zembutsu/erimil/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/zembutsu/erimil/releases/tag/v0.1.0
