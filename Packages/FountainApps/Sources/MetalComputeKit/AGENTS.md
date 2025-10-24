# MetalComputeKit — Agent Guide

Scope
- Lightweight compute scaffolding for macOS based on Metal and (optionally) MPSGraph. Designed to sit alongside MetalViewKit without entangling rendering code.

Targets
- `MetalComputeKit` (library)
  - `MetalComputeContext`: wraps `MTLDevice`/`MTLCommandQueue`, runtime MSL compilation, buffer helpers, and a dispatch helper.
  - Built‑in `vadd` kernel (vector add) compiled at runtime from inline MSL.
  - `MPSGraphFacade` (optional): basic matmul wrapper when `MetalPerformanceShadersGraph` is available.

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


Design choices
- Runtime MSL compilation via `device.makeLibrary(source:)` to avoid toolchain/env issues during development.
- Simple, explicit grid/threadgroup dispatch. Pick `threadsPerThreadgroup` based on the device’s `maxTotalThreadsPerThreadgroup`.
- No coupling to MetalViewKit; you may share `MTLDevice`/`MTLCommandQueue` if you need to pipe compute results into a view.

Extending
- Add kernels as inline MSL strings or load them from files; use `makeComputePipeline(functionName:source:)`.
- Prefer MPS (convolution, pooling, reduction) or MPSGraph (tensor graphs) over custom kernels where possible.

Threading & performance
- Prefer `.storageModeShared` for CPU‑visible staging; use `.storageModePrivate` for GPU‑only buffers and blit when needed.
- Batch work per command buffer; reuse pipelines.
- Avoid CPU–GPU round‑trips in tight loops.
