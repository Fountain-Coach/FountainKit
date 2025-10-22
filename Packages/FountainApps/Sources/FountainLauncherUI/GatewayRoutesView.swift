import SwiftUI

struct GatewayRoutesView: View {
    @ObservedObject var vm: LauncherViewModel
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Routes").font(.subheadline)
                Spacer()
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
        vm.fetchGatewayRoutes { json in
            DispatchQueue.main.async { self.text = json }
        }
    }
}

