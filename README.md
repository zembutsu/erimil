# Erimil (選り見る)

A macOS application for visual preview and selective extraction of images from ZIP archives.

## Features

- **Visual Preview**: Browse images inside ZIP files without extracting
- **Selective Extraction**: Mark images to keep or exclude, then generate optimized ZIP
- **Folder Support**: Also works with regular image folders
- **Keyboard-Driven**: Navigate and select with keyboard shortcuts
- **Favorites System**: Mark important images with ★ for protection
- **Slide Mode**: Fullscreen viewing with Favorites Mode for quick navigation

## Requirements

- macOS 14.0 (Sonoma) or later

## Installation

Download the latest release from [GitHub Releases](https://github.com/zembutsu/erimil/releases).

## Usage

### Basic Workflow

1. Drag a folder containing ZIPs to the sidebar, or use File → Open
2. Click a ZIP file to view thumbnails
3. Select images to exclude (or keep, depending on mode)
4. Click "確定 → _opt.zip" to generate optimized archive

### Selection Modes

| Mode | Click/X Key | Result |
|------|-------------|--------|
| **Exclude Mode** | Mark for removal | Selected items excluded from output |
| **Keep Mode** | Mark for keeping | Only selected items included in output |

Toggle mode via the toolbar button or Settings.

### Keyboard Shortcuts

#### Filer View (Thumbnail Grid)

| Key | Action |
|-----|--------|
| ← → ↑ ↓ / WASD | Navigate thumbnails |
| X | Toggle selection |
| F | Toggle favorite ★ |
| Space | Open Quick Look preview |
| Enter | Open Slide Mode (fullscreen) |
| Ctrl+F | Open Slide Mode (alternative) |

#### Quick Look Preview

| Key | Action |
|-----|--------|
| ← → / A D | Navigate images |
| Enter | Switch to Slide Mode |
| Space / Esc | Close preview |

#### Slide Mode (Fullscreen)

| Key | Normal Mode | Favorites Mode |
|-----|-------------|----------------|
| ← → / A D | Previous/Next image | Previous/Next ★ |
| Tab | Next ★ + **Enter Favorites Mode** | Next ★ |
| F | Toggle favorite ★ | Toggle favorite ★ |
| X | Toggle selection | Toggle selection |
| Q | Exit fullscreen | Exit Favorites Mode |
| Esc | Exit fullscreen | Exit fullscreen |
| Ctrl+← / Ctrl+A | Previous source (ZIP/folder) | Previous source |
| Ctrl+→ / Ctrl+D | Next source (ZIP/folder) | Next source |
| Space | Toggle controls | Toggle controls |

### Sidebar Navigation

| Action | Result |
|--------|--------|
| Single-click | Select source, show thumbnails |
| Double-click | Select source + open Slide Mode |

### Slide Mode Features

Slide Mode provides fullscreen image viewing with powerful navigation:

**Position Indicators**
- Image position bar: Shows current position with ★ (favorites) and × (selections) markers
- Source position bar: Shows position among sibling ZIPs/folders in the same directory

**Favorites Mode**
- Press `Tab` to enter Favorites Mode and jump to the next favorite
- `←/→` or `A/D` navigate between favorites only (skipping non-favorites)
- Yellow header indicates Favorites Mode is active
- Press `Q` to exit Favorites Mode (return to normal navigation)

**Source Navigation**
- `Ctrl+←/→` or `Ctrl+A/D` to switch between ZIPs/folders
- Maintains fullscreen state during navigation
- Loops from last to first (and vice versa)

## Favorites System

Erimil uses a **Hybrid Favorites** design that tracks favorites in two ways:

### ★ Direct Favorite (Yellow Star)

Favorited in the current source (ZIP/folder). These are **protected** from deletion in Exclude mode.

When you press `F` on an image:
- The image is marked as ★ (direct favorite)
- It cannot be selected for exclusion
- Shows "PROTECTED" label in Exclude mode

### ☆ Inherited Favorite (White Star)

The same image content was favorited in another source. This is a **reference** only.

| Scenario | Display | Protected? |
|----------|---------|------------|
| Favorited in this ZIP | ★ (yellow) | Yes |
| Same image favorited elsewhere | ☆ (white) | No |
| Not favorited | (none) | No |

### Distillation Workflow

This design enables a powerful "distillation" workflow:

```
photos.zip (100 images)
    ↓ Mark favorites with ★
    ↓ Export
photos_opt.zip (50 images)
    ↓ Open - ☆ shows previous favorites
    ↓ Mark new ★ for best selection
    ↓ Export  
photos_opt_opt.zip (20 images) = Best Selection
```

Each pass refines your selection, with ☆ showing what you liked before.

## Data Storage

Erimil stores cache and favorites in the sandboxed container:

```
~/Library/Containers/jp.pocketstudio.zem.Erimil/Data/Library/Application Support/Erimil/
├── cache/                      # Thumbnail cache (disk)
├── index.json                  # Path hash → content hash mapping
├── favorites_hybrid.json       # Favorites data (hybrid system)
└── last_folder_bookmark.data   # Security-scoped bookmark for folder restoration
```

## Contributing

Contributions are welcome! This project was created as a practical solution to a real problem, and maintained as a learning resource.

### Development Philosophy
- **Simplicity First**: Resist feature creep
- **Privacy Matters**: No telemetry, no cloud
- **Readable Code**: Clear over clever
- **User Agency**: Give users control

## Development Process & AI Usage

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

I'm sharing this development approach for a few reasons:

**Transparency**: The community deserves to know how projects are built, especially when new tools are involved.

**For students**: If you're learning to code, know that using AI as a learning tool is okay—as long as you understand what you're building. Don't copy-paste. Read, understand, modify, and make it yours.

**For fellow developers**: I don't claim this is the "right" way. It's simply my way of balancing learning new technologies with years of experience in software development. Your approach may differ, and that's perfectly valid.

### A Note of Respect

To developers who built their skills entirely through manual effort: I deeply respect that path. This isn't about claiming my approach is superior—it's about being honest regarding the tools I used. The open source community thrives on honesty, sharing, and mutual respect. I hope this project reflects those values, even if the development process looks different from what came before.

---

## Acknowledgments

This project stands on the shoulders of giants and wouldn't exist without:

**Development Support**
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) for reliable ZIP archive handling
- The macOS developer community for comprehensive documentation and helpful discussions
- Apple's engineering teams for SwiftUI and the macOS sandbox security model

**Related Tools**
- [kurumil](https://github.com/zembutsu/kurumil) - Companion tool for image compression and AI upscaling

## License

MIT License

## Author

Masahito Zembutsu / @zembutsu
