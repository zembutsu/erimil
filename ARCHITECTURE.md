# Erimil Architecture

This document describes the internal architecture of Erimil.

## Overview

Erimil is a macOS application built with SwiftUI that provides visual management of images in ZIP archives and folders. Users can browse folders, select ZIP files or image folders, preview contained images, mark items for exclusion/selection, and generate optimized archives or manage files.

```
┌─────────────────────────────────────────────────────────────┐
│                        Erimil                               │
├─────────────────┬───────────────────────────────────────────┤
│   Folder Tree   │          Thumbnail Grid                   │
│                 │                                           │
│  📁 Photos      │   [img1] [img2] [img3] [img4]            │
│   ├─ 📁 2024/   │   [img5] [img6] [img7] [img8]            │
│   │  └─ 📦a.zip │                                           │
│   └─ 📁 2023/   │   Double-click to preview                │
│      └─ 📦b.zip │   ┌──────────────────────┐               │
│                 │   │ [除外モード] 8 画像  │               │
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
- **ImageSourceType**: Enum (.archive, .folder) for UI customization

### 2. Archive Layer

Manages ZIP file reading and writing.

- **ArchiveManager**: ImageSource implementation for ZIP archives
  - Uses ZIPFoundation for ZIP operations
  - Opens Archive per-operation (official pattern)
  - Handles export with exclusions

### 3. Folder Layer

Manages folder image browsing and operations.

- **FolderManager**: ImageSource implementation for folders
  - Direct FileManager access
  - ZIP creation from selected images
  - Delete to Trash functionality

### 4. Navigation Layer

Handles folder browsing and source discovery.

- **SidebarView**: Finder-style tree navigation (→ DESIGN.md Decision 9)
  - ▶ for expand/collapse
  - Row click for content display
- **FolderNode**: Model representing folder/ZIP in tree

### 5. Selection Layer

Tracks user selections and pending changes.

- **selectedPaths**: Set<String> in ContentView (source of truth)
- **AppSettings**: Selection mode (exclude/keep), output folder defaults

### 6. View Layer

SwiftUI views for user interaction.

- **ContentView**: Main split view, owns selection state
- **ThumbnailGridView**: Grid display with mode-aware styling
- **ThumbnailCell**: Individual thumbnail with selection overlay
- **ImagePreviewView**: Modal full-size preview
- **SettingsView**: Settings panel (⌘,)

## Data Flow

### Opening a Source (ZIP or Folder)

```
User selects root folder
    ↓
SidebarView scans directory (FolderNode)
    ↓
User clicks ZIP or folder row
    ↓
ContentView creates ImageSource:
  - ZIP → ArchiveManager
  - Folder → FolderManager
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
Perform operation:
  - ZIP: exportOptimized(excluding: pathsToRemove)
  - Folder ZIP: createZip(excluding: pathsToRemove)
  - Folder Delete: moveToTrash(paths: pathsToRemove)
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

## Key Design Decisions

### 1. ImageSource Protocol Abstraction

ZIP files and folders are accessed through a common `ImageSource` protocol. This enables:
- Unified UI for different source types
- Easy addition of new formats (tar.gz, 7z in future)
- Same selection/preview logic for all sources

See DESIGN.md Decision 8 for rationale.

### 2. Lazy Thumbnail Loading

Thumbnails are generated on-demand as grid scrolls, not all at once. Large sources may contain hundreds of images; loading all would cause memory issues and slow startup.

### 3. Parent-Owned Selection State

`selectedPaths` lives in ContentView, not ThumbnailGridView. This enables:
- Accurate unsaved changes detection
- Mode-independent state (exclude/keep calculated from same data)
- Clear ownership of truth

### 4. Per-Operation Archive Opening

ArchiveManager opens Archive fresh for each operation (thumbnail, preview, export). This follows ZIPFoundation's official pattern and avoids encoding issues with Japanese filenames.

### 5. Selection Mode Abstraction

User selections are stored as `selectedPaths`. The meaning (exclude vs keep) is calculated at action time:
- `pathsToRemove = selectedPaths` (exclude mode)
- `pathsToRemove = allPaths - selectedPaths` (keep mode)

