import Foundation
import SDLKit

// SDL Composer Experiment
// Window with a neutral background and a bouncing rectangle to validate event loop / timing.

@main
struct App {
    static func main() throws {
        try SDL.initialize()
        defer { SDL.quit() }

        let window = try SDLWindow(title: "SDL Composer Experiment",
                                   width: 1024, height: 640,
                                   options: [.resizable, .allowHighDPI])
        let renderer = try SDLRenderer(window: window, options: [.accelerated, .presentVSync])

        var running = true
        var rect = SDLRect(x: 100, y: 100, w: 120, h: 80)
        var vel = (x: 3, y: 2)

        let bg = SDLColor(r: 248, g: 248, b: 248, a: 255)
        let fg = SDLColor(r: 10, g: 132, b: 255, a: 255)

        let fps: Double = 60
        let frameTime: UInt32 = UInt32(1000.0 / fps)

        while running {
            // Handle events
            while let event = SDLEvent.poll() {
                switch event.type {
                case .quit:
                    running = false
                case .keyDown(let key):
                    if key.keysym.sym == .escape { running = false }
                default:
                    break
                }
            }

            // Update animation
            rect.x += vel.x
            rect.y += vel.y
            let size = try renderer.outputSize()
            if rect.x < 0 || rect.x + rect.w > size.w { vel.x = -vel.x; rect.x += vel.x }
            if rect.y < 0 || rect.y + rect.h > size.h { vel.y = -vel.y; rect.y += vel.y }

            // Draw
            try renderer.setDrawColor(bg)
            try renderer.clear()
            try renderer.setDrawColor(fg)
            try renderer.fillRect(rect)

            // Present
            try renderer.present()

            // Cap framerate
            SDL.delay(frameTime)
        }
    }
}

