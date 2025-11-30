import Foundation

/// Stubbed PBVRT embed check; CI path is disabled in this workspace build to keep tests light.
/// The original Vision-backed embed validation lives in pbvrt-server; enable it when running the CI pipeline.
@main
struct PBVRTEmbedCI {
    static func main() {
        print("pbvrt-embed-ci stub: Vision check disabled in this workspace build.")
    }
}
