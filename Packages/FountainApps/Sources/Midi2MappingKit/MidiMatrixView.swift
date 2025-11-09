import SwiftUI
import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct MidiMatrixView: View {
    @ObservedObject var model: MidiMatrixModel
    @State private var hoverKey: MidiMatrixModel.RouteKey? = nil
    @State private var inspectorKey: MidiMatrixModel.RouteKey? = nil
    @State private var sweepActive: Bool = false
    @State private var sweepTargetOn: Bool = false
    @State private var sweepVisited: Set<MidiMatrixModel.RouteKey> = []
    public init(model: MidiMatrixModel) { self.model = model }

    public var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let leftBand: CGFloat = 140
            let topBand: CGFloat = 110
            let gridW = size - leftBand
            let gridH = size - topBand
            let rows = max(1, model.sources.count)
            let cols = max(1, model.destinations.count)
            let cw = gridW / CGFloat(cols)
            let ch = gridH / CGFloat(rows)

            ZStack(alignment: .topLeading) {
                // Background panel
                RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)

                // Column headers (rotated)
                ForEach(Array(model.destinations.enumerated()), id: \.offset) { col, name in
                    let x = leftBand + CGFloat(col) * cw + cw * 0.5
                    Text(name).font(.caption2).rotationEffect(.degrees(-90)).foregroundStyle(.secondary)
                        .position(x: x, y: topBand * 0.45)
                }
                // Row labels
                ForEach(Array(model.sources.enumerated()), id: \.offset) { row, name in
                    let y = topBand + CGFloat(row) * ch + ch * 0.5
                    HStack(spacing: MidiMapTokens.Spacing.s) {
                        Circle().fill(Color.green.opacity(0.8)).frame(width: 6, height: 6)
                        Text(name).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: leftBand - 8, alignment: .leading)
                    .position(x: (leftBand - 8) * 0.5, y: y)
                }

                // Grid cells
                ForEach(0..<rows, id: \.self) { i in
                    ForEach(0..<cols, id: \.self) { j in
                        let key = MidiMatrixModel.RouteKey(row: i, col: j)
                        let x = leftBand + CGFloat(j) * cw
                        let y = topBand + CGFloat(i) * ch
                        let isOn = model.isOn(key)
                        let isValid = (model.isCellValid?(key) ?? defaultCellValidity(for: key))
                        ZStack {
                            Rectangle()
                                .stroke(MidiMapTokens.Colors.grid, lineWidth: 1)
                                .background(isOn ? MidiMapTokens.Colors.tileOn.opacity(0.35) : Color.clear)
                                .overlay {
                                    if !isValid { HatchView().foregroundStyle(MidiMapTokens.Colors.hatch).clipped() }
                                }
                                .onHover { inside in hoverKey = inside ? key : nil }
                                .contentShape(Rectangle())
                                .allowsHitTesting(isValid)
                                .onTapGesture { if isValid { model.toggle(key) } }
                                .onTapGesture(count: 2) { if isValid { inspectorKey = key } }
                            // Arrow glyph when ON (left→top)
                            if isOn {
                                Path { p in
                                    let pad: CGFloat = 6
                                    let ox = x + cw - pad - 10
                                    let oy = y + pad + 10
                                    p.move(to: CGPoint(x: ox, y: oy))
                                    p.addLine(to: CGPoint(x: ox + 10, y: oy))
                                    p.addLine(to: CGPoint(x: ox + 6, y: oy - 6))
                                    p.move(to: CGPoint(x: ox + 10, y: oy))
                                    p.addLine(to: CGPoint(x: ox + 6, y: oy + 6))
                                }
                                .stroke(Color.white.opacity(0.9), lineWidth: 1)
                            }
                            // Hover/selection ring (thicker when selected)
                            if hoverKey == key && model.selected != key {
                                Rectangle().stroke(MidiMapTokens.Colors.keyline.opacity(0.7), lineWidth: 2)
                            }
                            if model.selected == key {
                                Rectangle().stroke(MidiMapTokens.Colors.keyline, lineWidth: 3)
                            }
                        }
                        .frame(width: cw, height: ch)
                        .position(x: x + cw/2, y: y + ch/2)
                    }
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let p = value.location
                    let key = pointToKey(point: p, leftBand: leftBand, topBand: topBand, cw: cw, ch: ch, rows: rows, cols: cols)
                    guard let key else { return }
                    #if canImport(AppKit)
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    #else
                    let shift = false
                    #endif
                    if !sweepActive && shift {
                        sweepActive = true
                        sweepVisited = []
                        sweepTargetOn = !model.isOn(key)
                    }
                    if sweepActive {
                        if (model.isCellValid?(key) ?? defaultCellValidity(for: key)) && !sweepVisited.contains(key) {
                            model.set(key, on: sweepTargetOn)
                            sweepVisited.insert(key)
                        }
                    }
                }
                .onEnded { _ in
                    sweepActive = false
                    sweepVisited.removeAll()
                }
            )
        }
        .popover(item: Binding<IdentKey?>(
            get: { inspectorKey.map { IdentKey(key: $0) } },
            set: { v in inspectorKey = v?.key }
        )) { _ in
            if let k = inspectorKey { MidiMatrixInspector(model: model, key: k) }
        }
    }

    struct IdentKey: Identifiable { let id = UUID(); let key: MidiMatrixModel.RouteKey }

    private func pointToKey(point: CGPoint, leftBand: CGFloat, topBand: CGFloat, cw: CGFloat, ch: CGFloat, rows: Int, cols: Int) -> MidiMatrixModel.RouteKey? {
        let gx = point.x - leftBand
        let gy = point.y - topBand
        guard gx >= 0, gy >= 0 else { return nil }
        let j = Int(floor(gx / cw))
        let i = Int(floor(gy / ch))
        guard i >= 0, j >= 0, i < rows, j < cols else { return nil }
        return .init(row: i, col: j)
    }

    private func defaultCellValidity(for key: MidiMatrixModel.RouteKey) -> Bool {
        guard key.row < model.sources.count, key.col < model.destinations.count else { return true }
        return model.sources[key.row] != model.destinations[key.col]
    }

    struct HatchView: View {
        var body: some View {
            GeometryReader { g in
                let w = g.size.width
                let h = g.size.height
                let step: CGFloat = 6
                Path { p in
                    var x: CGFloat = -h
                    while x < w { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + h, y: h)); x += step }
                }
                .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .butt))
            }
        }
    }
}

