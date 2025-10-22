import SwiftUI
import AppKit

struct OpenAPISidePanel: View {
    @ObservedObject var vm: LauncherViewModel
    @State private var specs: [SpecItem] = []
    @State private var selected: SpecItem? = nil
    @State private var filter: String = ""

    var body: some View {
        GroupBox(label: Text("OpenAPI Specs")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack { TextField("Filter", text: $filter); Spacer(); Button("Refresh") { specs = vm.findSpecs() } }
                HStack(alignment: .top, spacing: 8) {
                    List(selection: Binding(get: { selected }, set: { selected = $0 })) {
                        ForEach(specs.filter { filter.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(filter) }) { item in
                            HStack { Image(systemName: "doc.text"); Text(item.name) }.tag(item as SpecItem?)
                        }
                    }
                    .frame(minWidth: 160, maxHeight: 160)
                    TextEditor(text: Binding(get: { selected.flatMap { vm.readSpec(at: $0.url) } ?? "" }, set: { _ in }))
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 160)
                }
                HStack(spacing: 8) {
                    Button("Lint") { if let u = selected?.url { vm.lintSpec(at: u) } }
                    Button("Regenerate") { vm.regenerateFromSpecs() }
                    Button("Reload Routes") { vm.reloadGatewayRoutes() }
                    Spacer()
                    if let u = selected?.url { Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
                }.font(.caption)
            }
            .onAppear { specs = vm.findSpecs() }
        }
    }
}

