import Foundation

@main
struct PatchBaySnapshots {
    static func main() {
        // Disabled lightweight stub to avoid linking patchbay-app during tests.
        // The actual snapshot writer can be restored under a compile flag if needed.
        fputs("patchbay-snapshots: disabled stub (no-op)\n", stderr)
    }
}
