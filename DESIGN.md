# Erimil Design Rationale

This document explains why the software was designed the way it was, including discussion history and decision records.

---

## Design Goals

1. **Safety**: Never lose user data through accidental operations
2. **Speed**: Quick visual scanning of archive contents without full extraction
3. **Integration**: Seamless workflow with kurumil and other tools
4. **Simplicity**: Minimal learning curve, obvious UI patterns

---

## Design Decisions

### Decision 1: ZIP Editing Strategy

**Context**: How should Erimil modify ZIP archives? Direct editing is simpler but risky.

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A) In-place | Modify original ZIP directly | Simple, saves space | Data loss risk, no undo |
| B) New file | Create `{name}_opt.zip`, keep original | Safe, reversible | Double storage temporarily |
| C) User choice | Setting to switch between A and B | Flexible | UI complexity, decision fatigue |

**Decision**: **Option B (New file)** as default

**Rationale**: 
- User explicitly stated "消すのは怖い" (deletion is scary)
- Image curation often involves "やっぱり戻したい" (wanting to undo)
- Storage is cheap, data loss is expensive
- Future option to enable in-place editing for advanced users

**Output filename**: `{original_name}_opt.zip`
- `_opt` = "optimized"
- Short, clear intent
- Alternatives considered: `_cleaned`, `_erimil`, `_{timestamp}`

**Consequences**:
- ✅ Safe by default
- ✅ Easy to compare before/after
- ⚠️ Requires manual cleanup of original files
- ⚠️ Needs sufficient disk space for both files

**Future option**: Add setting for in-place editing (Phase 2+)

---

### Decision 2: Selection Mode

**Context**: Should users select images to "keep" or to "exclude"?

**Options Considered**:

| Option | Operation | Best for | Risk |
|--------|-----------|----------|------|
| A) Select to keep | Mark what survives | Picking few from many | Forget to select = deleted |
| B) Select to exclude | Mark what's removed | Removing few from many | Forget to select = kept (safe) |
| C) Toggle mode | Setting to switch A/B | Flexibility | Confusion about current mode |

**Decision**: **Option B (Select to exclude)** as default

**Rationale**:
- User's stated goal: "不要なものを排除" (remove unnecessary items)
- Safer failure mode: unmarked items are preserved
- Mental model: "I'm throwing these away" is clearer than "I'm keeping only these"

**UI implications**:
- Unselected = normal display (will be kept)
- Selected = visual indicator for exclusion (red border, dimmed, or ✕ overlay)

**Consequences**:
- ✅ Safe default (nothing deleted unless explicitly marked)
- ✅ Matches stated use case
- ⚠️ Tedious if user wants to keep only 10 of 100 images

**Future option**: Add "Keep mode" toggle (Phase 2+)

---

### Decision 3: Original File Handling

**Context**: What happens to the original ZIP after creating `_opt.zip`?

**Options Considered**:

| Option | Action | Safety |
|--------|--------|--------|
| A) Overwrite | Replace original with new | Low |
| B) Trash | Move original to Trash | Medium |
| C) Backup | Create `{name}_backup.zip` | High |
| D) Nothing | Leave original untouched | Highest |

**Decision**: **Option D (Nothing)** as default

**Rationale**:
- Given Decision 1 (new file creation), no need to touch original
- User decides when/if to delete original
- "Surprising" behavior (auto-trash) violates least surprise principle

**Consequences**:
- ✅ Maximum safety
- ✅ User retains full control
- ⚠️ Manual cleanup required
- ⚠️ Disk space usage during transition

**Future option**: Setting for "Move original to Trash after confirm" (Phase 2+)

---

### Decision 4: Preview Functionality

**Context**: How should users inspect individual images?

**Options Considered**:

| Option | Implementation | Effort |
|--------|----------------|--------|
| A) Thumbnails only | Grid view, no enlargement | Low |
| B) Quick Look | System QLPreviewPanel | Low-Medium |
| C) Custom modal | NSImage in sheet/popover | Medium |
| D) Side panel | Persistent preview pane | High |

**Decision**: **Option B or C (enlargeable preview)** for Phase 1

**Rationale**:
- User stated: "Quick Look の拡大表示だけ欲しい...「この画像なんだったっけ？」と結局Zip展開してしまっては意味が無い"
- Without enlargement, the tool defeats its own purpose
- Quick Look is native macOS pattern, familiar to users