public struct MidiMatrixInspector: View {
    @ObservedObject var model: MidiMatrixModel
    let key: MidiMatrixModel.RouteKey
    @State private var params: MidiRouteParams = .init()
    public init(model: MidiMatrixModel, key: MidiMatrixModel.RouteKey) { self.model = model; self.key = key; _params = State(initialValue: model.params(for: key)) }
    public var body: some View {
        VStack(alignment: .leading, spacing: MidiMapTokens.Spacing.m) {
            Text("Route Inspector").font(.headline)
            Text("\(model.sources[key.row]) → \(model.destinations[key.col])").font(.caption)
            Divider()
            // Channels
            VStack(alignment: .leading, spacing: MidiMapTokens.Spacing.s) {
                Toggle("All channels", isOn: Binding(get: { params.channelMaskAll }, set: { v in params.channelMaskAll = v; if v { params.channels.removeAll() } }))
                if !params.channelMaskAll {
                    WrapGrid(columns: 8, items: Array(1...16)) { idx in
                        let on = params.channels.contains(idx)
                        Button(action: { if on { params.channels.remove(idx) } else { params.channels.insert(idx) } }) { Text("\(idx)").font(.caption2).padding(6).background(on ? Color.accentColor.opacity(0.35) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 4)) }
                    }
                }
            }
            // Group
            HStack { Text("Group").font(.caption); Stepper(value: Binding(get: { params.group }, set: { params.group = min(max(0,$0),15) }), in: 0...15) { Text("\(params.group)").monospaced() } }
            // Filters
            VStack(alignment: .leading) {
                Text("Filters").font(.caption)
                HStack { Toggle("CV2", isOn: Binding(get: { params.filters.cv2 }, set: { params.filters.cv2 = $0 })); Toggle("M1", isOn: Binding(get: { params.filters.m1 }, set: { params.filters.m1 = $0 })); Toggle("PE", isOn: Binding(get: { params.filters.pe }, set: { params.filters.pe = $0 })); Toggle("Util", isOn: Binding(get: { params.filters.utility }, set: { params.filters.utility = $0 })) }
            }
            HStack { Spacer(); Button("Apply") { model.setParams(params, for: key) }; Button("Remove") { model.routes.remove(MidiMatrixModel.RouteKey(row: key.row, col: key.col)) } }
        }
        .padding(12)
        .frame(minWidth: 360)
    }
}

struct WrapGrid<T: Hashable, Content: View>: View {
    let columns: Int
    let items: [T]
    let content: (T) -> Content
    init(columns: Int, items: [T], @ViewBuilder content: @escaping (T) -> Content) { self.columns = columns; self.items = items; self.content = content }
    var body: some View {
        let rows = Int(ceil(Double(items.count)/Double(columns)))
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<columns, id: \.self) { c in
                        let idx = r*columns + c
                        if idx < items.count { content(items[idx]) } else { Spacer().frame(width: 20, height: 20) }
                    }
                }
            }
        }
    }
}
