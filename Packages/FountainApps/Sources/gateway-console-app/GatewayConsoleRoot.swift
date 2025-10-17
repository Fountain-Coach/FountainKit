import SwiftUI

struct GatewayConsoleRoot: View {
    @StateObject private var model = GatewayConsoleViewModel()
    @AppStorage("GatewayConsole.BaseURL") private var baseURLString: String = "http://127.0.0.1:8010"
    @AppStorage("GatewayConsole.Bearer") private var bearer: String = ""
    @State private var autoRefresh: Bool = true
    @State private var selectedTab: Tab = .traffic

    enum Tab: String, CaseIterable { case traffic, health, routes }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear { model.configure(baseURLString: baseURLString, bearer: bearer, autoRefresh: autoRefresh) }
        .onChange(of: baseURLString) { _, v in model.setBaseURL(v) }
        .onChange(of: bearer) { _, v in model.setBearer(v) }
        .onChange(of: autoRefresh) { _, v in model.setAutoRefresh(v) }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Gateway Console").font(.title3.weight(.semibold))
            Spacer()
            TextField("http://127.0.0.1:8010", text: $baseURLString)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            SecureField("Bearer (optional)", text: $bearer)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Toggle(isOn: $autoRefresh) { Label("Auto", systemImage: "arrow.triangle.2.circlepath").labelStyle(.iconOnly) }
                .toggleStyle(.button)
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { t in Text(t.rawValue.capitalized).tag(t) }
            }
            .pickerStyle(.segmented)
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .traffic: TrafficView(model: model)
        case .health: HealthView(model: model)
        case .routes: RoutesView(model: model)
        }
    }
}

// MARK: - Traffic

private struct TrafficView: View {
    @ObservedObject var model: GatewayConsoleViewModel
    @State private var methodFilter: String = "ALL"
    @State private var statusFilter: String = "ALL"
    @State private var pathFilter: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Method", selection: $methodFilter) {
                    Text("ALL").tag("ALL"); Text("GET").tag("GET"); Text("POST").tag("POST"); Text("PUT").tag("PUT"); Text("PATCH").tag("PATCH"); Text("DELETE").tag("DELETE")
                }.labelsHidden().frame(width: 90)
                Picker("Status", selection: $statusFilter) {
                    Text("ALL").tag("ALL"); Text("2xx").tag("2xx"); Text("3xx").tag("3xx"); Text("4xx").tag("4xx"); Text("5xx").tag("5xx"); Text("429").tag("429")
                }.labelsHidden().frame(width: 90)
                TextField("Filter path…", text: $pathFilter).textFieldStyle(.roundedBorder)
                Spacer()
                Button { Task { await model.refreshTraffic() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            Divider()
            let filtered = filteredTraffic()
            if filtered.isEmpty {
                Text("No recent traffic.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView { LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { ev in
                            HStack(spacing: 8) {
                                statusDot(ev.status)
                                Text(ev.method).font(.caption.weight(.semibold))
                                Text(ev.path).font(.caption).lineLimit(1)
                                Spacer()
                                Text("\(ev.status)").font(.caption2)
                                Text("\(ev.durationMs)ms").font(.caption2).foregroundStyle(.secondary)
                            }
                            .id(ev.id)
                        }
                    } }
                    .onChange(of: filtered.count) { _, _ in if let last = filtered.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                }
            }
        }
        .padding(8)
    }

    private func filteredTraffic() -> [GatewayConsoleViewModel.TrafficItem] {
        model.traffic.filter { ev in
            var ok = true
            if methodFilter != "ALL" { ok = ok && ev.method == methodFilter }
            if statusFilter != "ALL" {
                if statusFilter == "429" { ok = ok && ev.status == 429 }
                else if statusFilter == "2xx" { ok = ok && (200...299).contains(ev.status) }
                else if statusFilter == "3xx" { ok = ok && (300...399).contains(ev.status) }
                else if statusFilter == "4xx" { ok = ok && (400...499).contains(ev.status) }
                else if statusFilter == "5xx" { ok = ok && (500...599).contains(ev.status) }
            }
            if !pathFilter.isEmpty { ok = ok && ev.path.localizedCaseInsensitiveContains(pathFilter) }
            return ok
        }
    }

    private func statusDot(_ status: Int) -> some View {
        let color: Color = (200...299).contains(status) ? .green : ((400...499).contains(status) ? .orange : .red)
        return Circle().fill(color).frame(width: 10, height: 10)
    }
}

