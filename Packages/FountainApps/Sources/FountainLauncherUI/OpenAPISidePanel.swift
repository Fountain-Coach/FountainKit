import SwiftUI
import AppKit

struct OpenAPISidePanel: View {
    @ObservedObject var vm: LauncherViewModel
    @State private var specs: [SpecItem] = []
    @State private var selected: SpecItem? = nil
    @State private var filter: String = ""
    @State private var content: String = ""
    @State private var status: String? = nil

    var body: some View {
        GroupBox(label: Text("OpenAPI Specs")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Filter", text: $filter)
                    Spacer()
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                    Button("Refresh") { refreshList(selectFirstIfNeeded: true) }
                }
                HStack(alignment: .top, spacing: 8) {
                    List(selection: Binding(get: { selected }, set: { selected = $0 })) {
                        ForEach(specs.filter { filter.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(filter) }) { item in
                            HStack { Image(systemName: "doc.text"); Text(item.name) }.tag(item as SpecItem?)
                        }
                    }
                    .frame(minWidth: 160, maxHeight: 160)
                    TextEditor(text: $content)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 160)
                }
                HStack(spacing: 8) {
                    Button("Lint") {
                        guard let u = selected?.url else { flash("Select a spec first") ; return }
                        flash("Linting…"); vm.lintSpec(at: u); finishLater("Lint complete")
                    }
                    Button("Regenerate") { flash("Regenerating…"); vm.regenerateFromSpecs(); finishLater("Regenerate triggered") }
                    Button("Reload Routes") { flash("Reloading routes…"); vm.reloadGatewayRoutes(); finishLater("Reload requested") }
                    Button("Save") {
                        guard let u = selected?.url else { flash("Select a spec first"); return }
                        vm.writeSpec(at: u, content: content); flash("Saved"); finishLater(nil)
                    }
                    Button("Revert") { if let u = selected?.url { content = vm.readSpec(at: u); flash("Reverted"); finishLater(nil) } }
                    Spacer()
                    if let u = selected?.url { Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
                }.font(.caption)
            }
            .onAppear { refreshList(selectFirstIfNeeded: true) }
        }
        GroupBox(label: Text("Gateway Routes")) {
            GatewayRoutesView(vm: vm)
                .frame(minHeight: 160)
        }
        .onChange(of: selected) { _ in if let u = selected?.url { content = vm.readSpec(at: u) } else { content = "" } }
    }

    private func refreshList(selectFirstIfNeeded: Bool) {
        specs = vm.curatedSpecs()
        if selectFirstIfNeeded, selected == nil, let first = specs.first {
            selected = first
            content = vm.readSpec(at: first.url)
        }
    }
    private func flash(_ s: String?) { status = s }
    private func finishLater(_ s: String?, delay: TimeInterval = 1.2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { withAnimation { status = s } }
        if s != nil { DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.8) { withAnimation { status = nil } } }
    }
}
