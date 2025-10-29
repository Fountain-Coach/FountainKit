import Foundation

// Typed payload flowing between dashboard nodes
enum Payload {
    case timeSeries([TimeSeries])
    case scalar(Double)
    case table([TableRow])
    case annotations([Annotation])
    case text(String)
    case view(String) // SVG/HTML payload rendered by The Stage
    case none
}

struct TimeSeries: Identifiable {
    var id = UUID()
    var points: [(Date, Double)]
}

struct TableRow: Identifiable {
    var id = UUID()
    var label: String
    var value: Double
}

struct Annotation: Identifiable {
    var id = UUID()
    var time: Date
    var text: String
}

enum DashKind: String, Codable {
    case datasource
    case query
    case transform
    case aggregator
    case topN
    case threshold
    case panelLine
    case panelStat
    case panelTable
    case stageA4
    case replayPlayer
    // Adapters producing Stage-ready views
    case adapterFountain   // .fountain -> SVG (via Teatro)
    case adapterScoreKit   // ScoreKit JSON -> SVG (via TeatroScoreKitRenderer)
}

struct DashNode: Codable {
    var id: String
    var kind: DashKind
    var props: [String: String]
}
