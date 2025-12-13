# Erimil Architecture

This document describes the internal architecture of Erimil.

## Overview

Erimil is a macOS application built with SwiftUI that provides visual management of ZIP archive contents. Users can browse folders, select ZIP files, preview contained images, mark items for exclusion, and generate optimized archives.

```
┌─────────────────────────────────────────────────────────────┐
│                        Erimil                               │
├─────────────────┬───────────────────────────────────────────┤
│   Folder Tree   │          Thumbnail Grid                   │
│                 │                                           │
│  📁 Photos      │   [img1] [img2] [img3] [img4]            │
│   ├─ 2024/      │   [img5] [img6] [img7] [img8]            │
│   │  └─ 📦a.zip │                                           │
│   └─ 2023/      │   Click to enlarge (Quick Look)          │
│      └─ 📦b.zip │                                           │
├─────────────────┴───────────────────────────────────────────┤
│  Status: 3 items selected for exclusion                     │
│  [Cancel]                              [Confirm → _opt.zip] │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Navigation Layer

Handles folder browsing and ZIP file discovery.

- **FolderTreeView**: SwiftUI view displaying hierarchical folder structure
- **FolderNode**: Model representing folder/file in tree
- **ZIPDetector**: Identifies ZIP files within folder hierarchy

### 2. Archive Layer

Manages ZIP file reading and writing.

- **ArchiveManager**: Wrapper around ZIPFoundation for ZIP operations
- **ArchiveEntry**: Model representing single file within ZIP
- **ThumbnailGenerator**: Extracts and caches image thumbnails from ZIP

### 3. Selection Layer

Tracks user selections and pending changes.

- **SelectionState**: ObservableObject tracking excluded items
- **ChangeTracker**: Monitors unsaved changes for confirmation dialogs

### 4. Export Layer

Handles output generation.

- **ArchiveExporter**: Creates new ZIP excluding selected items
- **NamingStrategy**: Generates output filenames (`{name}_opt.zip`)

### 5. Preview Layer

Provides image preview functionality.

- **ThumbnailGridView**: Grid display of archive images
- **PreviewController**: Manages enlarged preview (Quick Look or modal)

## Data Flow

### Opening a ZIP

```
User selects folder
    ↓
FolderTreeView scans directory
    ↓
ZIPDetector identifies .zip files
    ↓
User clicks ZIP file
    ↓
ArchiveManager reads ZIP entries
    ↓
ThumbnailGenerator extracts previews (lazy, on-demand)
    ↓
ThumbnailGridView displays grid
```

### Selecting Items for Exclusion

```
User clicks thumbnail
    ↓
SelectionState.toggle(entry)
    ↓
ChangeTracker.markDirty()
    ↓
UI updates (visual exclusion marker)
```

### Confirming Changes

```
User clicks "Confirm"
    ↓
ArchiveExporter.export(
    source: original.zip,
    excluding: SelectionState.excludedItems,
    destination: original_opt.zip
)
    ↓
ZIPFoundation creates new archive
    ↓
SelectionState.clear()
    ↓
ChangeTracker.markClean()
    ↓
Success notification
```

### Navigation with Unsaved Changes

```
User clicks different ZIP (while dirty)
    ↓
ChangeTracker.isDirty == true
    ↓
Show confirmation dialog:
  - "Confirm" → Export, then navigate
  - "Discard" → Clear selection, navigate
  - "Cancel" → Stay on current ZIP
```

## Key Design Decisions

### 1. Lazy Thumbnail Loading

Thumbnails are generated on-demand as grid scrolls, not all at once. Large ZIPs may contain hundreds of images; loading all would cause memory issues and slow startup.

### 2. In-Memory Selection State

Exclusion selections are stored in memory only until confirmed. No intermediate files, no auto-save. This keeps the original ZIP completely untouched until explicit user action.

### 3. ZIPFoundation for Archive Operations

Using [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (pure Swift) rather than system `zip` command or libzip:
- No external dependencies
- Swift-native error handling
- Cross-platform potential (iOS future)

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
├── ErimilApp.swift           # App entry point
├── Models/
│   ├── FolderNode.swift      # Folder tree model
│   ├── ArchiveEntry.swift    # ZIP entry model
│   └── SelectionState.swift  # Selection tracking
├── Views/
│   ├── ContentView.swift     # Main split view
│   ├── FolderTreeView.swift  # Left pane
│   ├── ThumbnailGridView.swift # Right pane
│   └── PreviewView.swift     # Enlarged preview
├── Services/
│   ├── ArchiveManager.swift  # ZIP read/write
│   ├── ThumbnailGenerator.swift # Image extraction
│   └── ArchiveExporter.swift # Output generation
├── Utilities/
│   └── NamingStrategy.swift  # Filename generation
└── Resources/
    └── Assets.xcassets       # App icons, colors
```

## External Dependencies

| Dependency | Purpose | Notes |
|------------|---------|-------|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | ZIP archive handling | Swift Package, MIT license |
| SwiftUI | UI framework | System framework |
| QuickLook | Image preview | System framework (optional) |

## State Management

```
ErimilApp
    └── ContentView
            ├── @StateObject SelectionState (shared)
            ├── @StateObject ChangeTracker (shared)
            │
            ├── FolderTreeView
            │       └── @State selectedPath
            │
            └── ThumbnailGridView
                    └── reads SelectionState
                    └── writes SelectionState on click
```

## Privacy/Security Considerations

- **File Access**: Requires user-granted folder access (macOS sandbox)
- **No Network**: Application is fully offline
- **No Telemetry**: No data collection
- **Original Files**: Never modified without explicit "Confirm" action

## Performance Considerations

- **Large ZIPs (>1GB)**: Show warning, consider streaming approach
- **Many Images (>1000)**: Virtualized grid, load visible thumbnails only
- **Memory**: Thumbnail cache with size limit, LRU eviction

---

## Template Information

> Based on **Project Documentation Methodology** v0.1.0
> Document started: 2025-12-13
