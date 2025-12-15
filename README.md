# Erimil (選り見る)

A macOS application for visual preview and selective extraction of images from ZIP archives.

## Features

- **Visual Preview**: Browse images inside ZIP files without extracting
- **Selective Extraction**: Mark images to keep or exclude, then generate optimized ZIP
- **Folder Support**: Also works with regular image folders
- **Keyboard-Driven**: Navigate and select with keyboard shortcuts
- **Favorites System**: Mark important images with ★ for protection

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

| Key | Action |
|-----|--------|
| ← → ↑ ↓ / WASD | Navigate thumbnails |
| X | Toggle selection |
| V | Toggle favorite ★ |
| Space | Open preview |
| Escape / Enter | Close preview |

## Favorites System

Erimil uses a **Hybrid Favorites** design that tracks favorites in two ways:

### ★ Direct Favorite (Yellow Star)

Favorited in the current source (ZIP/folder). These are **protected** from deletion in Exclude mode.

When you press `V` on an image:
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

Erimil stores cache and favorites in:

```
~/Library/Application Support/Erimil/
├── cache/                    # Thumbnail cache
├── index.json               # Path → content hash mapping
└── favorites_hybrid.json    # Favorites data
```

## Related Projects

- [kurumil](https://github.com/zembutsu/kurumil) - Image compression and AI upscaling CLI tool

## License

MIT License

## Author

Masahito Zembutsu / @zembutsu
