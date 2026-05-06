# Erimil Design Philosophy (DRAFT)

> This document captures the product principles that distinguish Erimil from a generic image/document viewer.
> For development methodology (Bebop Style Development), see [`PHILOSOPHY-DRAFT.md`](./PHILOSOPHY-DRAFT.md).
> Started: 2026-04-25

---

## Why This Document Exists

A product accumulates features. Without a philosophy, those features drift toward whatever feels easy in the moment — and the product loses coherence.

This document records *why* Erimil makes certain choices, so future feature decisions can be checked against the principles rather than re-derived from scratch.

It is paired with `PHILOSOPHY-DRAFT.md`, which captures *how* we develop (BSD methodology). That document is portable — it can be applied to any project. This document is **specific to Erimil**: what we are building, and the convictions that shape the product itself.

---

## Core Principles

### 1. Source is Sacred

Erimil never modifies the source.

PDF files, ZIP archives, folder contents — when Erimil opens them, they remain bit-for-bit identical to before. Reordering, hiding, marking, exporting, annotating — none of these touch the source.

This is not a technical limitation. It is a deliberate constraint that defines what Erimil is.

**Why this matters:**

- Sources are often shared, backed up, archived, or original-of-record material. Modification breaks all of those.
- Sources may live on read-only media (DVD, network shares without write permission, CD archives). A tool that *requires* write access to the source cannot work with them.
- Sources may have integrity hashes used elsewhere (provenance, deduplication, content addressing). Modification breaks those checks silently.
- Trusting the user's data means leaving it untouched.

**Implication**: every feature that modifies how content is presented must do so through a layer *above* the source, never by rewriting it.

### 2. The Editorial Model

Where most viewers offer two paths — *show what's there* (read-only) or *modify the source* (destructive edit) — Erimil offers a third: **edit the experience without editing the artifact**.

```
Read-only viewer:    Source → Display
Destructive editor:  Source ← User edits → Display
Erimil's model:      Source → [View Layer] → Display
                              ↑ User edits here
```

The View Layer is where user choices live: ordering, hiding, marking, annotations. The source remains pristine; the layer carries everything the user did to make sense of it.

This is closer to what a curator does in a museum than what a word processor does to a document. The painting is not repainted to fit the exhibition — it is hung, sequenced, contextualized. The artifact endures; the curation is reversible, evolvable, and can be multiple.

**Current expression**: View Layer with manual order and hide.
**Possible future expressions**: per-entry annotations, tags, groupings, multiple named arrangements per source.

### 3. Metadata Follows Content, Not Path

When a user moves a folder, renames a ZIP, or copies a PDF to another disk, their curation should travel with the content — not break.

Erimil keys metadata by content (filename + hash), not by filesystem path. The View Layer for a ZIP is found by hashing the ZIP, regardless of where it lives now.

**Implication**: Erimil's sidecar metadata is centralized in Erimil's own storage, not dropped next to source files. This works with read-only media, survives source relocation, and avoids littering user directories with `.erimil-metadata/` clutter.

The trade-off is that backup or sync of curation requires backing up Erimil's metadata directory separately. We accept this cost.

### 4. The User Curates, the App Layers

Erimil is not opinionated about what the *correct* arrangement of a source is.

A photographer may sequence by aesthetic preference. A reviewer may sequence chronologically. A teacher may rearrange chapters by lesson order. None of these is the "right" view of the underlying material.

Erimil's job is to make the user's curation **easy to express, persistent, and reversible** — not to suggest what it should be.

**Implication**: View Layer is per-source, not global. There is no app-level "preferred arrangement". Each source carries its own.

---

## Anti-Patterns

### Destructive Editing

Modifying the source to organize it. Renaming files to control sort order. Deleting "rejected" images. Splitting a PDF to drop pages. These leave the source permanently changed and are incompatible with Principle 1.

**Erimil alternative**: express the change in the View Layer. The source stays whole.

### Filename Hacking

Using filenames as a sort-order encoding (`00_cover.png`, `01_intro.png`, `99_appendix.png`). This works, but:

- Mixes presentation concerns into the data
- Fails when filenames carry meaning (dates, IDs, content names)
- Forces re-renaming for every reorder
- Leaks app behavior into every other tool that lists the directory

**Erimil alternative**: manual order in the View Layer. Filenames stay meaningful; ordering lives where ordering belongs.

### Sidecar Litter

Dropping `.thumbs/`, `_metadata.json`, or `.DS_Store`-style files next to the user's source content. Pollutes user directories, breaks integrity checks, fails on read-only media.

**Erimil alternative**: all Erimil-managed metadata lives in Erimil's own storage, keyed by content hash.

### Global Curation

Assuming one user-level arrangement applies across all sources. A user's preference for "show newest first" doesn't apply when reviewing a fan-made comic ZIP intended to be read in publication order. Per-source curation is the correct unit.

