import Foundation

@main
struct CsoundAudioTest {
    static func main() async {
        let bin = resolveCsound()
        let tmp = makeTempDir()
        let csdURL = tmp.appendingPathComponent("test_tone.csd")
        let wavURL = tmp.appendingPathComponent("out.wav")
        do {
            try writeSimpleToneCSD(to: csdURL)
        } catch {
            fail("write-csd: \(error)")
        }
        let ok = runCsound(bin: bin, csd: csdURL, wav: wavURL)
        guard ok else { exit(2) }
        guard let rms = analyzeRMS(wav: wavURL) else { fail("analyze: no wav data") }
        print(String(format: "rms=%.4f", rms))
        if rms > 0.02 { print("PASS: audible signal present") ; exit(0) }
        else { print("FAIL: too quiet (rms=\(rms))") ; exit(3) }
    }

    static func resolveCsound() -> String {
        if let env = ProcessInfo.processInfo.environment["CSOUND_BIN"], !env.isEmpty { return env }
        let candidates = ["/opt/homebrew/bin/csound", "/usr/local/bin/csound", "/usr/bin/csound", "csound"]
        for c in candidates { if which(c) { return c } }
        fail("csound not found; set CSOUND_BIN")
        return "csound"
    }
    static func which(_ path: String) -> Bool { FileManager.default.isExecutableFile(atPath: path) || (try? runCapture(["which", path])).map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false }

    static func makeTempDir() -> URL {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let dir = cwd.appendingPathComponent(".fountain/artifacts/csound-test/\(Int(Date().timeIntervalSince1970)))", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func writeSimpleToneCSD(to url: URL) throws {
        let csd = """
        <CsoundSynthesizer>
        <CsOptions>
        -W -o out.wav -d
        </CsOptions>
        <CsInstruments>
        sr=48000
        ksmps=64
        nchnls=2
        0dbfs=1
        instr 1
          a1 oscili 0.25, 440, 1
          outs a1, a1
        endin
        </CsInstruments>
        <CsScore>
        f 1 0 16384 10 1
        i 1 0 1
        e
        </CsScore>
        </CsoundSynthesizer>
        """
        try csd.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    static func runCsound(bin: String, csd: URL, wav: URL) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["-W", "-o", wav.path, csd.path]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = pipe
        do { try proc.run() } catch { fail("csound run failed: \(error)") }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let s = String(data: data, encoding: .utf8) { print(s) }
        return proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: wav.path)
    }

    static func analyzeRMS(wav: URL) -> Double? {
        guard let data = try? Data(contentsOf: wav) else { return nil }
        // Minimal WAV parser (PCM 16-bit or 32-bit float)
        func u32le(_ off: Int) -> UInt32 { data.subdata(in: off..<(off+4)).withUnsafeBytes { $0.load(as: UInt32.self) } }
        func u16le(_ off: Int) -> UInt16 { data.subdata(in: off..<(off+2)).withUnsafeBytes { $0.load(as: UInt16.self) } }
        guard data.count > 44 else { return nil }
        // find "fmt " and "data" chunks
        var pos = 12
        var fmtOffset = -1, fmtSize = 0, dataOffset = -1, dataSize = 0
        while pos + 8 <= data.count {
            let id = String(data: data.subdata(in: pos..<(pos+4)), encoding: .ascii) ?? ""
            let size = Int(u32le(pos+4))
            if id == "fmt " { fmtOffset = pos + 8; fmtSize = size }
            if id == "data" { dataOffset = pos + 8; dataSize = size; break }
            pos += 8 + size
        }
        guard fmtOffset >= 0, dataOffset >= 0 else { return nil }
        let audioFormat = u16le(fmtOffset) // 1=PCM, 3=IEEE float
        let channels = Int(u16le(fmtOffset+2))
        let bitsPerSample = Int(u16le(fmtOffset+14))
        guard channels > 0, dataOffset + dataSize <= data.count else { return nil }
        let samples = data.subdata(in: dataOffset..<(dataOffset+dataSize))
        var acc = 0.0; var count = 0
        if audioFormat == 1 && bitsPerSample == 16 {
            for i in stride(from: 0, to: samples.count, by: 2*channels) {
                let s = Int16(bitPattern: samples.subdata(in: i..<(i+2)).withUnsafeBytes { $0.load(as: UInt16.self) })
                let v = Double(s) / 32768.0
                acc += v*v; count += 1
            }
        } else if audioFormat == 3 && bitsPerSample == 32 {
            for i in stride(from: 0, to: samples.count, by: 4*channels) {
                let v = samples.subdata(in: i..<(i+4)).withUnsafeBytes { $0.load(as: Float.self) }
                acc += Double(v*v); count += 1
            }
        } else { return nil }
        guard count > 0 else { return nil }
        return sqrt(acc / Double(count))
    }

    static func runCapture(_ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env"); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    static func fail(_ msg: String) -> Never { fputs("ERROR: \(msg)\n", stderr); exit(1) }
}

