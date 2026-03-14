# Hyperscaler PoC — Investigation & Plan

## Date
2026-03-14 (S080)

## Objective
Verify that CoreML-based Real-ESRGAN super-resolution is viable for Erimil's interactive use case. Measure inference time, output quality, and memory usage before committing to full implementation.

---

## Model Options

### 1. mszpro/CoreML_RealESRGAN (HuggingFace)
- **File**: `RealESRGAN.mlmodel.zip` (62.1 MB)
- **Source**: https://huggingface.co/mszpro/CoreML_RealESRGAN
- **Format**: `.mlmodel` (needs compilation to `.mlmodelc` on first use)
- **README**: Minimal (81 bytes) — no input/output spec documented

### 2. john-rocky/CoreML-Models (Google Drive)
- **File**: `RealESRGAN4x` (66.9 MB)
- **Input**: Image (RGB 512×512) — **fixed size**
- **Output**: Image (RGB 2048×2048) — x4 upscale
- **Source**: https://github.com/john-rocky/CoreML-Models
- **Also available**: `RealESRGAN_Anime4x` (66.9 MB, same dimensions)

### 3. Self-convert from official Real-ESRGAN weights
- **Source**: https://github.com/xinntao/Real-ESRGAN
- **Models available**: `RealESRGAN_x4plus`, `RealESRGAN_x4plus_anime_6B`, `RealESRGAN_x2plus`
- **Conversion**: PyTorch → ONNX → CoreML (via coremltools)
- **Benefit**: Can set flexible input shapes during conversion
- **Risk**: Conversion quality may differ from Python inference (see john-rocky issue #29)

### Recommendation for PoC
Use **john-rocky/CoreML-Models** (Real ESRGAN4x). Well-documented spec (512×512 → 2048×2048), explicit license policy, popular repository. See D002 below for rationale.

---

## Fixed Input Size Implications

The pre-converted models accept **fixed 512×512** input. This means:

### For images ≤ 512×512 (primary Erimil use case: low-res images)
1. Pad/resize input to 512×512
2. Run inference → get 2048×2048 output
3. Crop output to match original aspect ratio × 4

### For images > 512×512
Two strategies:
- **Downsample first**: Resize to 512×512 → infer → get 2048×2048 (net ~4x from downsampled, not from original)
- **Tile-based**: Split into 512×512 tiles with overlap → infer each → blend and reconstruct

For the **PoC**, we only test the simple case: single 512×512 input.

---

## CoreML Inference API (macOS / Swift)

### Approach: Vision Framework

```swift
import CoreML
import Vision

// 1. Compile model (first use only)
let compiledURL = try MLModel.compileModel(at: mlmodelURL)

// 2. Load model
let mlModel = try MLModel(contentsOf: compiledURL)
let vnModel = try VNCoreMLModel(for: mlModel)

// 3. Create request
let request = VNCoreMLRequest(model: vnModel) { request, error in
    guard let results = request.results as? [VNPixelBufferObservation],
          let observation = results.first else { return }
    let outputPixelBuffer = observation.pixelBuffer
    // Convert CVPixelBuffer → CGImage → NSImage → save
}

// 4. Run inference
let handler = VNImageRequestHandler(cgImage: inputCGImage, options: [:])
try handler.perform([request])
```

### Key Points
- `VNPixelBufferObservation` for pixel-output models (super-resolution)
- Vision framework handles image → CVPixelBuffer conversion automatically
- `imageCropAndScaleOption` controls how input is fitted to model's expected size
- Inference runs on ANE/GPU automatically (Core ML runtime decides)

### macOS-specific Notes
- No UIImage on macOS — use NSImage / CGImage / CIImage
- CVPixelBuffer → CGImage: use `CIImage(cvPixelBuffer:)` + `CIContext.createCGImage()`
- Model compilation: `MLModel.compileModel(at:)` returns temp URL, must move to permanent location

---

## PoC Architecture

### Deliverable
Swift command-line tool. No GUI, no Xcode project. Swift Package Manager.

### Directory Structure
```
experiment/hyperscalerpoc/
├── INVESTIGATION.md          ← this file
├── RESULTS.md                ← filled after PoC execution
├── models/                   ← downloaded .mlmodel (gitignored)
│   └── RealESRGAN.mlmodel
├── input/                    ← test images
│   └── test_512x512.png
├── output/                   ← inference results
│   └── test_upscaled.png
└── Sources/
    └── HyperscalerPoC/
        └── main.swift        ← CLI entry point
```

### Package.swift
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HyperscalerPoC",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HyperscalerPoC",
            path: "Sources/HyperscalerPoC"
        )
    ]
)
```

### main.swift — Pseudocode
```
1. Parse arguments: input image path, model path
2. Load and compile model (measure compilation time)
3. Load input image as CGImage
4. Run inference via VNCoreMLRequest (measure inference time)
5. Extract VNPixelBufferObservation → CGImage
6. Save output as PNG
7. Print metrics:
   - Model compilation time (ms)
   - Inference time (ms)
   - Input dimensions
   - Output dimensions
   - Peak memory (via task_info)