**Consequences**:
- ✅ Users can inspect details before deciding
- ✅ No need to extract ZIP externally
- ⚠️ Slight implementation complexity

---

### Decision 5: Application Name

**Context**: Naming for the DDL tool family.

**Options Considered**:
- **erimil** (選り見る) - "select and view"
- **shibomiru** (絞り見る) - "filter and view"  
- **yorinuki** (より抜き) - "selection"

**Decision**: **Erimil**

**Rationale**:
- Matches kurumil naming pattern (Japanese wordplay + "mil/miru")
- "serial experiments" aesthetic (lain reference)
- Clear meaning: 選り (select/choose) + 見る (view)

---

### Decision 6: ZIPFoundation Usage Pattern

**Date**: 2025-12-13

**Context**: During thumbnail generation, `corruptedData` errors occurred frequently. Initial implementation held `Archive` instance as a member variable and used custom caching mechanisms.

**Options Considered**:

| Option | Description | Result |
|--------|-------------|--------|
| A) Member variable | Hold Archive instance, custom entry cache | Failed - encoding issues, stale references |
| B) Per-operation | Open Archive fresh for each operation | Works - matches official examples |

**Decision**: **Option B (Per-operation)**

**Rationale**:
- Official documentation examples show opening Archive for each operation
- Avoids stale references and encoding issues with Japanese filenames
- Simpler code, less state to manage
- Reference: https://github.com/weichsel/ZIPFoundation#closure-based-reading-and-writing

**Implementation**:
```swift
// ✅ Correct pattern
func extractImage(for entry: ArchiveEntry) -> NSImage? {
    guard let archive = Archive(url: zipURL, accessMode: .read) else { return nil }
    guard let zipEntry = archive[entry.path] else { return nil }
    // ... extract using consumer closure
}
```

**Consequences**:
- ✅ Reliable extraction regardless of filename encoding
- ✅ Matches official patterns
- ⚠️ Slightly more overhead (opening archive each time)
- ⚠️ Acceptable tradeoff for correctness

---

### Decision 7: Sandbox File Access for Export

**Date**: 2025-12-13

**Context**: ZIP export failed with "Parent writable: false" error. macOS sandbox prevents writing to arbitrary locations.

**Options Considered**:

| Option | Description | UX |
|--------|-------------|-----|
| A) Direct write | Write to same directory as source | Fails in sandbox |
| B) NSSavePanel | Let user choose destination | Works, standard macOS pattern |
| C) App container | Save to app's container directory | Works but hidden from user |

**Decision**: **Option B (NSSavePanel)**

**Rationale**:
- User explicitly selects save location = permission granted
- Standard macOS UX pattern
- System handles overwrite confirmation
- Requires: `User Selected File: Read/Write` entitlement in Signing & Capabilities

**Implementation**:
```swift
let savePanel = NSSavePanel()
savePanel.nameFieldStringValue = "\(originalName)_opt.zip"
savePanel.allowedContentTypes = [.zip]  // requires import UniformTypeIdentifiers
guard savePanel.runModal() == .OK, let outputURL = savePanel.url else { return }
```

**Consequences**:
- ✅ Works within sandbox
- ✅ User has full control over destination
- ✅ Familiar macOS experience
- ⚠️ Extra click for user (acceptable for safety)

---

### Decision 8: ImageSource Abstraction

**Date**: 2025-12-14

**Context**: User requested folder browsing capability in addition to ZIP files. Need to support:
- ZIP files (existing)
- Folders containing images (new)

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A) Duplicate code | Separate views for ZIP/Folder | Simple | Code duplication, inconsistent UX |
| B) Protocol abstraction | Common ImageSource protocol | Unified UX, extensible | Initial refactoring effort |
| C) Union type | Enum with associated values | Type-safe | Complex pattern matching |

**Decision**: **Option B (Protocol abstraction)**

**Rationale**:
- Enables future format support (tar.gz, 7z) with same pattern
- Single ThumbnailGridView works with any source
- Consistent UX regardless of source type

**Implementation**:
```swift
protocol ImageSource {
    var url: URL { get }
    var displayName: String { get }
    func listImageEntries() -> [ImageEntry]
    func thumbnail(for entry: ImageEntry) -> NSImage?
    func fullImage(for entry: ImageEntry) -> NSImage?
}

class ArchiveManager: ImageSource { ... }  // existing
class FolderManager: ImageSource { ... }   // new
```

