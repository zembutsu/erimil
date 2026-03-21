# Erimil Architecture

This document describes the internal architecture of Erimil.

## Overview

Erimil is a macOS application built with SwiftUI that provides visual management of images in ZIP archives, folders, and PDF documents. Users can browse folders, select ZIP files, image folders, or PDFs, preview contained images, mark items for exclusion/selection, and generate optimized archives or manage files.

```
┌─────────────────────────────────────────────────────────────┐
│                        Erimil                               │
├─────────────────┬───────────────────────────────────────────┤
│   Folder Tree   │          Thumbnail Grid                   │
│                 │                                           │
│  📁 Photos      │   [img1] [img2] [img3] [img4]            │
│   ├─ 📁 2024/   │   [img5] [img6] [img7] [img8]            │
│   │  └─ 📦a.zip │                                           │
│   │  └─ 📄b.pdf │   Double-click to preview                │
│   └─ 📁 2023/   │   ┌──────────────────────┐               │
│      └─ 📦c.zip │   │ [除外モード] 8 画像  │               │
├─────────────────┴───┴──────────────────────┴────────────────┤
│  出力: 5件 / 除外: 3件                                      │
│  [選択をクリア]                        [確定 → _opt.zip]    │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. ImageSource Layer (Protocol Abstraction)

Unified interface for different image sources (→ DESIGN.md Decision 8).

- **ImageSource**: Protocol defining common interface for image browsing
- **ImageEntry**: Model representing single image from any source
- **ImageSourceType**: Enum for source type identification
  - `.archive` - ZIP files
  - `.folder` - Directories
  - `.pdf` - PDF documents (S024)

### 2. Archive Layer

Manages ZIP file reading and writing.

- **ArchiveManager**: ImageSource implementation for ZIP archives
  - Uses ZIPFoundation for ZIP operations
  - Opens Archive per-operation (official pattern)
  - Handles export with exclusions
- **ZIPEncodingDetector**: Detects and handles various filename encodings in ZIP files

### 3. Folder Layer

Manages folder image browsing and operations.

- **FolderManager**: ImageSource implementation for folders
  - Direct FileManager access
  - ZIP creation from selected images
  - Delete to Trash functionality

### 4. PDF Layer (S024)

Manages PDF document viewing as image sequences.

- **PDFManager**: ImageSource implementation for PDF documents
  - Each PDF page treated as an ImageEntry
  - Lazy page rendering for performance
  - Memory cache with double-checked locking for `fullImage()` (#165)
  - Uses system PDFKit (no external dependencies)
  - Export: optimized PDF (_opt.pdf) with page exclusion (#100)
  - Export: individual PNG pages at 300dpi (#100)
  - PDFExportError for structured error handling

### 5. Navigation Layer

Handles folder browsing and source discovery.

- **SidebarView**: Finder-style tree navigation (→ DESIGN.md Decision 9)
  - ▶ for expand/collapse
  - Single-click for content display
  - Double-click to open Slide Mode directly
- **FolderNode**: Model representing folder/ZIP/PDF in tree
  - `isZip`: ZIP file indicator
  - `isPdf`: PDF file indicator (S024)
  - Children are always `nil` — tree structure lives in `SidebarView.childrenCache` (#216)
  - Lazy loading: only root's direct children loaded on startup (1 `contentsOfDirectory` call)
  - Deeper levels loaded on-demand via DisclosureGroup expansion

### 6. Selection Layer

Tracks user selections and pending changes.

- **selectedPaths**: Set<String> in ContentView (source of truth)
- **AppSettings**: Selection mode (exclude/keep), output folder defaults

### 7. Cache Layer

Manages thumbnails, metadata, and aspect ratio information.

- **CacheManager**: Singleton for all caching operations
  - **Async initialization**: All data loads dispatched to background queue on startup; completes in ~143ms (#216)
  - **Thumbnail cache**: contentHash → NSImage (memory, with disk persistence)
  - **Path index**: pathHash → contentHash mapping
  - **Favorites storage**: Per-source favorites with hybrid format
  - **Source settings**: Per-source lastPosition, readingDirection, singlePageIndices (#54, #56)
  - **Bookmarks storage**: Per-source bookmarks with name, imageIndex, createdAt (#62)
  - **Aspect ratio cache**: In-memory cache for spread detection (#67 Phase 3)
    - `cacheAspectRatio(for:path:ratio:)` - Store aspect ratio
    - `getCachedAspectRatio(for:path:)` - Retrieve cached ratio
    - `isWideImage(for:path:threshold:)` - Check if image is wide (default threshold: 1.3)
    - `clearAspectRatioCache()` - Clear on source change
  - **Lock discipline**: JSON decode outside NSLock, lock only for assignment (#216)

- **TileSheetCache**: Tile-based thumbnail cache for archives (#24)
  - Debounce-based tile sheet generation for ZIP and PDF archives
  - Content-based archive hash (not path-based) for cache identity
  - Finder obfuscation for `.ecache` files
  - Preloaded in `listImageEntries()` via serial `accessQueue.sync`
  - Race condition prevention via serial queue pattern (D004)

- **ThumbnailCoalescer**: Batch thumbnail assignment to reduce SwiftUI re-evaluations (#138)
  - Collects thumbnail updates over a short window
  - Applies batch update in single body re-evaluation
  - Reduces re-evaluations by 95-98%

### 8. Spread Navigation Layer (S020/S021)

Handles spread (two-page) display logic and navigation.

- **SpreadNavigationHelper**: Utility enum for spread-aware calculations
  - `shouldShowSinglePage(for:at:totalCount:entries:)` - Determines single vs spread display
  - `navigationStep(for:at:totalCount:)` - Returns step size (1 or 2)
  - Considers: spread mode setting, single page markers, wide image detection
- **SpreadImageViewer**: SwiftUI view with double buffering
  - Instant page transitions (no flicker)
  - RTL (right-to-left) layout support for Japanese vertical text
  - Auto-detect wide images as single pages
  - Manual single page markers via V key

### 9. View Layer

SwiftUI views for user interaction.

- **ContentView**: Main split view, owns selection state
- **ThumbnailGridView**: Grid display with mode-aware styling
  - **ThumbnailDisplayItem**: Enum for display item types (#69)
    - `.single(Int)` - Single thumbnail
    - `.spread(leftIndex:rightIndex:)` - Spread pair
  - **GridSection**: Section model for bookmark dividers (#62)
    - Orange bookmark icon + section name + divider line
    - Pinned section headers during scroll
  - **ThumbnailSidebarView**: Vertical/horizontal thumbnail strip (S014)
- **ThumbnailComponents.swift**: Extracted thumbnail subviews (#175 Phase 1)
  - **SpreadThumbnailPairView**: Paired thumbnail display for spreads (#69)
    - `.fill` + `.clipped()` rendering with `floor()` for consistent sizing (#187)
    - 1px gap divider between pages (#187)
  - **Animated indicator badge**: [▶] overlay on GIF entries in Grid (#201)
- **ViewerView**: In-grid image viewer with thumbnail sidebar (#175 Phase 1: separate file)
  - Configurable thumbnail position (left/bottom/hidden via Ctrl+T)
  - Spread-aware navigation integrated
  - Uses SpreadImageViewer for image display
  - Auto-Slide support (Space/Shift+Space, shared AutoSlideTapHandler)
  - Animated GIF playback overlay (Space pause/resume, L loop toggle) (#201)
  - Render-gated navigation: waits for frame render before accepting next input (#154)
- **ExportConfirmationView**: Export sheet with metadata options (#105, #175 Phase 1: separate file)
  - Data loss prevention: blocks overwrite of same filename (#161)
  - Blocks export when all items are excluded (#163)
- **MetadataInspectorPanel**: NSPanel-based draggable/resizable metadata display (#140)
  - "i" key toggles in Viewer and Slide Modes
  - Shows image dimensions, file size, color space, format
  - Position and size persisted across sessions
- **AnimatedImageContent**: Data model + CGImageSource-based GIF decoder (#201)
- **AnimationPlayer**: CADisplayLink-based playback engine with retain cycle fix (#201)
- **ThumbnailCell**: Individual thumbnail with selection overlay
- **ImagePreviewView**: Quick Look modal preview — *deprecated, replaced by Auto-Slide (#176)*
- **SettingsView**: Settings panel (⌘,)
  - Grid spacing slider (#212)
  - Thumbnail quality presets with Retina support (#207)
  - N-step navigation step count (#143)
  - Auto-Slide loop setting

### 10. Slide Mode Layer

Fullscreen image viewing with Favorites Mode and source navigation.

- **SlideWindowController**: Singleton managing fullscreen window
  - NSWindow with NSHostingView for SwiftUI integration
  - Centralized key handling via `NSEvent.addLocalMonitorForEvents`
  - State sync to View via NotificationCenter
  - Empty source support with "No images" display
  - Auto-Slide: automatic page advance with tap-counted speed (#172/#178)
    - Space × 1/2/3 = Normal/Fast/Turbo, Shift+Space = reverse
    - Favorites Mode: advances through ★ only
    - Loop at source boundary (configurable)

- **Keyboard Handling**:
  | Key | Normal Mode | Favorites Mode |
  |-----|-------------|----------------|
  | ←/→, A/D | Previous/Next image (RTL-aware) | Previous/Next favorite (RTL-aware) |
  | ↑/↓, W/S | Previous/Next image (RTL-aware) | Previous/Next favorite (RTL-aware) |
  | Z/C | Previous/Next favorite (RTL-aware) | Previous/Next favorite (RTL-aware) |
  | Ctrl+A/D | Jump to first/last image | Same |
  | Ctrl+Z/C | Jump to first/last favorite | Same |
  | Ctrl+Option+←/→ | N-step jump (configurable) (#143) | Same |
  | Cmd+1/2/3/4/5 | Jump to 0%/25%/50%/75%/100% | Same |
  | Tab | Next ★ + enter mode | Next ★ |
  | F | Toggle favorite | Toggle favorite |
  | X | Toggle selection | Toggle selection |
  | V | Toggle single page marker | Toggle single page marker |
  | I | Toggle metadata inspector (#140) | Same |
  | L | Toggle loop (animated GIF only) (#201) | Same |
  | Q | Exit fullscreen | Exit Favorites Mode |
  | Esc | Exit fullscreen | Exit fullscreen |
  | Ctrl+W/S, Ctrl+↑/↓ | Previous/Next source | Same |
  | Ctrl+T | Cycle thumbnail position | Same |
  | Ctrl+R | Toggle reading direction | Same |
  | Shift+S | Add/delete bookmark (栞) | Same |
  | Shift+A/D | Previous/Next bookmark (RTL-aware) | Same |
  | Shift+B | Bookmark list overlay | Same |
  | Space | Auto-Slide start/stop (#172) | Same |
  | Space (animated) | Pause/resume GIF playback (#201) | Same |
  | Shift+Space | Reverse Auto-Slide (#178) | Same |
  | O | Toggle controls overlay | Same |

- **Favorites Mode State**:
  - `isFavoritesMode: Bool` in SlideWindowController
  - Visual: Yellow gradient header + ★ FAVORITES badge
  - Badge persists even when controls are hidden

- **SourceNavigator**: Utility for sibling source discovery
  - Lists ZIPs, PDFs, and image-containing folders in parent directory
  - Supports looping navigation (last→first, first→last)
  - `positionInfo(for:)` returns current position among siblings

- **SourcePositionIndicator**: Visual indicator for source position
  - Dot bar for ≤12 sources (individual dots)
  - Proportional bar for >12 sources (highlighted segment)
  - Fixed width (144px) aligned with ImagePositionBar

- **ImagePositionBar**: Image position within current source
  - Progress bar with current position marker
  - ★ markers for favorites (yellow)
  - × markers for selections (red)
  - Always shown for consistent layout (even with 1 image)

### 11. Key Handling Layer (S031)

Consolidated key handling logic shared across viewer modes.

- **KeyHandling.swift**: Centralized key handling utilities
  - `NavigationDirection`: Forward/backward enum with RTL inversion
  - `KeyAction`: All possible key actions enum
  - `NavigationHelper`: RTL and spread-aware navigation calculations
    - `navigate(direction:from:entries:sourceURL:isRTL:)` - Main navigation
    - `navigateFavorite(direction:from:favoriteIndices:isRTL:)` - Favorite navigation
    - `indexForPercent(_:totalCount:)` - Percentage-based position jump
    - `lastIndex(totalCount:)` - Get last valid index
    - `nextIndex/previousIndex` - Spread-aware index calculation
  - `KeyCode`: macOS key code constants
  - `CommonKeyParser`: Shared key event parsing
  - `BookmarkDialogHelper`: NSAlert-based add/delete dialogs for bookmarks (#62)
  - `BookmarkListKeyHandler`: Shared key handling for bookmark list overlay (#62 Phase 5)
  - `BookmarkListOverlayView`: SwiftUI overlay for bookmark list display (#62 Phase 5)
  - `AutoSlideTapHandler`: Shared tap-counting state machine for Auto-Slide (#175 Phase 2)
    - Used by both ViewerView and SlideWindowController
    - Encapsulates "tap N times within 0.3s" → mode 1-3 (Normal/Fast/Turbo)

- **Mode-Specific Handlers**:
  | Mode | Handler Location | Notes |
  |------|-----------------|-------|
  | Grid (Filer) | CommonKeyParser (via ThumbnailGridView) | RTL-aware nav, Z/C favorite, Ctrl+A/D/1-5 jump, Cmd+A select all (#164), render-gated Z/C (#154) |
  | Viewer | ViewerView.handleKeyEvent | Full navigation + Z/C + jump + I metadata + L loop |
  | Slide | SlideWindowController.handleKeyEvent | Event monitor based |

- **RTL Navigation**:
  All navigation keys (←/→, ↑/↓, A/D, W/S, Z/C, Shift+A/D) are RTL-aware.
  When reading direction is RTL, logical direction is inverted.

- **Bookmark Navigation** (Shift+S/A/D/B):
  Mnemonic: Shift = Shiori (栞, bookmark). All bookmark operations use Shift modifier.
  - Shift+S = Add/delete bookmark at current position
  - Shift+A = Previous bookmark, Shift+D = Next bookmark (RTL-aware, wrapping)
  - Shift+B = Toggle bookmark list overlay (↑↓/W/S to browse, Enter to jump, ESC to close)

- **Position Jump** (Ctrl+A/D, Cmd+1-5):
  One-handed navigation for quick position access.
  - Ctrl+A = first, Ctrl+D = last
  - Ctrl+Z = first favorite, Ctrl+C = last favorite
  - Cmd+1/2/3/4/5 = 0%/25%/50%/75%/100%

## Data Flow

### Opening a Source (ZIP, Folder, or PDF)

```
User selects root folder
    ↓
