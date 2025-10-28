import Foundation

// Typed payload flowing between dashboard nodes
enum Payload {
    case timeSeries([TimeSeries])
    case text(String)
    case none
}

struct TimeSeries: Identifiable {
    var id = UUID()
    var points: [(Date, Double)]
}

enum DashKind: String, Codable { case datasource, query, transform, panelLine, panelStat }

struct DashNode: Codable {
    var id: String
    var kind: DashKind
    var props: [String: String]
}