```

---

## Design Decisions (from S080 discussion)

### D001: Plugin Model Architecture ("持ち込みモデル" 方式)

Erimil does **not** bundle, redistribute, or recommend any specific model. Instead:

- Erimil is a **CoreML model host** — it reads any compatible model placed in the designated directory
- `~/Library/Application Support/Erimil/Models/` serves as the model directory
- If no model is present, the feature is disabled (graceful degradation)
- Users obtain models at their own discretion and responsibility

**Erimil provides:**
- Documentation: expected I/O spec (input shape, pixel format, output shape)
- Compatibility note: "Verified with Real-ESRGAN x4plus (CoreML)" — information, not endorsement

**Erimil does NOT provide:**
- Model files
- Download links inside the app
- Any license obligation for the model

**Benefits:**
- Zero redistribution = zero license obligation on Erimil
- Users can swap models freely (anime-optimized, x2, x4, future models)
- No app update needed when better models emerge
- App binary stays lightweight

### D002: PoC Model Selection — john-rocky/CoreML-Models

For PoC, use the Real-ESRGAN model from [john-rocky/CoreML-Models](https://github.com/john-rocky/CoreML-Models):

- Well-known repository (1.7k stars), active community
- Explicit license policy: "The license for each model conforms to the license for the original project"
- Original model (xinntao/Real-ESRGAN): **BSD-3-Clause** — permissive, commercial use OK
- Input/output spec documented: **512×512 RGB → 2048×2048 RGB**
- Google Drive download link available

Avoided: mszpro/CoreML_RealESRGAN — no license field, no README, unclear provenance.

---

## PoC Success Criteria

| Metric | Target | Rationale |
|--------|--------|-----------|
| Inference time | < 3 seconds (512×512 input) | Interactive preview must feel responsive |
| Output quality | Visually useful for "worth upscaling?" judgment | Subjective — Zem evaluates |
| Peak memory delta | < 500 MB above baseline | Must coexist with Erimil's image cache |
| Model compilation | < 30 seconds (one-time) | Acceptable for first-use experience |

## Go / No-Go Decision
After running PoC:
- **Go**: Create issues for #40 Phase 1–4, schedule implementation
- **No-Go (performance)**: Evaluate alternative models or defer to kurumil-only approach
- **No-Go (quality)**: Try anime-specific model or self-conversion with different settings

---

## Next Steps (This Session)

1. [ ] Zem: Download Real-ESRGAN model from john-rocky/CoreML-Models (Google Drive) to `models/`
2. [ ] Create Package.swift and main.swift
3. [ ] Prepare test image (512×512 low-res sample)
4. [ ] Build and run PoC
5. [ ] Record results in RESULTS.md
6. [ ] Go / No-Go decision

---

## References

- [mszpro/CoreML_RealESRGAN](https://huggingface.co/mszpro/CoreML_RealESRGAN)
- [john-rocky/CoreML-Models](https://github.com/john-rocky/CoreML-Models) — Real ESRGAN4x: 512×512 → 2048×2048
- [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) — Official PyTorch implementation
- [Apple: Flexible Input Shapes](https://apple.github.io/coremltools/docs-guides/source/flexible-inputs.html)
- [Apple Developer Forums: ESRGAN CoreML conversion](https://developer.apple.com/forums/thread/734998)
- john-rocky issue #29: CoreML conversion may produce lower quality than Python inference