This allows mode switching without losing selections.

## Constants and Configuration

| Constant | Value | Purpose |
|----------|-------|---------|
| `thumbnailSize` | 120px | Default thumbnail dimension |
| `gridSpacing` | 8px | Gap between thumbnails |
| `outputSuffix` | `_opt` | Appended to output filename |
| `supportedImageTypes` | jpg, jpeg, png, gif, webp, heic | Recognized image extensions |

## File Structure

```
Erimil/
├── ErimilApp.swift           # App entry point, Settings scene
├── ContentView.swift         # Main split view, owns selection state
├── SidebarView.swift         # Folder tree navigation (Finder-style)
├── ThumbnailGridView.swift   # Image grid with mode-aware UI
├── ThumbnailCell.swift       # Individual thumbnail (in ThumbnailGridView)
├── ImagePreviewView.swift    # Full-size preview modal
├── SettingsView.swift        # Settings panel
├── ImageSource.swift         # Protocol + ImageEntry model
├── ArchiveManager.swift      # ZIP ImageSource implementation
├── FolderManager.swift       # Folder ImageSource implementation
├── FolderNode.swift          # Tree node model
└── AppSettings.swift         # UserDefaults wrapper, SelectionMode
```

## External Dependencies

| Dependency | Purpose | Notes |
|------------|---------|-------|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | ZIP archive handling | Swift Package, MIT license |
| SwiftUI | UI framework | System framework |
| Combine | Reactive state (AppSettings) | System framework |
| UniformTypeIdentifiers | File type handling | System framework |

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
            │
            ├── SidebarView
            │       ├── @Binding selectedFolderURL
            │       ├── @State rootNode: FolderNode?
            │       └── @State selectedNodeID: UUID?
            │
            └── ThumbnailGridView
                    ├── @Binding selectedPaths     ← From parent
                    ├── @ObservedObject AppSettings.shared
                    ├── @State entries: [ImageEntry]
                    ├── @State thumbnails: [String: NSImage]
                    └── imageSource: any ImageSource
```

### AppSettings (Singleton)

```
AppSettings.shared
    ├── @Published selectionMode: SelectionMode
    ├── @Published defaultOutputFolder: URL?
    └── @Published useDefaultOutputFolder: Bool
    
    Persisted via UserDefaults
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

**Check logs in Console.app**

```
1. Open Console.app
2. Filter: Process name "Erimil" or search "[AppSettings]"
3. Operate the app and check logs
```

**Common log prefixes**

| Prefix | Component |
|--------|-----------|
| `[AppSettings]` | Settings, Bookmarks |
| `[CacheManager]` | Cache, Favorites |
| `[SidebarView]` | Folder tree |
| `[ContentView]` | Main view |

### Application Support Location

```bash
~/Library/Application Support/Erimil/
├── cache/                      # Thumbnail cache
├── index.json                  # Path → contentHash mapping
├── favorites_hybrid.json       # Favorites data
└── last_folder_bookmark.data   # Folder restoration bookmark
```

### Troubleshooting

**Q: Folder selected but contents not displayed**
```
A: Security-Scoped Bookmarks issue
   1. Verify bookmarks.app-scope in Entitlements
   2. Check "[AppSettings]" logs in Console.app
   3. Verify last_folder_bookmark.data is created
```

**Q: Favorites not saved**
```
A: Application Support directory issue
   1. Verify ~/Library/Application Support/Erimil/ exists
   2. Check permissions on favorites_hybrid.json
```

**Q: Build error "Entitlements file not found"**
```
A: Build Settings misconfiguration
   1. Verify Code Signing Entitlements path is correct
   2. Verify file is added to project
```

---

## Performance Considerations

- **Large ZIPs (>1GB)**: Show warning, consider streaming approach
- **Many Images (>1000)**: Virtualized grid, load visible thumbnails only
- **Memory**: Thumbnail cache with size limit, LRU eviction

---

## Template Information

> Based on **Project Documentation Methodology** v0.1.0
> Document started: 2025-12-13
> Last updated: 2025-12-14 (Phase 2.1 - Technical Constraints added)
