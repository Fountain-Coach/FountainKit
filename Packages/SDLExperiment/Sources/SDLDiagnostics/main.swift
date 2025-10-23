import Foundation
import SDLKit
#if canImport(CSDL3)
import CSDL3
#endif

@main
struct SDLDiagnosticsApp {
    static func main() {
        print("=== SDL Diagnostics ===")
        #if canImport(CSDL3)
        let rc = SDLKit_Init(0)
        if rc != 0 {
            print("SDLKit_Init failed: \(String(cString: SDLKit_GetError()))")
            return
        }
        defer { SDLKit_Quit() }
        let displays = SDLKit_GetNumVideoDisplays()
        print("Video displays: \(displays)")
        for i in 0..<displays {
            var xi:Int32 = 0, yi:Int32 = 0, wi:Int32 = 0, hi:Int32 = 0
            let name = SDLKit_GetDisplayName(i).flatMap { String(cString: $0) } ?? "(unknown)"
            _ = SDLKit_GetDisplayBounds(i, &xi, &yi, &wi, &hi)
            print("  [\(i)] \(name) — \(Int(wi))x\(Int(hi)) @ (\(Int(xi)),\(Int(yi)))")
        }
        print("Attempting to create 1x1 window…")
        if let win = SDLKit_CreateWindow("SDLDiag", 1, 1, 0) {
            print("Window created OK; destroying…")
            SDLKit_DestroyWindow(win)
        } else {
            print("CreateWindow failed: \(String(cString: SDLKit_GetError()))")
        }
        #else
        print("CSDL3 unavailable; cannot run diagnostics.")
        #endif
    }
}

