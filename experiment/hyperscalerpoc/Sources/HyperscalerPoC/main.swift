import Foundation
import CoreML
import Vision
import AppKit
import CoreImage

// MARK: - Memory Measurement

func peakMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return Double(info.resident_size) / 1_048_576.0
}

// MARK: - Image I/O Helpers

func loadCGImage(at path: String) -> CGImage? {
    guard let url = CFURLCreateWithFileSystemPath(nil, path as CFString, .cfurlposixPathStyle, false),
          let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }
    return image
}

func saveCGImage(_ image: CGImage, to path: String) -> Bool {
    guard let url = CFURLCreateWithFileSystemPath(nil, path as CFString, .cfurlposixPathStyle, false),
          let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

func cgImageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    return context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height))
}

// MARK: - Main

func run() throws {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        print("Usage: HyperscalerPoC <model.mlmodel> <input_image>")
        print("       HyperscalerPoC models/RealESRGAN.mlmodel input/test.png")
        exit(1)
    }

    let modelPath = args[1]
    let inputPath = args[2]
    let outputPath = args.count >= 4 ? args[3] : "output/result.png"

    let memBefore = peakMemoryMB()
    print("=== Hyperscaler PoC ===")
    print("Model:  \(modelPath)")
    print("Input:  \(inputPath)")
    print("Output: \(outputPath)")
    print()

    // --- Step 1: Compile Model ---
    print("[1/4] Compiling model...")
    let compileStart = CFAbsoluteTimeGetCurrent()
    let modelURL = URL(fileURLWithPath: modelPath)
    let compiledURL = try MLModel.compileModel(at: modelURL)
    let compileTime = (CFAbsoluteTimeGetCurrent() - compileStart) * 1000
    print("  Compiled in \(String(format: "%.0f", compileTime)) ms")
    print("  Compiled to: \(compiledURL.path)")

    // --- Step 2: Load Model ---
    print("[2/4] Loading model...")
    let loadStart = CFAbsoluteTimeGetCurrent()
    let config = MLModelConfiguration()
    config.computeUnits = .all  // ANE + GPU + CPU
    let mlModel = try MLModel(contentsOf: compiledURL, configuration: config)
    let vnModel = try VNCoreMLModel(for: mlModel)
    let loadTime = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
    print("  Loaded in \(String(format: "%.0f", loadTime)) ms")

    // Print model description
    let desc = mlModel.modelDescription
    print("  Inputs:")
    for (name, feat) in desc.inputDescriptionsByName {
        print("    \(name): \(feat.type.rawValue) — \(feat)")
    }
    print("  Outputs:")
    for (name, feat) in desc.outputDescriptionsByName {
        print("    \(name): \(feat.type.rawValue) — \(feat)")
    }

    // --- Step 3: Load Input Image ---
    print("[3/4] Loading input image...")
    guard let inputImage = loadCGImage(at: inputPath) else {
        print("  ERROR: Failed to load image at \(inputPath)")
        exit(1)
    }
    print("  Input size: \(inputImage.width) × \(inputImage.height)")

    // --- Step 4: Run Inference ---
    print("[4/4] Running inference...")
    let inferStart = CFAbsoluteTimeGetCurrent()

    let semaphore = DispatchSemaphore(value: 0)
    var outputImage: CGImage?
    var inferError: Error?

    let request = VNCoreMLRequest(model: vnModel) { request, error in
        if let error = error {
            inferError = error
            semaphore.signal()
            return
        }
        guard let results = request.results as? [VNPixelBufferObservation],
              let observation = results.first else {
            print("  ERROR: No VNPixelBufferObservation in results")
            print("  Results type: \(type(of: request.results))")
            if let results = request.results {
                for r in results {
                    print("    \(type(of: r))")
                }
            }
            semaphore.signal()
            return
        }
        let pixelBuffer = observation.pixelBuffer
        print("  Output buffer: \(CVPixelBufferGetWidth(pixelBuffer)) × \(CVPixelBufferGetHeight(pixelBuffer))")
        outputImage = cgImageFromPixelBuffer(pixelBuffer)
        semaphore.signal()
    }

    // Let Vision handle the resize to model's expected input
    request.imageCropAndScaleOption = .centerCrop
    //request.imageCropAndScaleOption = .scaleFill

    let handler = VNImageRequestHandler(cgImage: inputImage, options: [:])
    try handler.perform([request])
    semaphore.wait()

    let inferTime = (CFAbsoluteTimeGetCurrent() - inferStart) * 1000

    if let error = inferError {
        print("  ERROR: Inference failed — \(error)")
        exit(1)
    }

    print("  Inference time: \(String(format: "%.0f", inferTime)) ms")

    // --- Save Output ---
    if let output = outputImage {
        print("  Output size: \(output.width) × \(output.height)")
        if saveCGImage(output, to: outputPath) {
            print("  Saved to: \(outputPath)")
        } else {
            print("  ERROR: Failed to save output")
        }
    } else {
        print("  WARNING: No output image produced")
    }

    // --- Summary ---
    let memAfter = peakMemoryMB()
    print()
    print("=== Results ===")
    print("Model compile : \(String(format: "%.0f", compileTime)) ms")
    print("Model load    : \(String(format: "%.0f", loadTime)) ms")
    print("Inference     : \(String(format: "%.0f", inferTime)) ms")
    print("Memory before : \(String(format: "%.1f", memBefore)) MB")
    print("Memory after  : \(String(format: "%.1f", memAfter)) MB")
    print("Memory delta  : \(String(format: "%.1f", memAfter - memBefore)) MB")

    // Cleanup compiled model from temp
    try? FileManager.default.removeItem(at: compiledURL)
}

do {
    try run()
} catch {
    print("FATAL: \(error)")
    exit(1)
}
