# Erimil Project

This document is the entry point for developers and automated systems working on this project.

## Document Structure

| Document | Audience | Content |
|----------|----------|---------|
| **PROJECT.md** (this) | Developers, Systems | Project overview, principles, design philosophy |
| README.md | Users | Installation, usage, features |
| ARCHITECTURE.md | Developers, Systems | Technical structure, data flow, design decisions |
| DESIGN.md | Developers | Design rationale, trade-offs, alternatives considered |
| WORKFLOW.md | Developers, Systems | Development process, AI collaboration |
| CHANGELOG.md | Everyone | Version history, changes |

## Project Vision

**Erimil** (選り見る) is a macOS image curation tool. Browse, evaluate, mark, and export — across ZIP archives, folders, and PDFs. Keyboard-driven, lightweight, focused.

Part of the **DDL (Do Different Lab)** tool family, designed to work alongside [kurumil](https://github.com/zembutsu/kurumil) for image processing workflows.

### Core Principle

**「選り見る」= selectively view and curate.**

Erimil is not a viewer, not a manager, not an editor. It is a tool for **deciding what's worth keeping** — then getting out of your way.

### Problems Solved

- **Pre-processing bottleneck**: Before upscaling with kurumil, users need to filter out unnecessary images to save processing time and storage
- **Blind archive management**: Standard tools require full extraction to preview contents
- **Tedious selection**: No visual way to mark multiple files for removal across archives
- **Fragmented workflows**: ZIP, folder, and PDF images require different apps to browse and curate

### Design Philosophy

- **Safety First**: Non-destructive by default, explicit confirmation for all changes
- **Visual Workflow**: See what you're selecting, not just filenames  
- **Keyboard-Driven**: Every action reachable without a mouse
- **Unix Philosophy**: Do one thing well, integrate with other tools (kurumil)
- **Minimal Friction**: Drag & drop, keyboard shortcuts, no unnecessary dialogs

### What Erimil Does NOT Do

- Edit images (hand off to external editors)
- Manage a library or database
- Sync to the cloud
- Replace Lightroom, Photos, or any DAM

These boundaries are intentional. Features that don't serve "browse → evaluate → mark → export" don't belong here.

## Current Status

- **Version**: 0.3.4 (released), 0.3.5 (in progress)
- **Phase 1**: ✅ Completed (2025-12-13)
- **Phase 2**: ✅ Completed (2025-12-14)
- **Phase 2.1**: ✅ Completed (2025-12-16)
- **Phase 2.2**: ✅ Completed (2025-12-17)
- **Phase 2.3**: ✅ Completed (2026-01-31)
- **Phase 2.4**: ✅ Completed (2026-03-21)

## Development Principles

### 1. Safety by Default

All operations are non-destructive unless explicitly configured otherwise:
- Original ZIP files are never modified
- New optimized archives are created with `_opt.zip` suffix
- Unsaved changes prompt confirmation before navigation

### 2. Visual-First Design

Users should see images, not just filenames:
- Thumbnail grid for quick scanning
- Click-to-enlarge preview for detail inspection
- Visual markers for selection state (excluded items clearly indicated)

### 3. System-Assisted Development

This project uses AI-assisted development following the WORKFLOW.md guidelines:
- Human defines goals and approves approaches
- System proposes implementation and executes
- Human reviews, tests, and commits
- All decisions documented in DESIGN.md

## Roadmap

### Phase 1 (MVP) - ✅ Completed (2025-12-13)
- ✅ Folder tree navigation with ZIP recognition
- ✅ Thumbnail grid display
- ✅ Click-to-enlarge preview (Quick Look style)
- ✅ Selection for exclusion (select = exclude)
- ✅ Confirm → generate `{name}_opt.zip`
- ✅ Unsaved changes confirmation dialog
- ✅ Auto-reload folder tree after export

### Phase 2 - ✅ Completed (2025-12-14)
- ✅ Folder viewer (browse images in folders, not just ZIPs)
- ✅ Folder operations: ZIP creation, delete to Trash
- ✅ Settings panel (output path, selection mode default)
- ✅ Selection mode toggle (exclude vs keep)
- ✅ Finder-style UI (▶ for expand, row click for content view)
- ✅ ImageSource abstraction (unified ZIP/Folder handling)

### Phase 2.1 - ✅ Completed (2025-12-16) - UX Improvements
- ✅ Thumbnail size adjustment (Settings + UI slider)
- ✅ Cache infrastructure (hash-based, Application Support storage)
- ✅ Keyboard navigation (wasd/arrows, x for selection)
- ✅ Space key preview (window-based)
- ✅ Favorite feature (★/☆ hybrid, delete protection, v toggle)

### Phase 2.2 - ✅ Completed (2025-12-17) - Slide Mode
- ✅ Quick Look mode (Space key opens sheet preview)
- ✅ Slide Mode (f key opens fullscreen NSWindow)
- ✅ a/d and arrow keys for image navigation
- ✅ z/c for favorite jump navigation
- ✅ Position indicator (1/N) in both modes
- ✅ Auto-hide controls in Slide Mode

### Phase 2.3 - ✅ Completed (2026-01-31) - Extended Viewing
- ✅ PDF support (view PDF as image sequence)
- ✅ Spread (two-page) view for books
- ✅ RTL (right-to-left) reading direction
- ✅ ViewerView with configurable thumbnail sidebar
- ✅ Image prefetching for smooth navigation
- ✅ Single page markers (V key)
- ✅ Per-source settings (position, direction, markers)
- ✅ Bookmark (栞) system with named sections
- ✅ os.Logger migration (structured logging)
- ✅ Logger privacy hardening
- ✅ Hybrid ★ auto-protect behavior for export vs delete (#103)
- ✅ Record ★ on both pages in spread view (#104)
- ✅ Metadata carry-over on export with per-export selection (#105)
- ✅ Thumbnail performance: OperationQueue prefetch, PDF cache fix (#134)
- ✅ Grid flash elimination on Viewer Mode source switch (#122)
- ✅ Stale thumbnail fix on source switch (#127)
- ✅ Spread view misalign on favorite navigation (#129)
- ✅ Empty source feedback on Viewer/Full Mode entry (#131)
- ✅ Selection tap delay: double-tap gesture removal (#138 partial)
- 🔄 PDF page export — PDF/PNG (#100)
- 🔄 Deskew display correction for scanned PDFs (#101)

### Phase 2.4 - ✅ Completed (2026-03-21) - Performance & Automation
- ✅ Startup time optimization: 16.7s → 2ms via FolderNode lazy loading (#216)
- ✅ CacheManager async initialization (#216)
- ✅ Auto-Slide mode with multi-speed tap control (#172)
- ✅ Auto-Slide reverse playback (#178)
- ✅ Animated GIF playback in Viewer and Slide Modes (#201)
- ✅ Metadata inspector panel — "i" key (#140)
- ✅ Tile-based thumbnail cache for ZIP/PDF archives (#24)
- ✅ Thumbnail quality presets with Retina support (#207)
- ✅ Grid spacing setting (#212)
- ✅ N-step navigation with Ctrl+Option (#143)
- ✅ Cmd+A select/deselect all (#164)
- ✅ 3-level overlay controls in Slide Mode (#151)
- ✅ Auto-hide mouse cursor in Slide Mode (#145)
- ✅ Render-gated navigation for favorites (#154)
- ✅ Thumbnail cache format: .ecache with CGImageDestination (#146)
- ✅ ThumbnailGridView refactored into 4 files (#175)
- ✅ Key handling consolidated into CommonKeyParser (#169)
- ✅ QuickLook deprecated in favor of Auto-Slide (#176)
- ✅ Selection tap delay: .id() fix + ThumbnailCoalescer (#138)
- ✅ Export data loss prevention (#161) and empty export prevention (#163)
- ✅ Grid scroll follows focus in real-time (#158)
- ✅ Various bug fixes (#144, #150, #165, #193, #194, #195, #196)
- ✅ Hyperscaler PoC: CoreML Real-ESRGAN super-resolution (#40)

### v0.3.5 (In Progress) - Architecture & UX
- ✅ NSCollectionView + HSplitView migration — resolves #126, #209, #215 (#215)
- ✅ Full i18n / localization infrastructure (#244)
- ✅ Edge-click navigation (#255)
- ✅ Option+key N-step Navigation (#257)
- ✅ Ctrl+Option+W/S source switch across all modes (#259)
- ✅ Grid Source N-step navigation (#260)
- 🔄 "/" command palette replacing inline help tooltips (#139)
- 🔄 Show non-image items in Grid view (#132)
- 🔄 Grid view filtering and sorting (#97)
- 🔄 Drag & drop files to open directly in Viewer/Slide mode (#63)
- 🔄 PDF file support enhancements (#57)
- 🔄 Extract SlideWindowController.open helper (#50)
- 🔄 Tab Key mode switching in Grid Mode (#199)
- 🔄 Individual .ecache cleanup after tile sheet build (#208)
- 🔄 Thread safety: first-writer-wins Bool flags (#210)
- 🔄 Tile sheet incremental rebuild (#211)

### Phase 3 (Next) - Curation Quality
- Grid filtering (filename search) and sorting (name, size, date, ★)
- `.erimil.dat` sidecar for portable metadata
- kurumil CLI integration (post-export optimization)

### Phase 4 (Planned) - Broader Format & Display
- RAW format support (via ImageIO: CR2/CR3, NEF, ARW, DNG, etc.)
- EXIF metadata overlay
- GPU-accelerated display (Core Image pipeline)
- Additional archive formats (tar.gz, 7z, rar)

### Phase 5 (Planned) - Release Readiness
- i18n (English / Japanese)
- Accessibility (VoiceOver basic support)
- App Store preparation

### v1.0 Release Criteria
- All Phase 3-5 features complete
- i18n (en/ja)
- RAW format support for major cameras
- Accessibility baseline
- Privacy policy and support URL

### Future Direction

Erimil aims to become a **professional-grade image curation tool** — a lightweight, keyboard-driven alternative for the "browse → evaluate → mark → export" workflow. Potential areas include star rating (0-5), color labels, comparison mode, and XMP sidecar output for interoperability with professional tools.

All future additions must pass the test: **does this make "選り見る" faster or better?** If not, it doesn't belong here. See GitHub Issues for detailed proposals and discussion.

## For Automated Systems

When working on this project:

1. Read **ARCHITECTURE.md** to understand code structure
2. Read **WORKFLOW.md** to understand development process
3. Read **DESIGN.md** to understand why decisions were made
4. Check **GitHub Issues** for current tasks and plans
5. Use SwiftUI + ZIPFoundation as primary technologies
6. Follow safety-first principle: never implement destructive operations without explicit confirmation

### Agent Rules (Bebop Style Development)

This project follows **Bebop Style Development** — a methodology where human and AI collaborate as equal "Voices" in a session.

**Session Awareness**:
- Development happens in numbered sessions (S001, S002, ...). Each session has a log under `docs/sessions/`
- Always check the latest session log's **Handoff Bridge** for carry-forward items and warnings
- Do not assume context from prior sessions without reading the relevant log

**Coding Constraints**:
- Propose implementation approach before large changes; small fixes can be applied directly
- Never modify files outside the Erimil Xcode project without explicit approval
- Test builds must pass (`xcodebuild` or Xcode) before considering a task complete
- Commit messages follow: `type: description` (feat, fix, refactor, docs, chore)

**Scope Discipline**:
- Erimil is "選り見る" (view & select), not an editor. Do not add features outside browse → evaluate → mark → export
- Respect the **Parked** items in session logs — deferred topics are deferred for a reason
- When in doubt about scope, ask rather than implement

**Documentation**:
- Design decisions go in DESIGN.md, not in code comments
- Architecture changes require ARCHITECTURE.md updates in the same commit
- CHANGELOG.md is updated per release, not per commit

## Technical Overview

| Aspect | Choice |
|--------|--------|
| Platform | macOS 14+ (Sonoma) |
| UI Framework | SwiftUI |
| ZIP Library | ZIPFoundation |
| Language | Swift |
| License | MIT |
| Distribution | GitHub Release (initial) |

## Repository

- GitHub: https://github.com/zembutsu/erimil
- Issues: https://github.com/zembutsu/erimil/issues

## Related Projects

- [kurumil](https://github.com/zembutsu/kurumil) - Image compression and AI upscaling CLI tool
- [Tsubame](https://github.com/zembutsu/tsubame) - macOS window management (methodology origin)

---

## Template Information

> Based on **Project Documentation Methodology** v0.1.0
> Project started: 2025-12-13