**Consequences**:
- ✅ Single UI component for all source types
- ✅ Easy to add new formats (Phase 3)
- ✅ Consistent user experience
- ⚠️ Requires refactoring existing ArchiveManager

---

### Decision 9: Finder-style Navigation UI

**Date**: 2025-12-14

**Context**: Adding folder support creates ambiguity - clicking a folder could mean "expand tree" or "show contents".

**Options Considered**:

| Option | Operation | Pros | Cons |
|--------|-----------|------|------|
| A) Double-click = show | Single=expand, Double=show | ZIP consistency | Slow for browsing |
| B) Finder-style | ▶=expand, Row=show | Familiar, fast | Implementation change |
| C) Right-click menu | Context menu for actions | Explicit | Discoverable issue |
| D) Auto-show if images | Show images automatically | Intuitive | Unexpected behavior |

**Decision**: **Option B (Finder-style)**

**Rationale**:
- Matches macOS Finder behavior users already know
- Fast workflow: single click to view contents
- Disclosure triangle (▶) clearly indicates expandable items
- Works consistently for both folders and ZIPs

**UI Specification**:
```
▶ data/                    ← ▶ click: expand/collapse
    ▶ 2024/                ← Row click: show images in right pane
        ▶ screenshots/
    📦 archive.zip         ← Row click: show ZIP contents
```

**Consequences**:
- ✅ Familiar macOS pattern
- ✅ Fast navigation
- ✅ Unified behavior for ZIP and folders
- ⚠️ Requires SidebarView refactoring

---

### Decision 10: Folder Operations

**Date**: 2025-12-14

**Context**: When browsing folders, what actions should be available?

**Options Considered**:

| Action | Implementation | Risk |
|--------|----------------|------|
| ZIP selected images | Create new ZIP from selection | Low |
| Delete to Trash | NSWorkspace.shared.recycle() | Medium (recoverable) |
| Delete permanently | FileManager.removeItem() | High (data loss) |
| Move to folder | FileManager.moveItem() | Medium |

**Decision**: 
- **ZIP creation**: Create ZIP from selected (non-excluded) images
- **Delete**: Move to Trash only (never permanent delete)

