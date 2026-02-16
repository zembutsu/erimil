# Erimil Hyperscaler Preview — Design Document

## Overview

| Item | Value |
|------|-------|
| Feature | Hyperscaler Preview (超解像プレビュー) |
| Target Phase | Phase 4 |
| Dependencies | Core ML, Vision framework |
| Model | Real-ESRGAN (x4plus) — BSD-3-Clause |
| Approach | C案: Preview in Erimil, batch processing via kurumil |

## Problem Statement

Erimil's "browse → evaluate → mark → export" workflow lacks a critical evaluation capability: **predicting whether a low-resolution image will produce acceptable results after upscaling**. Users currently must export to kurumil, process, then evaluate — a slow feedback loop that defeats the purpose of rapid curation.

## Design Principle

> Hyperscaler Preview extends **evaluate**, not **edit**.
> The question it answers: "Is this image worth upscaling?" — not "Upscale this image."

This boundary keeps Erimil within its "選り見る" identity.

## Architecture

### Model Distribution Strategy: On-Demand Download

Erimil does **not** bundle the Core ML model. Instead:

```
First use of Hyperscaler Preview
  └── Check ~/Library/Application Support/Erimil/Models/
      ├── Model exists → Load and use
      └── Model missing → Show download dialog
          ├── User approves → Download from source URL → Save locally
          └── User declines → Feature unavailable (graceful degradation)
```

**Rationale:**
- App binary stays lightweight (~5MB vs ~67MB with model)
- No redistribution of model = no license obligation on Erimil
- User downloads model directly (same as downloading any tool)
- Model updates independent of app releases

**Model storage location:**
```
~/Library/Application Support/Erimil/Models/
  └── RealESRGAN_x4plus.mlmodelc/   (compiled Core ML model)
```

### Download Source Options

| Source | Pros | Cons |
|--------|------|------|
| HuggingFace (mszpro/CoreML_RealESRGAN) | Pre-converted, ready to use | 62MB zip, third-party host |
| Self-convert + GitHub Releases | Full control, known provenance | Requires conversion infrastructure |
| User provides own model | Maximum flexibility | Poor UX for non-technical users |

**Recommendation:** Start with HuggingFace source for PoC. For production, host on Erimil's GitHub Releases or provide a conversion script so users can convert from official Real-ESRGAN weights.

### Processing Pipeline

```
Input NSImage (from ImageSource)
  │
  ├── Resize to model input tile size (e.g., 256×256 or 512×512)
  │   └── For images larger than tile size: tile-based processing
  │
  ├── CGImage → CVPixelBuffer
  │
  ├── VNImageRequestHandler + VNCoreMLRequest
  │   └── Runs on ANE/GPU (automatic via Core ML)
  │
  ├── VNPixelBufferObservation → CGImage → NSImage
  │
  └── Display as preview overlay
```

### Tile-Based Processing

Real-ESRGAN Core ML models typically accept fixed-size input. For arbitrary image sizes:

```
Original image (e.g., 1024×768)
  │
  ├── Split into overlapping tiles (e.g., 256×256 with 16px overlap)
  ├── Process each tile through Core ML
  ├── Blend overlapping regions (linear interpolation)
  └── Reconstruct full upscaled image (4096×3072 for x4)
```

**Memory consideration:** Process one tile at a time to avoid OOM on large images. For preview purposes, processing only the visible region (or center crop) may be sufficient.

## UX Design

### Activation

| Context | Trigger | Behavior |
|---------|---------|----------|
| Slide Mode | `H` key (toggle) | Show/hide hyperscaler preview |
| Viewer Mode | `H` key (toggle) | Show/hide hyperscaler preview |
| Grid Mode | Not available | Grid is for overview, not detail evaluation |

### First-Time Experience

```
User presses H
  └── Model not found
      └── Sheet: "Hyperscaler Preview requires a super-resolution model (~60MB).
                  Download now?"
          [Download]  [Cancel]
          └── Progress indicator during download
              └── On complete: automatically show preview
```

### Preview Display

**Option A: Toggle overlay (recommended for initial implementation)**
- H key swaps displayed image between original and upscaled
- Status indicator: "Original" / "Hyperscaled (×4 Preview)"
- Fast toggle allows mental A/B comparison

**Option B: Side-by-side (future enhancement)**
- Split view: original left, upscaled right
- Synchronized zoom/pan

### Processing States

```
H pressed → "Processing..." spinner on image area
         → Upscaled image displayed (replaces spinner)
         → Navigate to next image → original shown
         → H is still active → auto-process next image
```

### Key Interaction Details

