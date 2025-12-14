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

**Erimil** (選り見る) is a macOS application that provides visual preview and selective extraction/deletion of images within ZIP archives.

Part of the **DDL (Do Different Lab)** tool family, designed to work alongside [kurumil](https://github.com/zembutsu/kurumil) for image processing workflows.

### Problems Solved

- **Pre-processing bottleneck**: Before upscaling with kurumil, users need to filter out unnecessary images to save processing time and storage
- **Blind archive management**: Standard tools require full extraction to preview contents
- **Tedious selection**: No visual way to mark multiple files for removal across archives

### Design Philosophy

- **Safety First**: Non-destructive by default, explicit confirmation for all changes
- **Visual Workflow**: See what you're selecting, not just filenames  
- **Unix Philosophy**: Do one thing well, integrate with other tools (kurumil)
- **Minimal Friction**: Drag & drop, keyboard shortcuts, no unnecessary dialogs

## Current Status

- **Version**: 0.1.0 (unreleased)
- **Phase**: Phase 2 Development
- **Phase 1**: ✅ Completed (2025-12-13)

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

### Phase 2 (In Progress)
- Folder viewer (browse images in folders, not just ZIPs)
- Folder operations: ZIP creation, delete to Trash
- Settings panel (output path, selection mode default)
- Selection mode toggle (exclude vs keep)
- Finder-style UI (▶ for expand, row click for content view)
- ImageSource abstraction (unified ZIP/Folder handling)

### Phase 3 (Planned)
- Additional archive formats (tar.gz, 7z, rar)
- kurumil direct integration
- Batch processing multiple ZIPs

## For Automated Systems

When working on this project:

1. Read **ARCHITECTURE.md** to understand code structure
2. Read **WORKFLOW.md** to understand development process
3. Read **DESIGN.md** to understand why decisions were made
4. Check **GitHub Issues** for current tasks and plans
5. Use SwiftUI + ZIPFoundation as primary technologies
6. Follow safety-first principle: never implement destructive operations without explicit confirmation

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

- GitHub: https://github.com/zembutsu/erimil (planned)
- Issues: https://github.com/zembutsu/erimil/issues (planned)

## Related Projects

- [kurumil](https://github.com/zembutsu/kurumil) - Image compression and AI upscaling CLI tool
- [Tsubame](https://github.com/zembutsu/tsubame) - macOS window management (methodology origin)

---

## Template Information

> Based on **Project Documentation Methodology** v0.1.0
> Project started: 2025-12-13