// MARK: - Health

private struct HealthView: View {
    @ObservedObject var model: GatewayConsoleViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { Task { await model.ping(path: "/live") } } label: { Label("Live", systemImage: "heart.fill") }
                Button { Task { await model.ping(path: "/ready") } } label: { Label("Ready", systemImage: "checkmark.seal.fill") }
            }
            .buttonStyle(.borderedProminent)
            if let status = model.lastPingStatus {
                Text("Status: \(status)").font(.caption)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
    }
}

// MARK: - Routes

private struct RoutesView: View {
    @ObservedObject var model: GatewayConsoleViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routes Management").font(.headline)
            Text("Reload dynamic routes from configuration storage.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { Task { await model.reloadRoutes() } } label: { Label("Reload Routes", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(.borderedProminent)
                if let message = model.bannerMessage { Text(message).font(.caption) }
            }
            Spacer()
        }
        .padding(8)
    }
}

// MARK: - ViewModel

@MainActor
final class GatewayConsoleViewModel: ObservableObject {
    struct TrafficItem: Identifiable, Codable { let id = UUID(); let method: String; let path: String; let status: Int; let durationMs: Int; let timestamp: String; let client: String? }

    @Published var traffic: [TrafficItem] = []
    @Published var lastPingStatus: String? = nil
    @Published var lastError: String? = nil
    @Published var bannerMessage: String? = nil

    private var baseURL: URL = URL(string: "http://127.0.0.1:8010")!
    private var bearer: String? = nil
    private var refreshTask: Task<Void, Never>? = nil

    func configure(baseURLString: String, bearer: String, autoRefresh: Bool) {
        setBaseURL(baseURLString)
        setBearer(bearer)
        setAutoRefresh(autoRefresh)
    }

    func setBaseURL(_ s: String) {
        if let u = URL(string: s), u.scheme != nil { baseURL = u }
    }
    func setBearer(_ s: String) { bearer = s.isEmpty ? nil : s }
    func setAutoRefresh(_ enabled: Bool) {
        refreshTask?.cancel(); refreshTask = nil
        guard enabled else { return }
        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshTraffic()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func refreshTraffic() async {
        var url = baseURL
        url.append(path: "/admin/recent")
        var req = URLRequest(url: url)
        if let b = bearer { req.setValue("Bearer \(b)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else { throw NSError(domain: "GatewayConsole", code: http.statusCode) }
            let events = try JSONDecoder().decode([TrafficItem].self, from: data)
            self.traffic = events
            self.lastError = nil
        } catch {
            self.lastError = "Traffic error: \(error.localizedDescription)"
        }
    }

    func reloadRoutes() async {
        var url = baseURL; url.append(path: "/admin/routes/reload")
        var req = URLRequest(url: url); req.httpMethod = "POST"
        if let b = bearer { req.setValue("Bearer \(b)", forHTTPHeaderField: "Authorization") }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 204 { bannerMessage = "Routes reloaded." } else { bannerMessage = "Failed (status \(http.statusCode))" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.bannerMessage = nil }
        } catch {
            bannerMessage = "Reload error: \(error.localizedDescription)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.bannerMessage = nil }
        }
    }

    func ping(path: String) async {
        var url = baseURL; url.append(path: path)
        do {
            let (_, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            lastPingStatus = "\(path): \(http.statusCode)"
            lastError = nil
        } catch {
            lastPingStatus = nil
            lastError = "Ping error: \(error.localizedDescription)"
        }
    }
}

