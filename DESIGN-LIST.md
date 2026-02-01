# Erimil Design Decisions Index

Quick reference for all design decisions. See **DESIGN.md** for full details.

---

## Decision Index

| ID | Date | Title | Summary |
|----|------|-------|---------|
| Decision 1 | 2025-12-13 | ZIP Editing Strategy | Create `_opt.zip` instead of modifying original |
| Decision 2 | 2025-12-13 | Selection Mode | Select to exclude as default, safer failure mode |
| Decision 3 | 2025-12-13 | Original File Handling | Leave original untouched after export |
| Decision 4 | 2025-12-13 | Preview Functionality | Click-to-enlarge with modal preview |
| Decision 5 | 2025-12-13 | Application Name | "Erimil" (選り見る) - visual selection |
| Decision 6 | 2025-12-13 | ZIPFoundation Usage | Open Archive per-operation pattern |
| Decision 7 | 2025-12-13 | Sandbox File Access | NSSavePanel for export location |
| Decision 8 | 2025-12-14 | ImageSource Abstraction | Protocol for ZIP/Folder/PDF unified handling |
| Decision 9 | 2025-12-14 | Finder-style Navigation | OutlineGroup with ▶ disclosure, row click for content |
| Decision 10 | 2025-12-14 | Folder Operations | ZIP creation and delete-to-Trash for folders |
| Decision 11 | 2025-12-15 | Cache Storage Location | Application Support directory for sandbox compliance |
| Decision 12 | 2025-12-15 | Hash-Based Privacy | Content hash for favorites, no filename exposure |
| Decision 13 | 2025-12-15 | Hybrid Favorites | ★ direct + ☆ inherited, path + hash tracking |
| Decision 14 | 2025-12-16 | Phase-based Versioning | Version bump at phase boundaries only |
| D004 | 2025-12-15 | Security-Scoped Bookmarks | Persist folder access across app launches |
| D005 | 2025-12-17 | Mode Definitions | Quick Look (sheet) vs Slide Mode (NSWindow) architecture |
| D006 | 2026-01-29 | PDF as ImageSource | PDFManager implements ImageSource protocol |
| D007 | 2026-01-26 | Spread View Double Buffering | Prepare next spread off-screen for instant transitions |
| D008 | 2026-01-30 | RTL Navigation Key Inversion | ←/→ keys inverted in RTL mode for natural reading |
| D009 | 2026-01-24 | ViewerView Thumbnail Sidebar | In-grid viewer with left/bottom/hidden positions |
| D010 | 2026-01-24 | Direction-Aware Prefetching | LRU cache prefetches in travel direction |

---

## ID Mapping Notes

Early decisions used "Decision N" format. Newer decisions use "DXXX" format for brevity.

| Old ID | New ID | Notes |
|--------|--------|-------|
| - | D001 | Equivalent to Decision 1 |
| - | D002 | Selection state scope refinement |
| - | D003 | Equivalent to Decision 13 |

D001-D003 were transitional and are now consolidated into the main Decision series.

---

## By Category

### Core Architecture
- Decision 8: ImageSource Abstraction
- D005: Mode Definitions
- D006: PDF as ImageSource

### User Interface
- Decision 9: Finder-style Navigation
- D007: Spread View Double Buffering
- D009: ViewerView Thumbnail Sidebar

### Data & Storage
- Decision 11: Cache Storage Location
- Decision 12: Hash-Based Privacy
- Decision 13: Hybrid Favorites
- D004: Security-Scoped Bookmarks

### Navigation & Input
- D008: RTL Navigation Key Inversion
- D010: Direction-Aware Prefetching

### Safety & Operations
- Decision 1: ZIP Editing Strategy
- Decision 2: Selection Mode
- Decision 3: Original File Handling
- Decision 10: Folder Operations

---

> See **DESIGN.md** for full rationale, options considered, and consequences.