**Rationale**:
- Follows Safety First principle (Design Goal #1)
- Trash is recoverable - aligns with "消すのは怖い" sentiment
- ZIP creation matches existing _opt.zip workflow

**UI**:
- Footer buttons change based on source type:
  - ZIP: 「確定 → _opt.zip」
  - Folder: 「ZIP化」「削除（ゴミ箱）」

**Consequences**:
- ✅ Safe operations only
- ✅ Consistent with Phase 1 safety philosophy
- ✅ Dynamic UI based on context
- ⚠️ No permanent delete (intentional limitation)

---

### Decision 11: Cache and Metadata Storage Location

**Date**: 2025-12-14

**Context**: Where to store thumbnail cache, Favorite metadata, and index data?

**Options Considered**:

| Location | Path | Pros | Cons |
|----------|------|------|------|
| Application Support | `~/Library/Application Support/Erimil/` | Apple recommended, Time Machine backup | None |
| Caches | `~/Library/Caches/Erimil/` | System may clear | Data loss risk |
| Source adjacent | `.erimil/` folder | Project-local | Clutters user folders |
| Container | Sandbox container | Required for App Store | Complex path |

**Decision**: **Application Support**

**Reference**: [Apple File System Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)

**Structure**:
```
~/Library/Application Support/Erimil/
├── cache/
│   └── {contentHash}.thumb.jpg    # Thumbnail cache
├── index.json                      # pathHash → contentHash mapping
└── favorites.json                  # contentHash → favorite metadata
```

**Consequences**:
- ✅ Standard macOS pattern
- ✅ Included in Time Machine backup
- ✅ Clean uninstall (remove folder)
- ✅ Centralized management

---

### Decision 12: Hash-Based Privacy Design

**Date**: 2025-12-14

**Context**: Storing file paths reveals user's folder structure and potentially sensitive information (dates, locations, project names).

**Options Considered**:

| Approach | Privacy | Debuggability |
|----------|---------|---------------|
| Plain paths | ✗ Exposed | ◎ Easy |
| Path hashing only | △ Content visible | ○ Medium |
| Full hashing | ◎ Anonymous | △ Hard |

**Decision**: **Full hashing (paths and content)**

**Implementation**:
```
Path: /Users/zem/private/photo.jpg
  ↓ sha256(path)
PathHash: sha256:aaa111...

Content: [binary image data]
  ↓ sha256(data)  
ContentHash: sha256:xxx999...
```

**Data Format**:
```json
// index.json - no readable paths
{
  "sha256:aaa111...": "sha256:xxx999...",
  "sha256:bbb222...": "sha256:yyy888..."
}

// favorites.json - content hash only
{
  "version": 1,
  "items": {
    "sha256:xxx999...": { "addedAt": "2025-12-14T10:30:00Z" },
    "sha256:yyy888...": { "addedAt": "2025-12-14T11:00:00Z" }
  }
}
```

**Behavior**:

| Scenario | Result |
|----------|--------|
| Same image, different path | Same contentHash → Favorite preserved |
| File renamed/moved | Same contentHash → Favorite preserved |
| Same name, different content | Different contentHash → Separate items |
| ZIP renamed (A.zip → A2.zip) | Same contentHash → Favorites work |

**Consequences**:
- ✅ Complete privacy (no readable paths)
- ✅ Automatic favorite migration on file move
- ✅ Deduplication (same image = same cache)
- ⚠️ Debugging requires hash lookup
- ⚠️ Hash calculation adds processing time (mitigated by caching)

---

### Decision 13: Favorite Feature Design

**Date**: 2025-12-14

**Context**: User wants to mark important images and prevent accidental deletion.

**Requirements**:
- Mark/unmark individual images with ★
- Favorite images cannot be deleted (safety)
- Favorites persist across sessions
- Favorites follow the image (not the path)

**Decision**:

**Data Model**:
- Key: contentHash (sha256 of image data)
- Value: metadata (addedAt timestamp, optional note)

**UI**:
- ★ overlay on thumbnail (yellow/gold)
- `v` key to toggle favorite
- Favorite images excluded from delete operations
- Warning if trying to delete favorites

**Safety Rules**:
1. Favorited images are **never** included in `pathsToRemove`
2. Delete button shows warning: "N件のお気に入りは除外されます"
3. ZIP export includes favorites regardless of selection mode

**Consequences**:
- ✅ Prevents accidental deletion of important images
- ✅ Works across ZIP/folder sources
- ✅ Survives file moves/renames
- ⚠️ User must unfavorite to delete

---

### Decision 14: Phase-based Versioning

**Date**: 2025-12-16

**Context**: At Phase 2.1 completion, considered bumping version to v0.3.0. This raised the question of when to increment version numbers during 0.x.x development.

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Sub-phase versioning (0.3.0 for 2.1) | Fine-grained tracking | Overhead, meaningless without users |
| B | Phase versioning (0.2.x for Phase 2) | Clear milestones | Less granular |
| C | Feature versioning | Flexible | Inconsistent |

**Decision**: **Option B (Phase-based versioning)**

- 0.1.0 = Phase 1 (MVP)
- 0.2.x = Phase 2 (all sub-phases 2.1, 2.2, 2.3, 2.4)
- 0.3.0 = Phase 3
- 1.0.0 = Public release

**Rationale**:
- Version numbers are "promises to external users" - no users yet means no need for fine-grained versioning
- Commit log provides sufficient detail for internal tracking
- CHANGELOG [Unreleased] section accumulates changes until Phase completion
- Reduces overhead of version management during active development

**Consequences**:
- ✅ All Phase 2.x changes accumulate in [Unreleased]
- ✅ Version bump only at Phase boundaries or major milestones
- ✅ Tag creation aligned with Phase completion
- ⚠️ Less granular external tracking (acceptable for 0.x.x)

---

### D004: Security-Scoped Bookmarks for Folder Persistence

**Date**: 2025-12-15 (S002)

**Context**: Restoring last opened folder on app launch in sandboxed environment. UserDefaults can store the folder path, but sandbox prevents accessing it without user re-granting permission.

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | UserDefaults path | Simple | Loses access on restart |
| B | Security-Scoped Bookmarks | Persists access | More complex |
| C | Always ask user | Guaranteed access | Poor UX |

**Decision**: **Option B** - Use Security-Scoped Bookmarks instead of plain URL storage.

**Rationale**:
- Only sandbox-compliant way to persist file access
- Standard Apple-recommended approach
- Works across app launches

**Technical Notes**:
```swift
// Save (after NSOpenPanel selection)
let bookmark = try url.bookmarkData(options: .withSecurityScope, ...)

// Restore (on app launch)
var isStale = false
let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
_ = url.startAccessingSecurityScopedResource()
```

**Consequences**:
- ✅ Seamless folder restoration on app launch
- ⚠️ Bookmark can become stale (file moved/deleted)
- ⚠️ Must handle bookmark resolution failures gracefully

---

### D005: Mode Definitions & Component Architecture

**Date**: 2025-12-17 (S003)

**Context**: Phase 2.2 implementation - need to clarify "preview" vs "slide mode" distinction. Risk of duplicate implementation and unclear user mental model.

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Single fullscreen-capable view | One component | Platform constraints |
| B | Separate implementations | Simple per-mode | Code duplication |
| C | Shared core with containers | DRY, flexible | More architecture |

**Decision**: **Option C** - Two-mode system with shared `ImageViewerCore` component.

| Mode | Purpose | Trigger | Container |
|------|---------|---------|-----------|
| Quick Look | Selection/triage | Space key | Sheet |
| Slide Mode | Immersive viewing | F key | NSWindow |

**Component Architecture**:
```
ImageViewerCore (shared)
├── Image display & loading
├── Navigation logic (a/d, z/c)
├── Position indicator
└── Favorite indices handling

Containers:
├── ImagePreviewView (Quick Look) → Sheet
└── SlideWindowView (Slide Mode) → NSWindow fullscreen
```

**Rationale**:
- Single source of truth for navigation logic
- Platform constraints: macOS Sheet cannot use `toggleFullScreen()`
- Clear user mental model: Quick Look for work, Slide Mode for viewing

**Consequences**:
- ✅ DRY principle maintained
- ✅ Easy to test core logic independently
- ⚠️ favoriteIndices must be passed from parent
- ⚠️ Slight complexity in state synchronization

---

### D006: PDF as ImageSource

**Date**: 2026-01-29 (S024)

**Context**: Adding PDF support to complement ZIP and folder viewing. Users have PDFs containing scanned images (art books, documents) that need the same viewing experience.

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Separate PDF viewer | Dedicated UX | Duplicate code, inconsistent |
| B | Convert PDF to images first | Simple integration | Requires temp storage, slow |
| C | PDF as ImageSource | Unified interface | Read-only limitation |

**Decision**: **Option C** - Implement `PDFManager` conforming to `ImageSource` protocol.

**Rationale**:
- Leverages existing ImageSource abstraction (Decision 8)
- No code changes needed in views - they already work with any ImageSource
- Lazy page rendering avoids memory issues with large PDFs
- Uses system PDFKit (no external dependencies)

**Consequences**:
- ✅ Unified UX across ZIP, folder, and PDF
- ✅ All features (favorites, selection, spread view) work automatically
- ⚠️ PDF pages are read-only (no export/delete operations)
- ⚠️ Large PDFs may have slower initial page rendering

---

### D007: Spread View with Double Buffering

**Date**: 2026-01-26 (S020/S021)

**Context**: Implementing two-page (spread) display for vertical text/book reading (#55, #67). Simple spread implementation caused visible flicker during page transitions.

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Synchronous loading | No flicker | Blocks UI |
| B | Accept flicker | Simple async | Poor UX |
| C | Double buffering | Smooth transitions | Higher memory |

**Decision**: **Option C** - `SpreadImageViewer` with double-buffered image loading.

**Rationale**:
- Instant visual transitions (no flicker)
- Non-blocking - UI remains responsive during load
- Matches user expectation from traditional image viewers

**Technical Notes**:
```swift
// Two sets of image state
@State private var leftImage: NSImage?
@State private var rightImage: NSImage?
@State private var preparedLeftImage: NSImage?
@State private var preparedRightImage: NSImage?
```

**Consequences**:
- ✅ Smooth page turns even with large images
- ⚠️ Slightly higher memory usage (4 images max vs 2)
- ⚠️ More complex state management

---

### D008: RTL Navigation Key Inversion

**Date**: 2026-01-30 (S026)

**Context**: RTL (right-to-left) reading direction for Japanese vertical text (#54, #76). When layout is reversed, what should ← and → keys do?

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Physical keys | ← = visually left | Confusing page order |
| B | Logical keys | ← = always "previous" | Fights muscle memory |
| C | Invert in RTL | ← = "next" in RTL | Matches reading motion |

**Decision**: **Option C** - Invert navigation keys when `readingDirection == .rtl`

| Key | LTR Mode | RTL Mode |
|-----|----------|----------|
| ← / A | Previous | Next |
| → / D | Next | Previous |

**Rationale**:
- Matches physical reading motion (finger swipe direction)
- Consistent with Japanese text reader apps (ComicGlass, etc.)
- "Previous" always moves toward page 1, "Next" toward last page

**Consequences**:
- ✅ Intuitive for vertical text readers
- ⚠️ May confuse users expecting physical key mapping
- ✅ Per-source setting allows mixing LTR and RTL content

---

### D009: ViewerView with Configurable Thumbnail Sidebar

**Date**: 2026-01-24 (S014)

**Context**: Users wanted to view images without leaving the grid, with quick thumbnail access. Existing modes (Quick Look, Slide Mode) required leaving the grid context.

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Enhance Quick Look | Fewer modes | Limited by sheet constraints |
| B | Grid overlay | In-place viewing | Complex layout |
| C | New ViewerView mode | Full-featured | Third viewing mode |

**Decision**: **Option C** - Add `ViewerView` as an in-grid viewer with optional thumbnail sidebar.

| Position | Layout | Use Case |
|----------|--------|----------|
| `.left` | Vertical strip | Wide monitors |
| `.bottom` | Horizontal strip | Standard monitors |
| `.hidden` | No thumbnails | Maximum image area |

Cycle with `Ctrl+T`.

**Rationale**:
- Maintains grid context while viewing
- Thumbnail sidebar enables quick jumping
- Position preference saved per-session

**Consequences**:
- ✅ Smooth workflow without mode switching
- ✅ Quick thumbnail access for navigation
- ⚠️ Adds complexity to ThumbnailGridView
- ⚠️ Three viewing modes to maintain

---

### D010: Direction-Aware Image Prefetching

**Date**: 2026-01-24 (S016)

**Context**: Reducing perceived latency when navigating images. Loading full-resolution images on demand caused noticeable delay.

**Options Considered**:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | No prefetch | Simple | Visible loading delay |
| B | Fixed prefetch (both directions) | Predictable | Wasted resources |
| C | Direction-aware prefetch | Efficient | More complex |

**Decision**: **Option C** - Implement `ImagePrefetcher` with direction-aware LRU cache.

| Feature | Implementation |
|---------|----------------|
| Cache size | Configurable (default: 5 images) |
| Prefetch direction | Based on recent navigation |
| Cancellation | Abort outdated prefetch tasks |
| Thread safety | Serial queue for cache operations |

**Rationale**:
- Users typically navigate sequentially (forward or backward)
- Prefetching in travel direction maximizes cache hits
- LRU eviction keeps memory bounded

**Consequences**:
- ✅ Near-instant image display during sequential navigation
- ✅ Memory usage proportional to prefetchCount
- ⚠️ Wasted prefetch if user jumps randomly (acceptable trade-off)

---

## Deferred Decisions

### Export Directory Structure

**Status**: Deferred to Phase 2

**Current thinking**: `./erimil/exclude/<ZIP_NAME>/`

**Open questions**:
- Relative to ZIP location or configurable base path?
- What if ZIP name contains special characters?
- Flat structure or preserve internal ZIP paths?

---

### kurumil Integration

**Status**: Deferred to Phase 3

**Options being considered**:
- A) Erimil calls kurumil directly (requires kurumil path config)
- B) Output folder designed for easy kurumil input
- C) Shell pipeline / Unix integration
- D) Shared config file for DDL tools

