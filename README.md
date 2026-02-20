# Erimil (選り見る)

A macOS image distillation tool — browse, curate, and refine image collections from ZIP archives, PDFs, and folders with iterative ★ favorites workflow. Keyboard-driven, RTL-aware, privacy-first.

<!-- screenshots: thumbnail grid + slide mode spread view -->

## Why Erimil?

Most archive tools let you extract files. Most image viewers let you browse.
Erimil does something different: **iterative visual distillation**.

```
photos.zip (100 images)
    → Browse, mark ★ favorites (protected from deletion)
    → Export → photos_opt.zip (50 images)
        → ★ metadata carried over — see what you liked before
        → Refine selection, mark new ★
        → Export → photos_opt_opt.zip (20 images) = Best Selection
```

Each pass refines your collection. ★ favorites are protected from deletion,
and their metadata carries over to exported archives so you can build on previous rounds.

## Features

- **Iterative Distillation**: ★ favorites with deletion protection and metadata carry-over on export
- **Multi-Format Sources**: ZIP archives, folders, and PDFs — unified browsing
- **Spread View**: Two-page display for books with RTL (right-to-left) support
- **PDF Page Export**: Export selected pages as optimized PDF, PNG folder, or PNG ZIP
- **Bookmarks (栞)**: Named position markers for quick navigation within sources
- **Keyboard-Driven**: Every action reachable without a mouse
- **Privacy-First**: No telemetry, no cloud, no network — your files stay local

## Installation

**Requirements**: macOS 14.0 (Sonoma) or later

