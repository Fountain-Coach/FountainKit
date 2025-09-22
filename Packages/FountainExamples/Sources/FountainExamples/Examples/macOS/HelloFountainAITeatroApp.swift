#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import Foundation
import Teatro
import TeatroRenderAPI

struct HealthResponse: Decodable {
    let status: String
    let version: String
}

@available(macOS 13.0, *)
struct ContentView: View {
    @State private var svg: Data? = nil
    @State private var loading = true

    var body: some View {
        Group {
            if let svg {
                TeatroPlayerView(svg: svg)
            } else if loading {
                ProgressView()
            } else {
                Text("Failed to load")
            }
        }
        .task {
            await load()
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func load() async {
        do {
            let url = URL(string: "http://localhost:8007/v1/health")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            let message = "Hello FountainAI World — \(health.status)"
            let rendered = try TeatroRenderer.renderScript(SimpleScriptInput(fountainText: message))
            if let svgData = rendered.svg {
                self.svg = svgData
            }
        } catch {
            print("Health check failed: \(error)")
        }
        loading = false
    }
}

@main
@available(macOS 13.0, *)
struct HelloFountainAITeatroApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
#else
@main
struct HelloFountainAITeatroApp {
    static func main() {
        print("HelloFountainAITeatro requires macOS with SwiftUI")
    }
}
#endif
