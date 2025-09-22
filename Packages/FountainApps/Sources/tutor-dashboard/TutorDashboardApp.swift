import Foundation
import SwiftCursesKit
import TutorDashboard

struct TutorDashboardApp: TerminalApp {
    var configuration: DashboardConfiguration
    private var discovery: ServiceDiscovery
    private var poller: ServiceStatusPoller

    private var statuses: [ServiceStatus] = []
    private var selectedIndex: Int = 0
    private var isRefreshing: Bool = false
    private var lastRefreshTick: Int = .min
    private var tickCount: Int = 0
    private var performedInitialRefresh = false
    private var lastUpdated: Date?
    private var message: String? = "Loading OpenAPI specs…"
    private var escapeState: EscapeSequenceState = .idle

    init(configuration: DashboardConfiguration) {
        self.configuration = configuration
        self.discovery = ServiceDiscovery(openAPIRoot: configuration.openAPIRoot)
        self.poller = ServiceStatusPoller()
    }

    var banner: String { "FountainAI Tutor Dashboard" }

    var body: some Scene {
        Screen {
            VStack(spacing: 1) {
                Title("FountainAI Tutor Dashboard")
                WidgetView(ServiceTableWidget(
                    rows: rows,
                    selectedIndex: selectedIndex,
                    isRefreshing: isRefreshing,
                    message: tableMessage
                ))
                LogView(
                    lines: detailLines,
                    maximumVisibleLines: 8
                )
                StatusBar(items: statusBarItems)
            }
            .padding(1)
        }
    }

    mutating func onEvent(_ event: Event, context: AppContext) async {
        switch event {
        case .tick:
            tickCount += 1
            await handleTick()
        case let .key(key):
            await handleKey(key, context: context)
        }
    }

    private mutating func handleTick() async {
        if !performedInitialRefresh {
            performedInitialRefresh = true
            await refreshStatuses()
            return
        }

        if tickCount - lastRefreshTick >= configuration.refreshIntervalTicks {
            await refreshStatuses()
        }
    }

    private mutating func handleKey(_ key: KeyEvent, context: AppContext) async {
        switch key {
        case let .character(character):
            await interpret(character: character, context: context)
        }
    }

    private mutating func interpret(character: Character, context: AppContext) async {
        switch escapeState {
        case .idle:
            if character == "\u{1B}" {
                escapeState = .sawEscape
                return
            }
            await handleBaseKey(character: character, context: context)
        case .sawEscape:
            if character == "[" {
                escapeState = .sawBracket
            } else {
                escapeState = .idle
                await handleBaseKey(character: character, context: context)
            }
        case .sawBracket:
            escapeState = .idle
            switch character {
            case "A":
                moveSelection(delta: -1)
            case "B":
                moveSelection(delta: 1)
            case "H":
                moveSelection(to: 0)
            case "F":
                moveSelection(to: rows.count - 1)
            default:
                break
            }
        }
    }

    private mutating func handleBaseKey(character: Character, context: AppContext) async {
        switch character {
        case "q", "Q":
            await context.quit()
        case "r", "R":
            await refreshStatuses()
        case "j", "J", "\u{000A}", "\u{000D}", "\t":
            moveSelection(delta: 1)
        case "k", "K":
            moveSelection(delta: -1)
        case "g":
            moveSelection(to: 0)
        case "G":
            moveSelection(to: rows.count - 1)
        default:
            break
        }
    }

    private mutating func moveSelection(delta: Int) {
        guard !rows.isEmpty else { return }
        let newIndex = max(0, min(rows.count - 1, selectedIndex + delta))
        selectedIndex = newIndex
    }

    private mutating func moveSelection(to index: Int) {
        guard !rows.isEmpty else { return }
        let clamped = max(0, min(rows.count - 1, index))
        selectedIndex = clamped
    }

    private mutating func refreshStatuses() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        message = "Refreshing…"
        defer {
            isRefreshing = false
            lastRefreshTick = tickCount
        }

        do {
            let descriptors = try discovery.loadServices()
            let fetched = await poller.fetchStatus(for: descriptors, environment: configuration.environment)
            statuses = fetched
            if selectedIndex >= rows.count {
                selectedIndex = max(0, rows.count - 1)
            }
            lastUpdated = Date()
            message = rows.isEmpty ? "No services discovered" : nil
        } catch {
            message = "Failed to load OpenAPI specs: \(error.localizedDescription)"
        }
    }

    private var rows: [ServiceRowModel] {
        statuses.map(ServiceRowModel.init(status:))
    }

    private var tableMessage: String? {
        if let message {
            return message
        }
        if rows.isEmpty {
            return "Waiting for service status…"
        }
        return nil
    }

    private var detailLines: [String] {
        var lines: [String] = []
        if let row = rows[safe: selectedIndex] {
            lines.append(contentsOf: row.detailLines)
        } else if let message {
            lines.append(message)
        } else {
            lines.append("Select a service to view details.")
        }
        lines.append(contentsOf: instructions)
        return lines
    }

    private var instructions: [String] {
        [
            "Use ↑/↓ or Tab to move between services.",
            "Press r to refresh, q to quit."
        ]
    }

    private var statusBarItems: [StatusBar.Item] {
        var items: [StatusBar.Item] = [
            .label("q: quit"),
            .label("r: refresh"),
            .label("↑/↓: move"),
            .label("tab: cycle"),
            .label("services: \(rows.count)")
        ]
        if isRefreshing {
            items.append(.label("refreshing…"))
        } else if let lastUpdated {
            items.append(.label("updated: \(formatted(time: lastUpdated))"))
        }
        return items
    }

    private func formatted(time: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = .current
        return formatter.string(from: time)
    }

    private enum EscapeSequenceState {
        case idle
        case sawEscape
        case sawBracket
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
