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

## References

- [kurumil repository](https://github.com/zembutsu/kurumil)
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [Tsubame DESIGN.md](https://github.com/zembutsu/tsubame) - Methodology origin
- Project Documentation Methodology v0.1.0

---

## Template Information

> Based on **Project Documentation Methodology** v0.1.0
> Document started: 2025-12-13