**Current direction**: Phase 1 outputs to folder, user manually runs kurumil

---

### Additional Archive Formats

**Status**: Deferred to Phase 3

**Candidates**: tar.gz, 7z, rar, tar.xz

**Dependencies**: 
- 7z/rar may require external libraries or binaries
- tar.gz is simpler (native Swift support possible)

---

## Discussion Log

### 2025-12-13: Initial Planning Session

**Participants**: Zem, Claude

**Topic**: Whether to build or use existing tools

**Discussion**:
- Existing tools (BetterZip, Keka) don't provide visual selection workflow
- User's specific need: pre-filter images before kurumil upscaling
- Frequency is low, but pain point is real
- Decision: Build, as part of DDL portfolio and kurumil ecosystem

**Topic**: Core workflow definition

**Discussion**:
- Left pane: folder tree with ZIP recognition
- Right pane: thumbnail grid of selected ZIP contents
- Actions: mark for exclusion, confirm to generate optimized ZIP
- Safety: confirm dialog on navigation with unsaved changes

**Key quotes**:
- "アップスケールすると容量ふえると思いますが、これぞ！というだけ残したり、前処理として、アップスケール不要なものを排除したい"
- "消すのは怖いので" (regarding in-place editing)
- "Quick Look の拡大表示だけ欲しい...結局Zip展開してしまっては意味が無い"