SidebarView.reloadTree() — loads root's direct children only (1ms) (#216)
    ↓
Tree structure stored in SidebarView.childrenCache (not FolderNode)
    ↓
DisclosureGroup expansion triggers loadChildrenFor() on demand
    ↓
User clicks ZIP, folder, or PDF row
    ↓
ContentView creates ImageSource:
  - ZIP → ArchiveManager
  - Folder → FolderManager
  - PDF → PDFManager
    ↓
ThumbnailGridView calls listImageEntries()
    ↓
Lazy thumbnail loading (on scroll)
    ↓
Grid displays images
```

### Selecting Items

```
User clicks thumbnail
    ↓
toggleSelection(entry)
    ↓
selectedPaths.insert/remove (ContentView)
    ↓
UI updates:
  - Overlay icon (✕ or ✓)
  - Border color (red or green)
  - Footer summary
```

### Mode-Aware Export/Delete

```
User clicks action button
    ↓
Calculate based on selectionMode:
  - exclude: pathsToRemove = selectedPaths
  - keep: pathsToRemove = allPaths - selectedPaths
    ↓
Initialize exportMetadataOptions from AppSettings defaults (#105)
    ↓
Check affectedFavoriteCount (#103):
  - > 0: Show ExportConfirmationView sheet
    │     ├── ★ warning message (mode-aware)
    │     ├── Metadata checkboxes (★, 栞, 方向, マーカー)
    │     └── User confirms → executePendingExport()
  - = 0: Execute immediately with default options
    ↓
Perform operation:
  - ZIP: exportOptimized(excluding: pathsToRemove)
  - Folder ZIP: createZip(excluding: pathsToRemove)
  - Folder Delete: moveToTrash(paths: pathsToRemoveForDelete)
  - PDF: exportOptimizedPDF(excluding: pathsToRemove)
  - PDF PNG: exportPagesAsPNG(excluding: pathsToRemove)
    ↓
CacheManager.copyMetadata(options: exportMetadataOptions) (#105)
  - Index remapping for surviving entries
  - PDF path remapping (0-based → 1-based)
  - Per-option: ★, 栞, direction, markers
    ↓
selectedPaths.removeAll()
    ↓
Success notification
```

### Navigation with Unsaved Changes

```
User clicks different source (while selectedPaths not empty)
    ↓
Show confirmation dialog:
  - "保存せず移動" → Clear selection, navigate
  - "キャンセル" → Stay on current source
```

### Opening Slide Mode

```
User triggers Slide Mode:
  - Enter key in filer
  - Double-click thumbnail
  - Double-click sidebar item
  - Enter in Quick Look preview
    ↓
ThumbnailGridView sets previewMode = .slideMode(index)
    ↓
SlideWindowController.shared.open()
  - Creates NSWindow
  - Registers event monitor
  - Toggles fullscreen
    ↓
User navigates with keyboard
    ↓
Exit via Q/Esc → SlideWindowController.close()
```

### Favorites Mode Flow

```
User presses Tab in Slide Mode
    ↓
SlideWindowController:
  - isFavoritesMode = true
  - notifyViewOfModeChange()
  - goToNextFavorite()
    ↓
View updates:
  - Yellow gradient header
  - ★ FAVORITES badge
  - Navigation hints change
    ↓
A/D now navigate favorites only
    ↓
User presses Q
    ↓
isFavoritesMode = false
    ↓
View returns to normal mode
```

### Fullscreen Source Navigation

```
User presses Ctrl+D in Slide Mode
    ↓
SlideWindowController handles key event
    ↓
ContentView.navigateToNextSource()
    ↓
SourceNavigator.nextSource(from: currentURL)
  - Scans parent directory
  - Filters for ZIPs, PDFs, and image folders
  - Returns next sibling (with loop)
    ↓
ContentView sets shouldReopenSlideMode = true
    ↓
selectedSourceURL changes
    ↓
ThumbnailGridView.loadSource() detects flag
    ↓
SlideWindowController.updateSource()
  - Creates new SlideView with new entries
  - Replaces window.contentView
  - Fullscreen state preserved
```

### Spread-Aware Thumbnail Display (#69)

```
ThumbnailSidebarView builds display items
    ↓
buildDisplayIndices(isSpreadMode:) called
    ↓
For each index:
  - Check SpreadNavigationHelper.shouldShowSinglePage()
  - If single: append .single(index)
  - If spread: append .spread(left, right), skip next
    ↓
ForEach renders ThumbnailDisplayItem:
  - .single → ThumbnailItemView
  - .spread → SpreadThumbnailPairView
    ↓
SpreadThumbnailPairView:
  - RTL layout: [right|left] (lower index on right)
  - LTR layout: [left|right]
```

### Aspect Ratio Caching (#67 Phase 3)

```
Image loaded (thumbnail or full)
    ↓
Calculate aspect ratio: width / height
    ↓
CacheManager.cacheAspectRatio(for:path:ratio:)
    ↓
SpreadNavigationHelper.shouldShowSinglePage() checks:
  - CacheManager.isWideImage(for:path:)
  - If ratio > 1.3 → wide → show as single
    ↓
Source changes
    ↓
CacheManager.clearAspectRatioCache()
```

## Configuration Values

| Setting | Value | Description |
|---------|-------|-------------|
| `thumbnailMaxSize` | 120px | Default thumbnail size (medium preset) |
| `thumbnailSmall` | 80px | Small preset size |
| `thumbnailLarge` | 180px | Large preset size |
| `maxThumbnailCacheCount` | 200 | Memory cache limit |
| `supportedImageTypes` | jpg, jpeg, png, gif, webp, heic | Recognized image extensions |
| `supportedAnimatedTypes` | gif | Animated image extensions (#201) |
| `positionBarWidth` | 144px | Fixed width for position indicators |
| `wideImageThreshold` | 1.3 | Default aspect ratio threshold for wide image detection |
| `defaultPrefetchCount` | 3 | Default number of images to prefetch |
| `defaultGridSpacing` | 2px | Default thumbnail grid gap (#212) |
| `defaultNStepCount` | 10 | Default N-step navigation step (#143) |
| `animatedFrameLimit` | 500 | Max frames for GIF playback (#201) |

## File Structure

```
Erimil/
├── ErimilApp.swift              # App entry point, Settings scene, CacheManager trigger
├── ContentView.swift            # Main split view, owns selection state
├── SidebarView.swift            # Folder tree navigation (Finder-style, lazy childrenCache)
├── ThumbnailGridView.swift      # Image grid with mode-aware UI
│   ├── ThumbnailDisplayItem     # Enum: .single, .spread (#69)
│   ├── ThumbnailSidebarView     # Thumbnail strip (S014)
│   └── ThumbnailCell            # Individual thumbnail
├── ThumbnailComponents.swift    # Extracted thumbnail subviews (#175 Phase 1)
│   └── SpreadThumbnailPairView  # Paired thumbnails (#69, #187 .fill+.clipped)
├── ViewerView.swift             # In-grid viewer with thumbnail sidebar (#175 Phase 1)
│   └── ViewerKeyEventHandler    # Viewer-specific key handling
├── ExportConfirmationView.swift # Export sheet with metadata options (#105, #175 Phase 1)
├── MetadataInspectorPanel.swift # NSPanel metadata display (#140)
├── AnimatedImageContent.swift   # GIF frame data model + decoder (#201)
├── AnimationPlayer.swift        # CADisplayLink playback engine (#201)
├── ImagePreviewView.swift       # Quick Look preview modal (deprecated #176)
├── SettingsView.swift           # Settings panel (grid spacing, quality, N-step, Auto-Slide)
├── SlideWindowController.swift  # Fullscreen slide mode controller
│   ├── SlideWindowView          # SwiftUI view for slide content
│   ├── ImagePositionBar         # Image position with ★/× markers
│   └── SlideKeyHandler          # Supplementary key view (Space only)
├── SpreadImageViewer.swift      # Spread view with double buffering (S020/S021)
│   └── SpreadNavigationHelper   # Spread-aware navigation utility
├── SourceNavigator.swift        # Sibling source discovery utility
├── SourcePositionIndicator.swift # Source position dot/bar indicator
├── ImageSource.swift            # Protocol + ImageEntry model
├── ArchiveManager.swift         # ZIP ImageSource implementation
├── FolderManager.swift          # Folder ImageSource implementation
├── PDFManager.swift             # PDF ImageSource implementation (S024)
├── FolderNote.swift             # FolderNode tree node model (lazy, children=nil)
├── CacheManager.swift           # Thumbnail cache, favorites, async init (#216)
├── TileSheetCache.swift         # Tile-based thumbnail cache for archives (#24)
├── ThumbnailCoalescer.swift     # Batch thumbnail update coalescer (#138)
├── KeyHandling.swift            # Centralized key handling + CommonKeyParser (#169)
│   ├── AutoSlideTapHandler      # Shared Auto-Slide state machine (#175 Phase 2)
│   ├── BookmarkDialogHelper     # NSAlert bookmark dialogs (#62)
│   └── BookmarkListKeyHandler   # Bookmark list key handling (#62)
├── ZIPEncodingDetector.swift    # ZIP filename encoding detection
└── AppSettings.swift            # UserDefaults wrapper, settings enums
```

## External Dependencies

| Dependency | Purpose | Notes |
|------------|---------|-------|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | ZIP archive handling | Swift Package, MIT license |
| SwiftUI | UI framework | System framework |
| Combine | Reactive state (AppSettings) | System framework |
| UniformTypeIdentifiers | File type handling | System framework |
| PDFKit | PDF rendering | System framework |
| CryptoKit | Content hashing for cache | System framework |
| CoreML | Super-resolution upscaling (Hyperscaler PoC) (#40) | System framework |
| ImageIO | GIF frame extraction (CGImageSource) (#201) | System framework |

## State Management

```
ErimilApp
    ├── Settings { SettingsView }
    │
    └── WindowGroup { ContentView }
            │
            ├── @State selectedPaths: Set<String>  ← Source of truth
            ├── @State selectedSourceURL: URL?
            ├── @State selectedSourceType: ImageSourceType?
            ├── @State shouldReopenSlideMode: Bool  ← For source navigation
            │
            ├── SidebarView
            │       ├── @Binding selectedFolderURL
            │       ├── @State rootNode: FolderNode?
            │       ├── @State selectedNodeURL: URL?
            │       ├── @State childrenCache: [URL: [FolderNode]]  ← Lazy tree (#216)
            │       └── onOpenSlideMode callback  ← Double-click handler
            │
            ├── ThumbnailGridView
            │       ├── @Binding selectedPaths     ← From parent
            │       ├── @Binding shouldReopenSlideMode
            │       ├── @ObservedObject AppSettings.shared
            │       ├── @State entries: [ImageEntry]
            │       ├── @State thumbnails: [String: NSImage]
            │       ├── @State previewMode: PreviewMode
            │       └── imageSource: any ImageSource
            │
            └── SlideWindowController.shared (Singleton)
                    ├── slideWindow: NSWindow?
                    ├── currentIndex: Int
                    ├── isFavoritesMode: Bool       ← Favorites Mode state
                    ├── storedEntries: [ImageEntry]
                    ├── storedFavoriteIndices: Set<Int>
                    ├── storedSelectedIndices: Set<Int>
                    ├── storedOnToggleFavorite: ((Int) -> Void)?
                    └── storedOnToggleSelection: ((Int) -> Void)?
```

### CacheManager (Singleton)

```
CacheManager.shared
    ├── Async init: background load on startup (~143ms) (#216)
    │       └── didFinishLoadingNotification for UI refresh
    ├── pathIndex: [String: String]           ← pathHash → contentHash
    ├── thumbnailCache: NSCache               ← contentHash → NSImage
    ├── sourceSettings: [String: SourceSettings]  ← Per-source settings (#54)
    │       ├── lastPosition: Int?
    │       ├── readingDirection: ReadingDirection?
    │       └── singlePageIndices: Set<Int>?  ← V key markers (#56)
    ├── aspectRatioCache: [String: CGFloat]   ← In-memory only (#67)
    │
    Methods:
    ├── copyMetadata()             ← Export metadata carry-over (#105)
    │       Index remapping, path remapping (PDF), per-option control
    ├── setDirectFavorite()        ← Idempotent favorite registration
    └── pdfEntryPathRemapper()     ← Auto-detect PDF path format
    │
    Persisted:
    ├── index.json                 ← pathIndex
    ├── favorites.json             ← Favorites data
    ├── source_settings.json       ← sourceSettings
    └── tilesheets/                ← Tile-based archive thumbnails (#24)
```

#### MetadataCarryOverOptions (#105)

```
MetadataCarryOverOptions
    ├── favorites: Bool            ← ★ お気に入り
    ├── bookmarks: Bool            ← 栞 ブックマーク
    ├── readingDirection: Bool     ← 読み取り方向
    └── singlePageMarkers: Bool   ← 単独表示マーカー
```

### AppSettings (Singleton)

```
AppSettings.shared
    ├── @Published selectionMode: SelectionMode
    ├── @Published defaultOutputFolder: URL?
    ├── @Published useDefaultOutputFolder: Bool
    ├── @Published thumbnailSizePreset: ThumbnailSizePreset
    ├── @Published thumbnailSize: CGFloat              ← Custom size value
    ├── @Published thumbnailQuality: ThumbnailQuality  ← Quality preset with Retina (#207)
    ├── @Published gridSpacing: CGFloat                ← Grid gap size (#212)
    ├── @Published favoriteScope: FavoriteScope       ← Content vs Source
    ├── @Published viewerThumbnailPosition: ViewerThumbnailPosition
    ├── @Published prefetchCount: Int                 ← Prefetch image count
    ├── @Published loopWithinSource: Bool             ← Loop navigation
    ├── @Published defaultReadingDirection: ReadingDirection
    ├── @Published isSpreadModeEnabled: Bool          ← Spread view toggle
    ├── @Published spreadThreshold: Double            ← Wide image threshold
    ├── @Published nStepCount: Int                    ← N-step navigation step (#143)
    ├── @Published autoSlideLoop: Bool                ← Auto-Slide loop at boundary (#172)
    ├── @Published lastOpenedFolderURL: URL?          ← Restore on launch
    ├── @Published metadataCarryOverFavorites: Bool   ← Export ★ (#105)
    ├── @Published metadataCarryOverBookmarks: Bool   ← Export 栞 (#105)
    ├── @Published metadataCarryOverDirection: Bool   ← Export direction (#105)
    ├── @Published metadataCarryOverMarkers: Bool     ← Export markers (#105)
    ├── defaultMetadataOptions: MetadataCarryOverOptions  ← Computed (#105)
    
    Persisted via UserDefaults
```

### Enums (in AppSettings.swift)

```
SelectionMode
    ├── .exclude    ← Selected items will be removed
    └── .keep       ← Selected items will be kept

ThumbnailSizePreset
    ├── .small      ← 80px
    ├── .medium     ← 120px
    ├── .large      ← 180px
    └── .custom     ← Use thumbnailSize value

FavoriteScope
    ├── .content    ← Same image anywhere gets ★ (by content hash)
    └── .source     ← Per ZIP/folder independent ★

ViewerThumbnailPosition
    ├── .left       ← Vertical strip on left
    ├── .bottom     ← Horizontal strip at bottom
    └── .hidden     ← No thumbnail strip (Ctrl+T cycles)

ReadingDirection
    ├── .ltr        ← Left-to-Right (Western)
    └── .rtl        ← Right-to-Left (Japanese vertical text)
```

## Privacy/Security Considerations

- **File Access**: Requires user-granted folder access (macOS sandbox)
- **No Network**: Application is fully offline
- **No Telemetry**: No data collection
- **Original Files**: Never modified without explicit "Confirm" action

---

## Technical Constraints (macOS Platform)

### App Sandbox

macOS apps run within a sandbox with restricted file access.

| Operation | Constraint | Solution |
|-----------|------------|----------|
| File reading | User-selected only | Use NSOpenPanel |
| File writing | User-selected only | Use NSSavePanel |
| Persistent folder access | Lost on app restart | Security-Scoped Bookmarks |
| Move to Trash | Requires permission | `NSWorkspace.shared.recycle()` |

### Security-Scoped Bookmarks

Mechanism to maintain access rights to user-selected folders across app launches.

```swift
// Save (after NSOpenPanel selection)
let bookmarkData = try url.bookmarkData(options: .withSecurityScope)

// Restore (on app launch)
let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope)
url.startAccessingSecurityScopedResource()  // Start accessing
// ...
url.stopAccessingSecurityScopedResource()   // Stop accessing
```

**Note**: UserDefaults may not persist in Xcode debug environment. File-based storage (Application Support) is recommended.

### Entitlements Requirements

Required keys in `Erimil.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

### Common Pitfalls

| Problem | Symptom | Cause | Solution |
|---------|---------|-------|----------|
| Cannot read folder contents | `children count: 0` | No access rights | Security-Scoped Bookmarks |
| Settings not saved | Reset on every launch | UserDefaults issue | File-based storage |
| ZIP export fails | permission denied | No write permission | Use NSSavePanel |
| Entitlements error | Build failure | Missing configuration | Check Build Settings |

---

## Development Setup

### Xcode Configuration

**1. Create Entitlements File**

```
1. File → New → File → Property List
2. Filename: Erimil.entitlements
3. Right-click → Open As → Source Code
4. Paste content (see above)
```

**2. Register in Build Settings**

```
1. Project Navigator → Select Erimil project
2. TARGETS → Select Erimil
3. Build Settings tab
4. Search: "entitlements"
5. Set Code Signing Entitlements to "Erimil/Erimil.entitlements"
```

**3. Verify Signing & Capabilities**

```
1. Signing & Capabilities tab
2. App Sandbox is enabled
3. File Access → User Selected File: Read/Write
```

### Debugging

**Structured logging with os.Logger (#94)**

All debug output uses Apple's `os.Logger` framework with subsystem `com.erimil.app`.
Logger categories are defined in `Logger.swift` as static extensions.

**Filtering in Console.app**

```
1. Open Console.app
2. Filter: Process name "Erimil"
3. Filter: Subsystem "com.erimil.app"
4. Optionally filter by Category (e.g., "ThumbnailGrid")
5. Action → Include Debug Messages to show .debug level
```

**Logger categories**

| Category | Component |
|----------|-----------|
| `AppSettings` | Settings, Bookmarks |
| `ArchiveManager` | ZIP archive operations |
| `CacheManager` | Cache, Favorites, Metadata Copy |
| `Bookmark` | Bookmark operations (#62) |
| `SidebarView` | Folder tree |
| `ContentView` | Main view |
| `ThumbnailGrid` | Thumbnail grid |
| `SlideWindow` | Slide Mode |
| `SourceNavigator` | Source navigation |
| `PDFManager` | PDF operations |
| `Prefetcher` | Image prefetching |
| `FolderManager` | Folder operations |
| `ZIPEncoding` | ZIP filename encoding |
| `ImagePreview` | Quick Look preview |
| `Viewer` | ViewerView |
| `SpreadViewer` | Spread display |
| `KeyHandling` | Keyboard event handling |
| `AnimationPlayer` | GIF playback (#201) |
| `TileSheet` | Tile-based thumbnail cache (#24) |
| `Coalescer` | Thumbnail batch updates (#138) |
| `Metadata` | Metadata inspector (#140) |

**Log levels**

| Level | Usage |
|-------|-------|
| `.debug` | Development traces (thumbnail loading, key detection) |
| `.info` | Milestones (source switch, export complete) |
| `.error` | Failures (file read error, archive open failure) |

### Application Support Location

```bash
~/Library/Application Support/Erimil/
├── cache/                      # Thumbnail cache (.ecache format #146)
├── tilesheets/                 # Tile-based thumbnail cache for archives (#24)
├── index.json                  # Path → contentHash mapping
├── favorites.json              # Favorites data (hybrid format)
├── source_settings.json        # Per-source settings (#54)
├── bookmarks.json              # Per-source bookmarks (#62)
└── last_folder_bookmark.data   # Folder restoration bookmark
```

### Troubleshooting

**Q: Folder selected but contents not displayed**
```
A: Security-Scoped Bookmarks issue
   1. Verify bookmarks.app-scope in Entitlements
   2. Check AppSettings category logs in Console.app
   3. Verify last_folder_bookmark.data is created
```

**Q: Favorites not saved**
```
A: Application Support directory issue
   1. Verify ~/Library/Application Support/Erimil/ exists
   2. Check permissions on favorites.json
```

**Q: Build error "Entitlements file not found"**
```
A: Build Settings misconfiguration
   1. Verify Code Signing Entitlements path is correct
   2. Verify file is added to project
```

**Q: Keyboard shortcuts not working in Slide Mode**
```
A: Event monitor issue
   1. Check SlideWindow category logs for "Event monitor registered"
   2. Verify window is key window (isKeyWindow == true)
```

**Q: PDF pages not displaying**
```
A: PDFManager issue
   1. Check PDFManager category logs for page count
   2. Verify PDF is not password-protected
   3. Check memory usage for large PDFs
```

**Q: Spread view showing wrong layout**
```
A: Aspect ratio or direction issue
   1. Check reading direction setting (RTL vs LTR)
   2. Verify aspect ratio cache is populated
   3. Check single page markers (V key)
```

---

## Performance Considerations

- **Startup**: Lazy tree loading (FolderNode children=nil, on-demand via childrenCache) — 16.7s → 2ms (#216)
- **CacheManager**: Async initialization on background queue — 143ms for 105K entries, does not block main thread (#216)
- **Large ZIPs (>1GB)**: Show warning, consider streaming approach
- **Many Images (>1000)**: Virtualized grid, load visible thumbnails only
- **Memory**: Thumbnail cache with size limit, LRU eviction
- **Large PDFs**: Lazy page rendering, memory cache with double-checked locking (#165)
- **Image Prefetching**: Direction-aware prefetch reduces perceived latency
- **Thumbnail disk cache**: Synchronous check in loadThumbnailIfNeeded eliminates async delay for cached thumbnails (#160)
- **Tile sheets**: ZIP/PDF archives use tile-based thumbnail cache for fast subsequent opens (#24)
- **Render-gated navigation**: Z/C favorite navigation prevents key-repeat from skipping unrendered frames (#154)
- **ThumbnailCoalescer**: Batches thumbnail assignments to reduce SwiftUI body re-evaluations by 95-98% (#138)
- **Sandboxed filesystem**: Recursive traversal is catastrophically expensive due to permission checks; always use lazy loading (#216)

---

## Template Information

> Based on **Project Documentation Methodology** v0.1.0
> Document started: 2025-12-13
> Last updated: 2026-03-21 (v0.3.4: #216 lazy tree, #24 tile sheets, #201 animated, #140 metadata, #138 coalescer)
