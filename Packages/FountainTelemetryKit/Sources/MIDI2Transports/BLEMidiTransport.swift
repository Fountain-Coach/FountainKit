import Foundation

#if canImport(CoreBluetooth)
import CoreBluetooth

@available(macOS 12.0, *)
public final class BLEMidiTransport: NSObject, MIDITransport, @unchecked Sendable {
    public var onReceiveUMP: (([UInt32]) -> Void)?
    public var onReceiveUmps: (([[UInt32]]) -> Void)?

    private let queue = DispatchQueue(label: "BLEMidiTransportQueue")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var midiChar: CBCharacteristic?
    private let targetNameSubstring: String?
    private var rxSysex: [UInt8]? = nil
    private var reconnectAttempts: Int = 0
    private var reconnectWork: DispatchWorkItem?

    // BLE MIDI 1.0 service/characteristic UUIDs
    private let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    private let midiCharUUID = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

    public init(targetNameContains: String? = nil) {
        self.targetNameSubstring = targetNameContains
        super.init()
    }

    public func open() throws {
        // CoreBluetooth requires main queue for some operations; delegate callbacks can hop back to queue.
        central = CBCentralManager(delegate: self, queue: queue)
        #if DEBUG
        print("[BLE] Central init (target=\(targetNameSubstring ?? "<any>"))")
        #endif
    }

    public func close() throws {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        midiChar = nil
        central = nil
        reconnectWork?.cancel(); reconnectWork = nil; reconnectAttempts = 0
    }

    public func send(umpWords: [UInt32]) throws {
        guard let p = peripheral, let c = midiChar else { return }
        guard !umpWords.isEmpty else { return }
        let mt = UInt8((umpWords[0] >> 28) & 0xF)
        var txBytes: Int = 0
        switch mt {
        case 0x4:
            let packets = Self.umpCV2ToMIDI1Packets(umpWords)
            for bytes in packets {
                var data = Data([0x80])
                data.append(contentsOf: bytes)
                p.writeValue(data, for: c, type: .withoutResponse)
                txBytes += data.count
            }
        case 0x2:
            let status = UInt8((umpWords[0] >> 16) & 0xFF)
            let d1 = UInt8((umpWords[0] >> 8) & 0xFF)
            let d2 = UInt8(umpWords[0] & 0xFF)
            let hi = status & 0xF0
            let bytes: [UInt8] = (hi == 0xC0 || hi == 0xD0) ? [status, d1] : [status, d1, d2]
            var data = Data([0x80]); data.append(contentsOf: bytes)
            p.writeValue(data, for: c, type: .withoutResponse)
            txBytes += data.count
        case 0x3:
            let payload = Self.decodeSysEx7UMP(umpWords)
            guard !payload.isEmpty else { return }
            var idx = 0
            while idx < payload.count {
                let n = min(19, payload.count - idx) // 1 byte ts + up to 19 data
                var data = Data([0x80, 0xF0])
                data.append(contentsOf: payload[idx..<(idx+n)])
                if idx + n >= payload.count { data.append(0xF7) }
                p.writeValue(data, for: c, type: .withoutResponse)
                txBytes += data.count
                idx += n
            }
        case 0x1:
            let status = UInt8((umpWords[0] >> 16) & 0xFF)
            let d1 = UInt8((umpWords[0] >> 8) & 0xFF)
            let d2 = UInt8(umpWords[0] & 0xFF)
            let bytes: [UInt8]
            switch status {
            case 0xF8, 0xFA, 0xFB, 0xFC, 0xFE, 0xFF, 0xF6: bytes = [status]
            case 0xF1, 0xF3: bytes = [status, d1]
            case 0xF2: bytes = [status, d1, d2]
            default: bytes = [status]
            }
            var data = Data([0x80]); data.append(contentsOf: bytes)
            p.writeValue(data, for: c, type: .withoutResponse)
            txBytes += data.count
        default:
            break
        }
        NotificationCenter.default.post(name: Notification.Name("BLETransportEvent"), object: nil, userInfo: ["event":"tx","bytes": txBytes])
    }