**Erimil alternative**: View Layer per source. Application-level defaults are minimal and treated as fallbacks, not commitments.

---

## Open Questions

These are deliberately unresolved. They are recorded here to keep them visible, not to decide them yet.

### Naming

"View Layer" is the architectural term. For end-users, the concept may need a different name. Candidates:

- **Arrangement** — neutral, describes both ordering and hiding
- **Curation** — captures the editorial framing, but slightly academic
- **Shelf** / **棚** — Japanese metaphor for personal, situated organization
- **Layout** — overloaded, may confuse with UI layout
- **Setup** — too generic

Open question: should the user-facing name match the architectural name, or should they intentionally diverge?

### Positioning

Should "Source is Sacred" and "the Editorial Model" be made explicit in README, on the product website, in the App Store description? They are differentiating claims — most viewers cannot say them honestly. But over-claiming philosophy in product copy can sound pretentious.

Open question: at what point does the philosophy belong in marketing copy, versus staying as internal design discipline?

### Scope of the Editorial Model

The model currently applies to image-based sources (PDF, ZIP, folder of images). Should it extend to:

- Audio collections (playlists as View Layers)?
- Video (chapter overrides, scene hides)?
- Text documents (annotated views, paragraph-level hide)?

Open question: is Erimil image-first by accident of origin, or image-first by design?

---
## Source Layer / View Layer Separation

Erimil treats every image collection as two stacked layers. Most design
decisions resolve cleanly once you ask which layer a given concern belongs to.

### Definitions

**Source layer (ソース層)** — what the content *is*.
A FolderManager / ArchiveManager / PDFManager owns this. Everything in this
layer is determined when the source is opened, or is intrinsic to the content
itself. The user does not change Source-layer properties through view
controls.

**View layer (表示層)** — how the user is *looking at* the content right now.
ThumbnailGridView owns this (currently with CacheManager-backed persistence).
View-layer state can change at any time, can differ between sessions, and is
orthogonal to which source is open.

### Classification

| Concern | Layer | Note |
|---|---|---|
| `entryPath` order (raw) | Source | Filesystem-derived, deterministic |
| RTL / LTR reading direction | Source | Content-intrinsic |
| `supportsDateSort` | Source | Capability flag |
| Prefetch order (`prefetchAllThumbnails`) | Source | Natural ingestion order, content-internal |
| Cover image position | Source | Content-intrinsic |
| TileSheet packing order | Source (internal) | Build-time determinism, path-based |
| Sort mode / ascending | View | User preference, runtime-mutable |
| Manual order (#268) | View | User-defined override |
| Hidden entries (#268) | View | Display filter, entry preserved in source |
| Bookmarks (栞) | View-adjacent | Per-source persistence, but user-driven |

### The orthogonality rule

> View-layer changes never trigger Source-layer recomputation.

Concretely: changing the sort mode in ThumbnailGridView reorders the displayed
`entries` array. It does **not** re-call `listImageEntries()`, does **not**
re-trigger `prefetchAllThumbnails`, does **not** invalidate any TileSheet, and
does **not** affect the path-based lookup chain
(`ArchiveManager.thumbnail(for:)` → `CacheManager.getThumbnail`).

This is enforced by the path-based lookup contract: every cached thumbnail is
keyed by `entry.path`, never by display index. Source-layer storage may be
internally ordered (e.g. TileSheetCache sorts by `entryPath` for deterministic
packing), but that order is an internal implementation detail of the build
path, not a property exposed to or depended on by the View layer.

### Why this matters

The classification above resolves several otherwise-ambiguous design
questions:

- **"Should sort change prefetch order?"** No. Prefetch order is the source's
  natural ingestion order; the user's view selection does not propagate back.
- **"Should RTL flip when sort is descending?"** No. RTL is intrinsic; sort
  is a view choice. They occupy different axes.
- **"Where does sort state live?"** View layer. Per-source persistence
  (CacheManager today, possibly View Layer JSON in #268) is a serialization
  detail; the conceptual ownership stays in View.
- **"Can TileSheetCache break under non-name sort?"** No. Its order
  invariant is internal to the build path. The View layer never observes it.

---

## See Also

- [`PHILOSOPHY-DRAFT.md`](./PHILOSOPHY-DRAFT.md) — Bebop Style Development methodology (how we develop)
- `ARCHITECTURE.md` — Implementation architecture (how it is built)
- View Layer feature — first concrete realization of the Editorial Model:
  - #268 — View Layer: manual order and hide
  - #267 — Sort implementation (prerequisite)
  - #269 — Export favorites-only (consequence)

---

> "A library does not become useful by rewriting the books on the shelves. It becomes useful by how the shelves are arranged — and by who is allowed to rearrange them."

---

*This is a living document. It will evolve with practice and decisions.*
