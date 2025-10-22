import SwiftUI

struct GatewayRoutesView: View {
    @ObservedObject var vm: LauncherViewModel
    @State private var text: String = ""
    @State private var isLoading: Bool = false
    @State private var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Routes").font(.subheadline)
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.7) }
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                Button("Refresh") { refresh() }
            }
            ScrollView {
                Text(text.isEmpty ? "(no data)" : text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        isLoading = true; error = nil
        vm.fetchGatewayRoutes { json in
            DispatchQueue.main.async {
                self.isLoading = false
                if json == "__INVALID_URL__" {
                    self.text = ""
                    self.error = "Set Gateway URL under Environment"
                } else {
                    self.text = json
                    self.error = nil
                }
            }
        }
    }
}