---

### 2025-12-14: Phase 2 Planning Session

**Participants**: Zem, Claude

**Topic**: Extending to folder browsing

**Discussion**:
- User requested folder image browsing in addition to ZIP files
- Use case: Factorio screenshots organized by date, want to archive selected ones
- Natural extension of existing workflow
- Decision: Add FolderManager with same ImageSource protocol

**Topic**: Folder operations

**Discussion**:
- Two operations needed: ZIP creation (archive selected) and delete (cleanup)
- Delete must be Trash-only for safety
- Dynamic footer buttons based on source type

**Topic**: Navigation UI for mixed sources

**Discussion**:
- Problem: folder click could mean "expand" or "view contents"
- Solution: Finder-style UI (▶ for expand, row click for view)
- Consistent behavior for both ZIP and folders
- Reference: macOS Finder sidebar behavior

**Priority order**:
1. Settings panel (enables defaults for other features)
2. ImageSource abstraction + FolderManager
3. Finder-style navigation
4. Selection mode toggle
5. Folder operations (ZIP/Delete)

---

### 2025-12-14: Phase 2.1 Planning Session

**Participants**: Zem, Claude

**Topic**: UX improvements from real usage

**Discussion**:
User feedback after using Phase 2:
- Thumbnails too small for large displays
- Want keyboard-driven workflow
- Need favorites to prevent accidental deletion
- Cache would improve perceived performance

