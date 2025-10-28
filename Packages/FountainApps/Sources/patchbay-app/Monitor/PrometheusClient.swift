import Foundation

enum PrometheusClientError: Error { case badURL, badResponse }

struct PrometheusResponse: Codable {
    struct DataField: Codable {
        struct Series: Codable {
            struct ValuePoint: Codable {
                let value: [PromValue]
                enum PromValue: Codable {
                    case num(Double)
                    case str(String)
                    init(from decoder: Decoder) throws {
                        var c = try decoder.unkeyedContainer()
                        _ = try c.decode(Double.self) // timestamp (unused; we pass via outer)
                        if let n = try? c.decode(Double.self) { self = .num(n) } else { self = .str(try c.decode(String.self)) }
                    }
                    func encode(to encoder: Encoder) throws {
                        var c = encoder.unkeyedContainer()
                        try c.encode(0.0)
                        switch self {
                        case .num(let d): try c.encode(d)
                        case .str(let s): try c.encode(s)
                        }
                    }
                }
                enum CodingKeys: String, CodingKey { case value }
            }
            let values: [[String]]? // sometimes strings
            let value: [String]?     // or single value
            let metric: [String:String]
        }
        let resultType: String
        let result: [Series]
    }
    let status: String
    let data: DataField
}

@MainActor
func queryRange(baseURL: URL, promQL: String, start: Date, end: Date, step: Int) async throws -> [TimeSeries] {
    var url = baseURL
    url.append(path: "/api/v1/query_range")
    guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw PrometheusClientError.badURL }
    comps.queryItems = [
        URLQueryItem(name: "query", value: promQL),
        URLQueryItem(name: "start", value: String(Int(start.timeIntervalSince1970))),
        URLQueryItem(name: "end", value: String(Int(end.timeIntervalSince1970))),
        URLQueryItem(name: "step", value: String(step))
    ]
    guard let finalURL = comps.url else { throw PrometheusClientError.badURL }
    let (data, resp) = try await URLSession.shared.data(from: finalURL)
    guard (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { throw PrometheusClientError.badResponse }
    let decoded = try JSONDecoder().decode(PrometheusResponse.self, from: data)
    // Map result → [TimeSeries]
    var series: [TimeSeries] = []
    for s in decoded.data.result {
        var pts: [(Date, Double)] = []
        if let values = s.values { // [[ts, value]] where both strings
            for v in values {
                if v.count >= 2, let ts = Double(v[0]), let y = Double(v[1]) {
                    pts.append((Date(timeIntervalSince1970: ts), y))
                }
            }
        } else if let value = s.value { // [ts, value]
            if value.count >= 2, let ts = Double(value[0]), let y = Double(value[1]) {
                pts.append((Date(timeIntervalSince1970: ts), y))
            }
        }
        series.append(TimeSeries(points: pts))
    }
    return series
}