Download the latest release from [GitHub Releases](https://github.com/zembutsu/erimil/releases).

**Erimil is open source.** You can clone the repository and build it yourself with Xcode.

## Quick Start

1. Drag a folder containing ZIPs to the sidebar, or use File → Open
2. Click a source (ZIP / folder / PDF) to view thumbnails
3. Navigate with arrow keys or WASD, mark favorites with `F`
4. Select images to exclude with `X` (or keep, depending on mode)
5. Click export to generate optimized archive

**Selection Modes**: Toggle between Exclude Mode (mark items to remove) and Keep Mode (mark items to retain) via the toolbar or Settings.

**Viewer Modes**: Press `Enter` or `R` for Viewer Mode with thumbnail sidebar, `Ctrl+F` for fullscreen Slide Mode, `Space` for Quick Look preview.

<details>
<summary>📖 Full Keyboard Shortcuts Reference</summary>

### Common Navigation (All Viewer Modes)

All navigation keys are **RTL-aware** — they follow "physical key position = visual screen position" principle.

| Key | Action |
|-----|--------|
| ← → ↑ ↓ / WASD | Navigate images |
| Z / C | Previous / Next favorite ★ |
| Ctrl+A / Ctrl+D | Jump to first / last image |
| Ctrl+Z / Ctrl+C | Jump to first / last favorite |
| Cmd+1/2/3/4/5 | Jump to 0% / 25% / 50% / 75% / 100% |
| Ctrl+R | Toggle reading direction (LTR ↔ RTL) |
| Shift+S | Add / delete bookmark (栞) |
| Shift+A / Shift+D | Previous / Next bookmark |
| Shift+B | Bookmark list overlay |

### Filer View (Thumbnail Grid)

| Key | Action |
|-----|--------|
| X | Toggle selection |
| F | Toggle favorite ★ |
| V | Toggle single page marker |
| Space | Open Quick Look preview |
| Enter / R | Open Viewer Mode |
| Ctrl+F | Open Slide Mode |
| Ctrl+W/S or Ctrl+↑/↓ | Previous / Next source |

### Quick Look Preview

| Key | Action |
|-----|--------|
| F | Switch to Slide Mode |
| V | Toggle single page marker |
| Q / Space / Esc / Enter | Close preview |

### Viewer Mode

| Key | Action |
|-----|--------|
| X | Toggle selection |
| F | Toggle favorite ★ |
| V | Toggle single page marker |
| T | Cycle thumbnail position |
| Enter | Open Slide Mode |
| Q / R / Esc | Close (return to Filer) |
| Ctrl+W/S or Ctrl+↑/↓ | Previous / Next source |

### Slide Mode (Fullscreen)

| Key | Normal Mode | Favorites Mode |
|-----|-------------|----------------|
| ← → ↑ ↓ / WASD | Previous/Next image | Previous/Next ★ |
| Z / C | Previous/Next ★ | Previous/Next ★ |
| Tab | Next ★ + **Enter Favorites Mode** | Next ★ |
| F | Toggle favorite ★ | Toggle favorite ★ |
| X | Toggle selection | Toggle selection |
| V | Toggle single page marker | Toggle single page marker |
| Q | Exit fullscreen | Exit Favorites Mode |
| Esc | Exit fullscreen | Exit fullscreen |
| Ctrl+W/S or Ctrl+↑/↓ | Previous/Next source | Same |
| Ctrl+T | Cycle thumbnail position | Same |
| Shift+S | Add/delete bookmark (栞) | Same |
| Shift+A / Shift+D | Previous/Next bookmark | Same |
| Shift+B | Bookmark list overlay | Same |
| Space | Toggle controls | Toggle controls |

### Sidebar Navigation

| Action | Result |
|--------|--------|
| Single-click | Select source, show thumbnails |
| Double-click | Select source + open Slide Mode |

</details>

## Advanced Features

### Favorites System (★)

Press `F` to mark an image as ★ favorite. Favorites are **protected from deletion** in Exclude mode — selecting a ★ image shows a "PROTECTED" label and the selection is blocked.

Favorites metadata is carried over when exporting, so you can see your previous selections when reopening an exported archive. This enables iterative refinement across multiple export passes.

### Bookmarks (栞) System

Bookmarks are named position markers within a source for quick navigation.

- **Shift+S**: Add a bookmark at current position (with custom name) or delete existing bookmark
- **Shift+A/D**: Navigate between bookmarks (wraps around, RTL-aware)
- **Shift+B**: Open bookmark list overlay for browsing and jumping
- **Grid View**: Bookmark dividers appear as section headers between thumbnails

Bookmarks are stored per-source and persist across sessions. Mnemonic: Shift = Shiori (栞).

### Spread View (Two-Page Display)

Enable in Settings to display two pages side-by-side — ideal for book reading.

- RTL (right-to-left) direction support for Japanese vertical text
- Wide images automatically displayed as single pages
- Press `V` to manually mark/unmark pages as single
- Per-source settings for reading direction and single page markers

### PDF Export

For PDF sources, the export button offers three formats:

| Format | Output | Use Case |
|--------|--------|----------|
| **PDF** (primary) | `{name}_opt.pdf` | Selected pages as new PDF |
| **PNG folder** | `{name}_pages/` | Individual PNG files (300dpi) |
| **PNG ZIP** | `{name}_png.zip` | PNG files packaged in ZIP (300dpi) |

Exported pages preserve original page numbers (e.g., `page_001.png, page_003.png` with gaps where pages were excluded). Metadata (★ favorites, 栞 bookmarks, reading direction, markers) is carried over to the new file.

### Slide Mode Details

**Position Indicators**: Image position bar shows current position with ★ and × markers. Source position bar shows position among sibling sources in the directory.

**Favorites Mode**: Press `Tab` to enter — navigation keys move between favorites only. Yellow header indicates active. Press `Q` to exit back to normal navigation.

**Source Navigation**: `Ctrl+W/S` or `Ctrl+↑/↓` switches between sources while maintaining fullscreen state. Loops from last to first.

**Position Jump**: `Ctrl+A/D` for first/last, `Ctrl+Z/C` for first/last favorite, `Cmd+1-5` for percentage positions. All jumps are RTL-aware.

## Data Storage

Erimil stores cache and favorites in the sandboxed container:

```
~/Library/Containers/jp.pocketstudio.zem.Erimil/Data/Library/Application Support/Erimil/
├── cache/                      # Thumbnail cache (disk)
├── index.json                  # Path hash → content hash mapping
├── favorites_hybrid.json       # Favorites data
├── bookmarks.json              # Per-source bookmarks (栞)
└── last_folder_bookmark.data   # Security-scoped bookmark for folder restoration
```

## Development Philosophy & AI Usage

This project was developed with assistance from Claude AI (Anthropic). I want to be transparent about this approach and my reasoning.

### Standing on the Shoulders of Giants

I've been fortunate to work with open source technologies for over 30 years—from the early internet days to Linux, Virtualization, Cloud Computing, Docker, and beyond. The knowledge and code shared freely by countless developers made my career possible. Using AI trained on open source code without acknowledgment would feel like forgetting where I came from.

### Learning, Not Replacing

I used AI as a **learning accelerator** to explore SwiftUI, a framework I hadn't worked with before:

- I identified the problem (visual preview and selective extraction of images from ZIP archives)
- I defined all requirements and architectural decisions
- AI generated initial code structures and API examples
- I read and understood every line of generated code
- I debugged, refined, and made all final decisions

This mirrors how I learned in the 1990s: reading others' code, asking questions in forums, and building on shared knowledge. The tools changed, but the learning process remains the same.

### Why Share This?

**Transparency**: The community deserves to know how projects are built, especially when new tools are involved.

**For students**: If you're learning to code, know that using AI as a learning tool is okay—as long as you understand what you're building. Don't copy-paste. Read, understand, modify, and make it yours.

**For fellow developers**: I don't claim this is the "right" way. It's simply my way of balancing learning new technologies with years of experience in software development. Your approach may differ, and that's perfectly valid.

### A Note of Respect

To developers who built their skills entirely through manual effort: I deeply respect that path. This isn't about claiming my approach is superior—it's about being honest regarding the tools I used. The open source community thrives on honesty, sharing, and mutual respect. I hope this project reflects those values, even if the development process looks different from what came before.

### Contributing

Contributions are welcome! This project was created as a practical solution to a real problem, and maintained as a learning resource.

- **Simplicity First**: Resist feature creep
- **Privacy Matters**: No telemetry, no cloud
- **Readable Code**: Clear over clever
- **User Agency**: Give users control

## Acknowledgments

**Development Support**
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) for reliable ZIP archive handling
- The macOS developer community for comprehensive documentation and helpful discussions
- Apple's engineering teams for SwiftUI and the macOS sandbox security model

**Related Tools**
- [kurumil](https://github.com/zembutsu/kurumil) — Companion tool for image compression and AI upscaling

## License

MIT License — Masahito Zembutsu / [@zembutsu](https://github.com/zembutsu)
