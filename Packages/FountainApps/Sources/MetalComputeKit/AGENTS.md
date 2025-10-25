# MetalComputeKit — Agent Guide

Scope
- Lightweight compute scaffolding for macOS based on Metal and (optionally) MPSGraph. Designed to sit alongside MetalViewKit without entangling rendering code.

Targets
- `MetalComputeKit` (library)
  - `MetalComputeContext`: wraps `MTLDevice`/`MTLCommandQueue`, runtime MSL compilation, buffer helpers, and a dispatch helper.
  - Built‑in compute: vadd/vmul/saxpy, activations (relu/clamp/sigmoid), reductions (sum/min/max), softmax, FIR, window, linear resample.
  - `MPSDsp`: MPS 2D convolution wrapper with CPU fallback; preferred FFT path (vDSP today, GPU upgrade later).
  - `MPSGraphFacade` (optional): basic matmul when `MetalPerformanceShadersGraph` is available.

Usage (example)
```swift
import MetalComputeKit

print(MetalComputeInspector.report()) // quick capability report (device name, thread width hint, MPSGraph availability)

guard let ctx = MetalComputeContext() else { fatalError("No Metal") }
let a = Array(repeating: 1.0 as Float, count: 1024)
let b = Array(repeating: 2.0 as Float, count: 1024)
let c = try ctx.vadd(a: a, b: b) // c[i] = 3.0

#if canImport(MetalPerformanceShadersGraph)
if let g = MPSGraphFacade() {
    let m = 32, k = 64, n = 16
    let a = (0..<(m*k)).map { _ in Float.random(in: -1...1) }
    let b = (0..<(k*n)).map { _ in Float.random(in: -1...1) }
    let c = g.matmul(a: a, m: m, k: k, b: b, n: n)
    print(c.count) // m*n
}
#endif
```

Your machine — “now it’s about you”
- Run the demo to see what this Mac can do:
  - `swift run --package-path Packages/FountainApps metalcompute-demo`
  - You’ll get a capability report like:
    - `Metal Device: Apple M2` (or discrete GPU name)
    - `Thread Execution Width (hint): 32/64` (guides threadgroup sizing)
    - `MPSGraph Available: yes/no` (tensor graphs available on this SDK)
  - Then it benchmarks a large vector add (vadd). If MPSGraph is available, it also attempts a matmul (stubbed when unavailable).

Extensible (future‑proofing)
- FFT: `fftMagnitudesPreferred(_:)` uses Accelerate vDSP for reliability today. A GPU path (MPSGraph or MPSFFT) can be enabled behind availability without changing call sites.
- DSP kernels live in `MPSDsp.swift` (2D convolution, windowing, resample). Additions here don’t affect core compute.
- Validation: use `metalcompute-tests` to keep additions green across SDK differences; be tolerant where MPS implementations vary (compare MAE or constrain to inner regions).

If the report says “MPSGraph Available: no”
- Why you’re seeing this
  - The running Swift toolchain is using an SDK or Xcode that doesn’t expose `MetalPerformanceShadersGraph`.
  - Common causes: Command‑line build pointed at an old Xcode, or macOS SDK too old for your repo’s platform (we target macOS 14).
- Quick fixes (pick the one that applies)
  - Ensure Xcode 15+ (or newer) is selected for CLI builds:
    - `sudo xcode-select -s /Applications/Xcode.app`
    - Verify: `xcode-select -p` and `swift --version`
  - Sanity‑check the SDK path and the module:
    - `xcrun --sdk macosx --show-sdk-path`
    - `xcrun swiftc -sdk $(xcrun --show-sdk-path --sdk macosx) -e 'import MetalPerformanceShadersGraph; print("MPSGraph OK")'`
  - Confirm OS/SDK target: this workspace targets `macOS 14`. If you’re on an older macOS, keep using MetalComputeKit kernels and Core ML; enable MPSGraph on a newer host.
- You’re not blocked
  - All compute examples (vadd, custom kernels) run with plain Metal.
  - For ML, prefer Core ML for packaged models or keep using custom Metal/MPS kernels; we can enable MPSGraph later without changing call sites.

Xmas upgrades (make this machine “happy”)
- Upgrade to the latest stable Xcode and macOS you’re comfortable with.
- Re‑select Xcode for CLI (`xcode-select`) so `swift build` uses that SDK.
- Optional: ask us to enable the full MPSGraphFacade implementation — it’s gated behind availability and can be swapped in once the module is present.


Design choices
- Runtime MSL compilation via `device.makeLibrary(source:)` to avoid toolchain/env issues during development.
- Simple, explicit grid/threadgroup dispatch. Pick `threadsPerThreadgroup` based on the device’s `maxTotalThreadsPerThreadgroup`.
- No coupling to MetalViewKit; you may share `MTLDevice`/`MTLCommandQueue` if you need to pipe compute results into a view.

Extending
- Add kernels as inline MSL strings or load them from files; use `makeComputePipeline(functionName:source:)`.
- Prefer MPS (convolution, pooling, reduction) or MPSGraph (tensor graphs) over custom kernels where possible.

Core ML interop
- Moved to `CoreMLKit` to keep responsibilities clean.
- Use `CoreMLKit.CoreMLInterop.loadModel(at:)` and `predict(model:inputs:)`.
- Demo runner: `swift run --package-path Packages/FountainApps coreml-demo` with `COREML_MODEL=/path/to/Model.mlmodel[c]`.

Threading & performance
- Prefer `.storageModeShared` for CPU‑visible staging; use `.storageModePrivate` for GPU‑only buffers and blit when needed.
- Batch work per command buffer; reuse pipelines.
- Avoid CPU–GPU round‑trips in tight loops.
