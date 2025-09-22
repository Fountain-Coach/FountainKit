import Foundation
import SwiftCursesKit

struct ServiceTableFormatter: Sendable {
    let rows: [ServiceRowModel]
    let selectedIndex: Int
    let isRefreshing: Bool
    let message: String?

    func lines(width: Int, height: Int?) -> [String] {
        guard width > 0 else { return [] }

        let columnLayout = ColumnLayout(rows: rows, width: width, selectedIndex: selectedIndex)
        var rendered: [String] = []
        rendered.append(columnLayout.headerLine())
        if width >= 2 {
            rendered.append(String(repeating: "─", count: width))
        } else {
            rendered.append("─")
        }

        let availableHeight = height.map { max(0, $0 - rendered.count) }
        let visibleRows = rowsToDisplay(limit: availableHeight)
        rendered.append(contentsOf: visibleRows.map { columnLayout.render(row: $0.row, index: $0.index, width: width) })

        if rendered.count < (height ?? Int.max), let statusLine = statusLine(width: width) {
            rendered.append(statusLine)
        }

        return rendered
    }

    private func rowsToDisplay(limit: Int?) -> [(row: ServiceRowModel, index: Int)] {
        guard !rows.isEmpty else { return [] }
        let limit = limit ?? rows.count
        guard limit > 0 else { return [] }
        let centerOffset = limit / 2
        let start = max(0, min(selectedIndex - centerOffset, rows.count - limit))
        let end = min(rows.count, start + limit)
        return rows[start..<end].enumerated().map { (offset, row) in
            (row: row, index: start + offset)
        }
    }

    private func statusLine(width: Int) -> String? {
        if let message, !message.isEmpty {
            return pad(message, width: width)
        }
        if isRefreshing {
            return pad("Refreshing…", width: width)
        }
        if rows.isEmpty {
            return pad("No services discovered", width: width)
        }
        return nil
    }

    private func pad(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }
        if text.count >= width {
            return String(text.prefix(width))
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    private struct ColumnLayout {
        let selectionWidth = 2
        let spacing = 2
        let nameWidth: Int
        let baseWidth: Int
        let healthWidth: Int
        let capabilitiesWidth: Int
        let rows: [ServiceRowModel]
        let totalWidth: Int
        let selectedIndex: Int

        init(rows: [ServiceRowModel], width: Int, selectedIndex: Int) {
            self.rows = rows
            self.totalWidth = max(20, width)
            self.selectedIndex = selectedIndex
            let metrics = ColumnMetrics(rows: rows)
            let available = max(0, totalWidth - selectionWidth - spacing * 3)
            let desiredName = max(metrics.maxName, 16)
            let desiredBase = max(metrics.maxBase, 20)
            let desiredHealth = max(metrics.maxHealth, 12)
            var name = min(desiredName, available / 3)
            var base = min(desiredBase, available / 3 + available / 6)
            var health = min(desiredHealth, available / 5)
            if name + base + health > available {
                let overflow = name + base + health - available
                let reduceBase = min(overflow, max(0, base - 16))
                base -= reduceBase
                let reduceName = min(overflow - reduceBase, max(0, name - 12))
                name -= reduceName
                let reduceHealth = min(overflow - reduceBase - reduceName, max(0, health - 10))
                health -= reduceHealth
            }
            let remaining = max(0, available - name - base - health)
            let desiredCapabilities = max(metrics.maxCapabilities, 16)
            var capability = min(desiredCapabilities, remaining)
            if capability < 8 {
                capability = max(8, remaining)
            }
            self.nameWidth = max(12, name)
            self.baseWidth = max(16, base)
            self.healthWidth = max(10, health)
            self.capabilitiesWidth = max(8, capability)
        }

        func headerLine() -> String {
            renderColumns(
                indicator: "  ",
                name: "Service",
                base: "Base URL",
                health: "Health",
                capabilities: "Capabilities"
            )
        }

        func render(row: ServiceRowModel, index: Int, width: Int) -> String {
            let indicator = index == selectedIndex ? "➤ " : "  "
            return renderColumns(
                indicator: indicator,
                name: row.serviceName,
                base: row.baseDisplay,
                health: row.healthSummary,
                capabilities: row.capabilitySummary,
                width: width
            )
        }

        private func renderColumns(
            indicator: String,
            name: String,
            base: String,
            health: String,
            capabilities: String,
            width: Int? = nil
        ) -> String {
            let total = width ?? totalWidth
            let padded = indicator
                + pad(name, width: nameWidth)
                + String(repeating: " ", count: spacing)
                + pad(base, width: baseWidth)
                + String(repeating: " ", count: spacing)
                + pad(health, width: healthWidth)
                + String(repeating: " ", count: spacing)
                + pad(capabilities, width: capabilitiesWidth)
            if padded.count <= total {
                return padded + String(repeating: " ", count: max(0, total - padded.count))
            }
            return String(padded.prefix(total))
        }

        private func pad(_ text: String, width: Int) -> String {
            guard width > 0 else { return "" }
            if text.count >= width {
                return String(text.prefix(width))
            }
            return text + String(repeating: " ", count: width - text.count)
        }
    }

    private struct ColumnMetrics {
        let maxName: Int
        let maxBase: Int
        let maxHealth: Int
        let maxCapabilities: Int

        init(rows: [ServiceRowModel]) {
            self.maxName = max(16, rows.map { $0.serviceName.count }.max() ?? 16)
            self.maxBase = max(20, rows.map { $0.baseDisplay.count }.max() ?? 20)
            self.maxHealth = max(12, rows.map { $0.healthSummary.count }.max() ?? 12)
            self.maxCapabilities = max(16, rows.map { $0.capabilitySummary.count }.max() ?? 16)
        }
    }
}

struct ServiceTableWidget: Widget {
    var rows: [ServiceRowModel]
    var selectedIndex: Int
    var isRefreshing: Bool
    var message: String?

    func measure(in constraints: LayoutConstraints) -> LayoutSize {
        let height = max(6, min(constraints.maxHeight, rows.count + 4))
        let width = max(40, constraints.maxWidth)
        return LayoutSize(width: width, height: height)
    }

    func render(in frame: LayoutRect, buffer: inout RenderBuffer) {
        guard frame.size.width > 0, frame.size.height > 0 else { return }
        let formatter = ServiceTableFormatter(
            rows: rows,
            selectedIndex: selectedIndex,
            isRefreshing: isRefreshing,
            message: message
        )
        let renderedLines = formatter.lines(width: frame.size.width, height: frame.size.height)
        var currentY = frame.origin.y
        for line in renderedLines.prefix(frame.size.height) {
            let point = LayoutPoint(x: frame.origin.x, y: currentY)
            buffer.write(String(line.prefix(frame.size.width)), at: point, maxWidth: frame.size.width)
            currentY += 1
        }
    }
}
