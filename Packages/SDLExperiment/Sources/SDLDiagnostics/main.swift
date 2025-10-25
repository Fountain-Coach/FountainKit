import Foundation
import SDLKit
#if canImport(Darwin)
import Darwin
#endif
#if canImport(CSDL3)
import CSDL3
#endif

@main
struct SDLDiagnosticsApp {
    static func main() {
        print("=== SDL Diagnostics ===")

        // Print basic env info helpful for SDL troubleshooting
        let env = ProcessInfo.processInfo.environment
        #if os(macOS)
        let hb = env["HOMEBREW_PREFIX"] ?? "/opt/homebrew"
        let dyld = env["DYLD_FALLBACK_LIBRARY_PATH"] ?? "(unset)"
        print("Platform: macOS ; Homebrew: \(hb)")
        print("DYLD_FALLBACK_LIBRARY_PATH=\(dyld)")
        print("SDL_VIDEODRIVER=\(env["SDL_VIDEODRIVER"] ?? "(unset)") SDL_AUDIODRIVER=\(env["SDL_AUDIODRIVER"] ?? "(unset)")")
        // Hint defaults if not set (this process only)
        if env["SDL_VIDEODRIVER"] == nil { setenv("SDL_VIDEODRIVER", "cocoa", 1) }
        if env["SDL_AUDIODRIVER"] == nil { setenv("SDL_AUDIODRIVER", "dummy", 1) }
        // Check for Homebrew SDL dylib
        let sdlLibPath = hb + "/lib/libSDL3.dylib"
        let libExists = FileManager.default.fileExists(atPath: sdlLibPath)
        print("SDL3 dylib present at \(sdlLibPath): \(libExists ? "yes" : "no")")
        // Try dlopen to surface any loader error text
        if !libExists {
            print("Note: install SDL3 via: Scripts/apps/install-sdl-deps.sh")
        } else {
            #if canImport(Darwin)
            if let handle = dlopen(sdlLibPath, RTLD_LAZY) {
                dlclose(handle)
            } else if let err = dlerror() {
                print("dlopen error: \(String(cString: err))")
            }
            #endif
        }
        #endif

        #if canImport(CSDL3)
        let rc = SDLKit_Init(0)
        if rc < 0 {
            let msg = String(cString: SDLKit_GetError())
            print("SDLKit_Init failed: \(msg)")
            if msg.isEmpty {
                print("Tip: run via 'bash Scripts/apps/launch-sdl-experiment.sh' to set required env, or install deps with 'bash Scripts/apps/install-sdl-deps.sh'.")
            }
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
            let msg = String(cString: SDLKit_GetError())
            print("CreateWindow failed: \(msg)")
        }
        #else
        print("CSDL3 unavailable; cannot run diagnostics.")
        #endif
    }
}
