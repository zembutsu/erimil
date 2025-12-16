# Erimil Design Document

This document records significant design decisions with their context and rationale.

---

## D001: Two-step Export with Safety Focus

**Date**: 2025-12-13  
**Context**: How to handle file modifications safely

### Decision

Export creates a new `_opt.zip` file instead of modifying the original.

### Rationale

- Original files remain untouched (safety first)
- Easy to compare before/after
- No risk of data loss from bugs or user error
- Matches user mental model of "export" vs "edit"

### Consequences

- Requires disk space for both files
- User must manually delete original if desired
- Clear separation of source and output

---

## D002: Selection State Scope

**Date**: 2025-12-14  
**Context**: Where to store selectedPaths state for unsaved changes detection

### Problem

After refactoring to use ImageSource abstraction, the "unsaved changes" detection was showing false positives because the state was scoped to the wrong component.

### Decision

Move `selectedPaths` state from `ThumbnailGridView` to `ContentView` (parent).

### Rationale

- `ContentView` is the navigation coordinator
- It knows when sources change
- It can properly reset state on source change
- It can accurately detect "has user made changes?"

### Consequences

- `ThumbnailGridView` receives `@Binding` instead of owning state
- Cleaner separation: grid displays, parent coordinates
- Accurate unsaved changes detection

---

## D003: Hybrid Favorites System

**Date**: 2025-12-15  
**Context**: How to track favorites across different sources (ZIP/folder) while handling duplicates

### Problem

Users want to:
1. Mark favorites that persist when reopening the same source
2. Recognize the same image even if it appears in different ZIPs
3. See visual distinction between "I favorited this here" vs "this is a duplicate of something I favorited elsewhere"

### Options Considered

1. **Path-only**: Simple but doesn't recognize duplicates
2. **Hash-only**: Recognizes duplicates but loses source specificity
3. **Hybrid**: Both path and hash tracking

### Decision

**Option 3**: Hybrid system with two storage mechanisms:

| Type | Storage Key | Display | Meaning |
|------|-------------|---------|---------|
| Direct | sourceURL + entryPath | ★ (black star) | "I favorited this specific file" |
| Inherited | contentHash | ☆ (white star) | "Same content as something I favorited" |

### Rationale

- Covers all user mental models
- No false negatives (if you favorited it anywhere, you see indication)
- Clear visual distinction prevents confusion
- Content hash enables cross-source recognition

### Consequences

- More complex storage (two lookup paths)
- Hash calculation required (handled by existing cache)
- UI must distinguish ★ vs ☆

### Technical Notes

- Direct favorites stored as: `hash(sourceURL + entryPath)`
- Inherited lookup via: `contentHash`
- Direct always takes precedence over Inherited

---

## D004: Security-Scoped Bookmarks for Folder Persistence

**Date**: 2025-12-15  
**Context**: Restoring last opened folder on app launch in sandboxed environment

### Problem

UserDefaults can store the folder path, but sandbox prevents accessing it without user re-granting permission.

### Decision

Use Security-Scoped Bookmarks instead of plain URL storage.

### Rationale

- Only sandbox-compliant way to persist file access
- Standard Apple-recommended approach
- Works across app launches

### Consequences

- More complex than simple UserDefaults
- Bookmark can become stale (file moved/deleted)
- Must handle bookmark resolution failures gracefully

### Technical Notes

```swift
// Save
let bookmark = try url.bookmarkData(options: .withSecurityScope, ...)

// Restore  
var isStale = false
let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
_ = url.startAccessingSecurityScopedResource()
```

---

## D005: Mode Definitions & Component Architecture

**Date**: 2025-12-17  
**Context**: Phase 2.2 implementation - need to clarify "preview" vs "slide mode" distinction

### Problem

The terms "Quick Look" and "Slide Mode" were ambiguous. Risk of:
- Duplicate implementation for similar features
- Unclear user mental model
- Scattered viewer logic across multiple components

### Options Considered

1. **Single fullscreen-capable view** - One component that toggles between windowed/fullscreen
2. **Separate implementations** - Two completely independent viewers
3. **Shared core with mode-specific containers** - Common viewer logic, different window types

### Decision

**Option 3**: Two-mode system with shared ImageViewerCore component

| Mode | Purpose | Trigger | Container | Window Type |
|------|---------|---------|-----------|-------------|
| Quick Look | Selection/triage work | Space key | ImagePreviewView | Sheet |
| Slide Mode | Immersive viewing | f key | SlideWindowView | NSWindow (fullscreen) |

**Component Architecture**:
```
ImageViewerCore (shared)
├── Image display & loading
├── Navigation logic (a/d, z/c)
├── Position indicator
└── Favorite indices handling

Containers:
├── ImagePreviewView (Quick Look)
│   └── Sheet-based, header with controls
└── SlideWindowView (Slide Mode)
    └── NSWindow, auto-hide controls overlay
```

### Rationale

- **Single source of truth**: Navigation logic lives in one place
- **Platform constraints**: macOS Sheet cannot use `toggleFullScreen()`, requiring separate NSWindow
- **User mental model**: Clear distinction - Quick Look for work, Slide Mode for viewing
- **Extensibility**: Easy to add new modes without duplicating core logic

### Consequences

**Positive**:
- DRY principle maintained
- Clear separation of concerns
- Easy to test core logic independently

**Negative**:
- favoriteIndices must be passed from parent (computed each render)
- Slight complexity in state synchronization between modes

### Technical Notes

- `fullScreenCover()` is iOS-only, not available on macOS
- Sheet windows are attached to parent and cannot toggle fullscreen
- NSWindow requires explicit cleanup (`orderOut` + `close`) to avoid lingering UI

---

## Future Decisions

Reserved for future design decisions as they arise.
