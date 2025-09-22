import Foundation

let args = CommandLine.arguments.dropFirst()
if let cmd = args.first {
    do {
        switch cmd {
        case "send":
            var file: String?
            var corr: String?
            var it = args.dropFirst().makeIterator()
            while let a = it.next() {
                if a == "--in", let v = it.next() { file = v }
                else if a == "--corr", let v = it.next() { corr = v }
            }
            guard let f = file else { throw FlexCtlError.usage }
            let words = try sendEnvelope(path: f, corrOverride: corr)
            print(words)
        case "tail":
            var corr: String?
            var it = args.dropFirst().makeIterator()
            while let a = it.next() {
                if a == "--corr", let v = it.next() { corr = v }
            }
            guard let c = corr else { throw FlexCtlError.usage }
            let output = try tail(corr: c, journalDir: ".")
            print(output)
        case "replay":
            var file: String?
            var it = args.dropFirst().makeIterator()
            while let a = it.next() {
                if a == "--ump", let v = it.next() { file = v }
            }
            guard let f = file else { throw FlexCtlError.usage }
            let env = try replayUMP(path: f)
            let data = try JSONEncoder().encode(env)
            if let txt = String(data: data, encoding: .utf8) { print(txt) }
        default:
            throw FlexCtlError.usage
        }
    } catch {
        let msg = "error: \(error)\n"
        FileHandle.standardError.write(Data(msg.utf8))
        exit(1)
    }
} else {
    let msg = "usage: flexctl send|tail|replay\n"
    FileHandle.standardError.write(Data(msg.utf8))
    exit(1)
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
