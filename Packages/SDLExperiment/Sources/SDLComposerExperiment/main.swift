import Foundation
import SDLKit
#if canImport(CSDL3)
import CSDL3
#endif

// SDL Composer Experiment
// Window with a neutral background and a bouncing rectangle to validate render loop.

@main
@MainActor
struct App {
    static func main() {
        do {
            // Open window
            let window = SDLWindow(config: .init(title: "SDL Composer Experiment", width: 1024, height: 640))
            try window.open()
            try window.show()

            // Create renderer bound to window
            let renderer = try SDLRenderer(width: 1024, height: 640, window: window)

            // Simple animation state
            var x = 100, y = 100, w = 120, h = 80
            var vx = 3, vy = 2

            // ARGB colors
            let bg: UInt32 = 0xFFF8F8F8
            let fg: UInt32 = 0xFF0A84FF

            let fps: Double = 60
            let frameTime: useconds_t = useconds_t(1_000_000.0 / fps)
            // Allow duration override via env; default to 12 seconds for visibility
            let duration = Double(ProcessInfo.processInfo.environment["SDL_EXPERIMENT_DURATION_SEC"] ?? "12") ?? 12.0
            let end = Date().addingTimeInterval(duration)
            while Date() < end {
                // Update
                x += vx; y += vy
                if x < 0 || x + w > 1024 { vx = -vx; x += vx }
                if y < 0 || y + h > 640  { vy = -vy; y += vy }

                // Draw
                try renderer.clear(color: bg)
                try renderer.drawRectangle(x: x, y: y, width: w, height: h, color: fg)
                renderer.present()

                // Cap frame rate
                usleep(frameTime)
            }
            renderer.shutdown()
            window.close()
        } catch {
            // Avoid LLDB attach prompt; print friendly guidance and fall back to a headless no-op loop
            #if canImport(CSDL3)
            let cmsg = String(cString: SDLKit_GetError())
            #else
            let cmsg = "(CSDL3 unavailable)"
            #endif
            fputs("SDL experiment failed: \(error)\n", stderr)
            if !cmsg.isEmpty { fputs("SDL lastError: \(cmsg)\n", stderr) }
            fputs("If SDL is unavailable, install required libs (e.g. brew install sdl3 sdl3_ttf sdl3_image) or run on a system with a display.\n", stderr)
            // Headless fallback: keep process alive briefly so launcher can verify run path
            let end = Date().addingTimeInterval(2)
            while Date() < end { usleep(50_000) }
        }
    }
}
