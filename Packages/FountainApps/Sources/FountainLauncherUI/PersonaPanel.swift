import SwiftUI
import AppKit

struct PersonaPanel: View {
    @ObservedObject var vm: LauncherViewModel
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 120)
            HStack(spacing: 8) {
                Button("Load") { text = vm.readPersona() }
                Button("Save") { vm.writePersona(text) }
                Spacer()
            }.font(.caption)
        }
        .onAppear { text = vm.readPersona() }
    }
}

extension LauncherViewModel {
    private var personaURL: URL? {
        guard let repoPath else { return nil }
        return URL(fileURLWithPath: repoPath).appendingPathComponent("Configuration/persona.yaml")
    }
    func readPersona() -> String {
        guard let url = personaURL else { return "# persona.yaml (create)\nrole: assistant\nstyle: concise\n" }
        return (try? String(contentsOf: url)) ?? ""
    }
    func writePersona(_ s: String) {
        guard let url = personaURL else { return }
        do { try s.write(to: url, atomically: true, encoding: .utf8); logText += "\n[persona] Saved persona.yaml\n" } catch {
            logText += "\n[persona] Save failed: \(error)\n"
        }
    }
}

