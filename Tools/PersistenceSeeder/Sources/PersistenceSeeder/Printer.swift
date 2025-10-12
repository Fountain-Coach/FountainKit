import Foundation

struct JSONPrinter {
    private let encoder: JSONEncoder

    init(pretty: Bool = true) {
        encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        encoder.dateEncodingStrategy = .iso8601
    }

    func print<T: Encodable>(_ value: T) throws {
        let data = try encoder.encode(value)
        if let string = String(data: data, encoding: .utf8) {
            Swift.print(string)
        }
    }
}
