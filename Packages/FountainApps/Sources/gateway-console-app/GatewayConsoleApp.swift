import SwiftUI
import FountainStoreClient

@main
struct GatewayConsoleApp: App {
    var body: some Scene {
        WindowGroup {
            GatewayConsoleRoot()
                .task {
                    // Seed & print Teatro prompt on boot for observability
                    await PromptSeeder.seedAndPrint(
                        appId: "gateway-console",
                        prompt: GatewayConsoleApp.buildTeatroPrompt(),
                        facts: [
                            "instruments": [[
                                "manufacturer": "Fountain",
                                "product": "GatewayConsole",
                                "instanceId": "gateway-console-1",
                                "displayName": "Gateway Console"
                            ]]
                        ]
                    )
                }
        }
        .windowStyle(.automatic)
    }
}

@MainActor
extension GatewayConsoleApp {
    static func buildTeatroPrompt() -> String {
        return """
        Scene: Gateway Console (Control Surface)
        Text:
        - Minimal macOS window hosting status/controls for Gateway-adjacent operations.
        - Intended for quick inspection and manual triggers; complements the full control plane.
        Where:
        - Code: Packages/FountainApps/Sources/gateway-console-app/*
        """
    }
}