**Topic**: Thumbnail sizing

**Decision**:
- Add to Settings + UI slider
- Presets: Small (80px), Medium (120px), Large (180px), Custom

**Topic**: Favorite feature requirements

**Discussion**:
- Primary purpose: prevent accidental deletion (safety)
- Secondary: mark important images for later
- Must persist across sessions and file moves
- ★ visual indicator on thumbnails

**Topic**: Privacy-first metadata design

**Discussion**:
- Concern: storing paths reveals folder structure, dates, project names
- Solution: hash everything (both paths and content)
- Content hash enables: favorite migration on file move, deduplication
- Path hash enables: fast lookup without exposing structure

**Data location decision**:
- `~/Library/Application Support/Erimil/` (Apple recommended)
- Follows same pattern as Finder, Photos.app, etc.

**Topic**: Keyboard shortcuts

**Initial mapping**:
- `wasd` or arrow keys: navigate thumbnails
- `x`: toggle selection (exclude/keep)
- `v`: toggle favorite
- `Space`: preview
- `Enter`: close preview

Future (Phase 2.2):
- `a/f`: previous/next in slide mode
- `z/c`: previous/next favorite
- `Shift-A/F`: previous/next source

**Phase 2.1 scope (confirmed)**:
1. Thumbnail size adjustment
2. Cache infrastructure (hash calculation + Application Support storage)
3. Keyboard navigation (wasd/arrows + x selection)
4. Space key preview
5. Favorite feature (v toggle, ★ display, delete protection)

---

## References

- [kurumil repository](https://github.com/zembutsu/kurumil)
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [Tsubame DESIGN.md](https://github.com/zembutsu/tsubame) - Methodology origin
- Project Documentation Methodology v0.1.0

---

## Template Information

> Based on **Project Documentation Methodology** v0.1.0
> Document started: 2025-12-13
> Last updated: 2026-01-31 (S029: D004-D010 added)