- H toggles **mode**, not individual images
- When mode is active, each newly displayed image triggers processing
- Processing is **async** — UI remains responsive
- Only **current visible image** is processed (no prefetching for hyperscaler)
- Cancel processing on navigation (don't waste cycles on images user skipped)

## Integration with kurumil

### Export Flow

After curation with hyperscaler preview:

```
User exports (existing export flow)
  └── Export dialog gains new option:
      ☐ "Open in kurumil for upscaling"  (checkbox, unchecked by default)
      
      If checked:
        └── After export completes:
            ├── Generate file list (one path per line)
            └── Launch: kurumil --input-list <listfile> --scale 4
```

### kurumil Integration Requirements (Phase 3 prerequisite)

- kurumil must accept `--input-list` parameter (file containing paths)
- kurumil must accept `--output-dir` parameter
- Erimil generates the list, kurumil does the work

### Quick Export (Preview Quality)

For users who want "good enough" upscaled images without kurumil:

```
Export menu:
  ├── Export PDF (existing)
  ├── Export PNG (existing)
  └── Export Upscaled PNG (new — Phase 4+)
      └── Uses Core ML model to upscale selected pages
      └── "_upscaled" suffix
      └── Warning: "Preview quality. For production use, export to kurumil."
```

**Note:** This is lower priority than the preview feature itself.

## Technical Considerations

### Model Compilation

Core ML models need compilation before first use. Two approaches:

1. **Distribute .mlmodel, compile on first load** — slower first launch (~10-30s), smaller download
2. **Distribute .mlmodelc (pre-compiled)** — instant load, larger download, platform-specific

Recommendation: Distribute `.mlmodel` and compile on first use. Cache compiled version.

```swift
// Pseudocode
let modelURL = modelsDirectory.appending("RealESRGAN_x4plus.mlmodel")
let compiledURL = try MLModel.compileModel(at: modelURL)
// Move compiled model to permanent location
let permanentURL = modelsDirectory.appending("RealESRGAN_x4plus.mlmodelc")
try FileManager.default.moveItem(at: compiledURL, to: permanentURL)
```

### Memory Management

| Image Size | x4 Output | Memory (approx) |
|------------|-----------|-----------------|
| 256×256 | 1024×1024 | ~12MB |
| 512×512 | 2048×2048 | ~48MB |
| 1024×1024 | 4096×4096 | ~192MB |

**Strategy:** Limit preview to reasonable sizes. For images >1024px, process a center crop or downsample first, then upscale. Full-image upscaling is kurumil's job.

### Thread Safety

- Model loading: once, on background thread, cache the MLModel instance
- Inference: background thread via `accessQueue` (consistent with existing PDFManager pattern)
- UI update: MainActor after inference completes
- Cancel token: support cancellation when user navigates away

### Error Handling

| Error | User Message | Action |
|-------|-------------|--------|
| Model not found | "Model not downloaded" | Offer download |
| Download failed | "Download failed. Check connection." | Retry option |
| Inference failed | "Could not process this image" | Fallback to original |
| Out of memory | "Image too large for preview" | Suggest smaller view |
| Model corrupted | "Model file is damaged" | Offer re-download |

## File Structure (Proposed)

```
Erimil/
  Models/
    HyperscalerManager.swift    — Model download, compilation, lifecycle
    HyperscalerProcessor.swift  — Core ML inference, tiling, image conversion
  Views/
    (existing views modified to support H key toggle)
```

## Implementation Plan

### Prerequisites
- [ ] #103 → #104 → #105 chain completed (Phase 2.3 / early Phase 3)
- [ ] kurumil CLI interface defined (--input-list, --output-dir)

### Phase 4 Issues (Proposed)

| # | Title | Scope | Est. |
|---|-------|-------|------|
| TBD | feat: HyperscalerManager — model download & lifecycle | Download, compile, cache, delete | M |
| TBD | feat: HyperscalerProcessor — Core ML inference | CVPixelBuffer conversion, inference, tiling | L |
| TBD | feat: H key hyperscaler toggle in Slide/Viewer | UI integration, async display | M |
| TBD | feat: kurumil export integration | File list generation, process launch | S |
| TBD | feat: Quick Export upscaled PNG (optional) | Core ML batch export | M |

### PoC Steps (Before Phase 4)

1. **Local PoC** (outside Erimil project):
   - Download RealESRGAN.mlmodel from HuggingFace
   - Create minimal Swift command-line tool or SwiftUI app
   - Verify: load model → feed image → get upscaled output
   - Measure: inference time, memory usage, output quality
   
2. **Evaluate results:**
   - Is preview quality acceptable for "worth upscaling?" decisions?
   - Is inference speed acceptable for interactive use (<3s per image)?
   - Does memory usage stay within reasonable bounds?

3. **Decision gate:**
   - If PoC results are positive → Create issues, schedule for Phase 4
   - If quality insufficient → Evaluate alternative models or defer

## Licensing Summary

| Component | License | Obligation |
|-----------|---------|------------|
| Erimil | MIT | — |
| Real-ESRGAN model | BSD-3-Clause | Copyright notice in acknowledgements if bundled |
| Core ML / Vision | Apple | macOS platform usage |
| Model distribution | On-demand download | No redistribution by Erimil = no license obligation on app |

**On-demand download approach eliminates Erimil's redistribution obligation for the model.** Users obtain the model directly. Erimil's acknowledgements should still note the model's origin and license for transparency.

## Open Questions

1. **Model selection:** x2 vs x4? x4 is more dramatic for preview but slower. Could offer both.
2. **Anime-optimized model:** Real-ESRGAN has `RealESRGAN_x4plus_anime_6B` (smaller, anime-focused). Relevant given Erimil's manga/doujinshi use case?
3. **Apple's built-in upscaling:** macOS 14+ may have new Vision APIs for super-resolution. Monitor WWDC for potential framework-level solution that would eliminate model management entirely.
4. **Model update mechanism:** How to notify users when better models are available?

## Decisions Log

| ID | Decision | Rationale |
|----|----------|-----------|
| D001 | Hybrid approach (C案): preview in Erimil, batch in kurumil | Respects "選り見る" boundary while adding evaluate capability |
| D002 | On-demand model download, not bundled | App size, licensing clarity, update independence |
| D003 | H key toggle in Slide/Viewer modes | Consistent with existing keyboard-driven UX (f, v, etc.) |
| D004 | Core ML + Vision framework | Native macOS, ANE acceleration, no external dependencies |
| D005 | Phase 4 scheduling | #103-#105 chain and Phase 3 priorities come first |
| D006 | PoC before commitment | Verify quality/performance before creating issues |

---

## Session Reference

- **Created in:** S041
- **Related sessions:** S039 (kurumil integration planning), S040 (#100 export)
- **Carry forward:** PoC execution → local Xcode project, outside Bebop session

> Based on **Bebop Style Development** v0.1.1
> Project: Erimil