    // Minimal UMP → MIDI 1.0 mapping for common Channel Voice 2.0 messages.
    static func umpCV2ToMIDI1Packets(_ words: [UInt32]) -> [[UInt8]] {
        guard !words.isEmpty else { return [] }
        var out: [[UInt8]] = []
        var i = 0
        while i < words.count {
            let w1 = words[i]
            let mt = UInt8((w1 >> 28) & 0xF)
            if mt == 0x4 { // MIDI 2.0 Channel Voice
                if i + 1 >= words.count { break }
                let w2 = words[i+1]
                let statusHi = UInt8((w1 >> 20) & 0xF) << 4
                let ch = UInt8((w1 >> 16) & 0xF)
                switch statusHi {
                case 0x90: // Note On
                    let note = UInt8((w1 >> 8) & 0xFF)
                    let v16 = UInt16((w2 >> 16) & 0xFFFF)
                    let vel7 = UInt8((UInt32(v16) * 127) / 65535)
                    out.append([0x90 | ch, note, vel7])
                case 0x80: // Note Off
                    let note = UInt8((w1 >> 8) & 0xFF)
                    out.append([0x80 | ch, note, 0])
                case 0xB0: // CC
                    let cc = UInt8((w1 >> 8) & 0xFF)
                    let v32 = w2
                    let v7 = UInt8((Double(v32) / 4294967295.0 * 127.0).rounded())
                    out.append([0xB0 | ch, cc, v7])
                case 0xE0: // Pitch Bend
                    let v32 = w2
                    let v14 = UInt16((Double(v32) / 4294967295.0 * 16383.0).rounded())
                    let lsb = UInt8(v14 & 0x7F)
                    let msb = UInt8((v14 >> 7) & 0x7F)
                    out.append([0xE0 | ch, lsb, msb])
                default:
                    break
                }
                i += 2
            } else if mt == 0x3 {
                break
            } else {
                i += 1
            }
        }
        return out
    }
    // Decode a single UMP SysEx7 message into raw payload bytes (no 0xF0/0xF7)
    static func decodeSysEx7UMP(_ words: [UInt32]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i + 1 < words.count {
            let w1 = words[i], w2 = words[i+1]
            if ((w1 >> 28) & 0xF) != 0x3 { break }
            let n = Int((w1 >> 16) & 0xF)
            let b0 = UInt8((w1 >> 8) & 0xFF)
            let b1 = UInt8(w1 & 0xFF)
            let b2 = UInt8((w2 >> 24) & 0xFF)
            let b3 = UInt8((w2 >> 16) & 0xFF)
            let b4 = UInt8((w2 >> 8) & 0xFF)
            let b5 = UInt8(w2 & 0xFF)
            let chunk = [b0,b1,b2,b3,b4,b5].prefix(n)
            out.append(contentsOf: chunk)
            i += 2
        }
        return out
    }

    // Parse BLE MIDI 1.0 characteristic payload into a list of MIDI 1.0 messages (status+data bytes)
    static func parseBLEMidiStream(_ data: Data) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var idx = 0
        var status: UInt8? = nil
        var seenTimestamp = false
        while idx < data.count {
            let b = data[idx]
            if status == nil {
                // Looking for status; BLE timestamp headers are 0x80..0xBF
                if b >= 0x80 && b <= 0xBF {
                    if !seenTimestamp {
                        seenTimestamp = true; idx += 1; continue
                    } else {
                        // Second MSB=1 in timestamp range after a timestamp → treat as status
                        status = b; seenTimestamp = false; idx += 1; continue
                    }
                }
                if b >= 0x80 {
                    status = b; idx += 1; seenTimestamp = false; continue
                }
                // Data byte without status; skip
                idx += 1; continue
            } else {
                let hi = status! & 0xF0
                switch hi {
                case 0xC0, 0xD0: // two-byte messages: status + 1 data
                    if idx < data.count {
                        let d1 = data[idx]
                        out.append([status!, d1])
                        status = nil
                        idx += 1
                    } else { idx = data.count }
                case 0x80, 0x90, 0xA0, 0xB0, 0xE0: // three-byte messages
                    if idx + 1 < data.count {
                        let d1 = data[idx]
                        let d2 = data[idx+1]
                        out.append([status!, d1, d2])
                        status = nil
                        idx += 2
                    } else { idx = data.count }
                default:
                    // Unsupported; resync
                    status = nil; idx += 1
                }
            }
        }
        return out
    }
}

