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

## References

- [kurumil repository](https://github.com/zembutsu/kurumil)
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [Tsubame DESIGN.md](https://github.com/zembutsu/tsubame) - Methodology origin
- Project Documentation Methodology v0.1.0

---

## Template Information

> Based on **Project Documentation Methodology** v0.1.0
> Document started: 2025-12-13
