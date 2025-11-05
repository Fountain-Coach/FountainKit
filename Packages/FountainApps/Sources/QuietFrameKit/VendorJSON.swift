import Foundation

public enum QFVendorCommand: Equatable {
    case recStart
    case recStop
    case unknown(topic: String)
}

public enum QFVendorJSON {
    public static func encode(topic: String, data: [String: Any] = [:]) -> [UInt8] {
        var payload: [String: Any] = ["topic": topic]
        if !data.isEmpty { payload["data"] = data }
        let json = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        var bytes: [UInt8] = [0xF0, 0x7D, 0x4A, 0x53, 0x4E, 0x00]
        bytes.append(contentsOf: Array(json))
        bytes.append(0xF7)
        return bytes
    }

    public static func parse(_ bytes: [UInt8]) -> QFVendorCommand? {
        guard bytes.count >= 8, bytes[0] == 0xF0, bytes[1] == 0x7D, bytes[2] == 0x4A, bytes[3] == 0x53, bytes[4] == 0x4E, bytes[5] == 0x00, bytes.last == 0xF7 else { return nil }
        let body = Data(bytes[6..<(bytes.count-1)])
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let topic = obj["topic"] as? String else { return nil }
        switch topic {
        case "rec.start": return .recStart
        case "rec.stop": return .recStop
        default: return .unknown(topic: topic)
        }
    }
}