@available(macOS 12.0, *)
extension BLEMidiTransport: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        #if DEBUG
        print("[BLE] Central state=poweredOn → scanning for MIDI service…")
        #endif
        central.scanForPeripherals(withServices: [midiServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        #if DEBUG
        print("[BLE] Discovered: name=\(peripheral.name ?? "<nil>") rssi=\(RSSI)")
        #endif
        if let sub = targetNameSubstring, let name = peripheral.name, !name.localizedCaseInsensitiveContains(sub) {
            return
        }
        self.peripheral = peripheral
        central.stopScan()
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        #if DEBUG
        print("[BLE] Connected: name=\(peripheral.name ?? "<nil>") → discovering services")
        #endif
        reconnectAttempts = 0; reconnectWork?.cancel(); reconnectWork = nil
        NotificationCenter.default.post(name: Notification.Name("BLETransportEvent"), object: nil, userInfo: ["event":"connected","name": peripheral.name ?? ""])    
        peripheral.discoverServices([midiServiceUUID])
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        NotificationCenter.default.post(name: Notification.Name("BLETransportEvent"), object: nil, userInfo: ["event":"disconnected","name": peripheral.name ?? ""])    
        let attempt = min(reconnectAttempts + 1, 5)
        reconnectAttempts = attempt
        let delay = pow(2.0, Double(attempt))
        #if DEBUG
        print("[BLE] Disconnected. Reconnecting in ~\(Int(delay))s…")
        #endif
        let work = DispatchWorkItem { [weak self] in
            guard let self, let c = self.central else { return }
            c.scanForPeripherals(withServices: [self.midiServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        reconnectWork?.cancel(); reconnectWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        #if DEBUG
        print("[BLE] Services discovered: count=\(peripheral.services?.count ?? 0) → discovering characteristic")
        #endif
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics([midiCharUUID], for: s) }
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == midiCharUUID {
                self.midiChar = c
                #if DEBUG
                print("[BLE] MIDI characteristic found → enabling notifications")
                #endif
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let v = characteristic.value, characteristic.uuid == midiCharUUID else { return }
        #if DEBUG
        print("[BLE] RX \(v.count) bytes")
        #endif
        NotificationCenter.default.post(name: Notification.Name("BLETransportEvent"), object: nil, userInfo: ["event":"rx","bytes": v.count])
        // Parse BLE MIDI 1.0 frames → MIDI 1.0 messages
        let msgs = Self.parseBLEMidiStream(v)
        if msgs.isEmpty { return }
        var umps: [[UInt32]] = []
        for m in msgs {
            guard let status = m.first else { continue }
            if status == 0xF0 {
                // Begin/continue SysEx accumulation
                if rxSysex == nil { rxSysex = [] }
                rxSysex?.append(contentsOf: m.dropFirst())
            } else if status == 0xF7 {
                // End SysEx; encode to UMP chunks
                let payload = rxSysex ?? []
                umps.append(contentsOf: Self.encodeSysEx7UMP(payload))
                rxSysex = nil
            } else {
                let d1: UInt8 = m.count > 1 ? m[1] : 0
                let d2: UInt8 = m.count > 2 ? m[2] : 0
                let w1 = (UInt32(0x2) << 28) | (0 << 24) | (UInt32(status) << 16) | (UInt32(d1) << 8) | UInt32(d2)
                umps.append([w1])
            }
        }
        if !umps.isEmpty {
            if let batch = onReceiveUmps { batch(umps) }
            if let single = onReceiveUMP { for u in umps { single(u) } }
        }
    }
}

@available(macOS 12.0, *)
extension BLEMidiTransport {
    // Encode raw SysEx7 payload (no 0xF0/0xF7) to UMP SysEx7 chunks
    static func encodeSysEx7UMP(_ bytes: [UInt8]) -> [[UInt32]] {
        if bytes.isEmpty { return [] }
        var umps: [[UInt32]] = []
        var idx = 0
        var first = true
        while idx < bytes.count {
            let remain = bytes.count - idx
            let n = min(6, remain)
            let status: UInt8
            if first && n == remain { status = 0x0 }
            else if first { status = 0x1 }
            else if n == remain { status = 0x3 }
            else { status = 0x2 }
            var chunk = Array(bytes[idx..<(idx+n)])
            while chunk.count < 6 { chunk.append(0) }
            let w1 = (UInt32(0x3) << 28) | (0 << 24) | (UInt32(status) << 20) | (UInt32(n) << 16) | (UInt32(chunk[0]) << 8) | UInt32(chunk[1])
            let w2 = (UInt32(chunk[2]) << 24) | (UInt32(chunk[3]) << 16) | (UInt32(chunk[4]) << 8) | UInt32(chunk[5])
            umps.append([w1, w2])
            idx += n
            first = false
        }
        return umps
    }
}

#endif
