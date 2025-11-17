import Foundation

#if canImport(CoreBluetooth)
import CoreBluetooth

@available(macOS 12.0, *)
public final class BLEMidiPeripheralTransport: NSObject, MIDITransport, @unchecked Sendable {
    public var onReceiveUMP: (([UInt32]) -> Void)?
    public var onReceiveUmps: (([[UInt32]]) -> Void)?

    private let queue = DispatchQueue.main
    private var manager: CBPeripheralManager!
    private var subscribers: [CBCentral] = []
    private var service: CBMutableService?
    private var characteristic: CBMutableCharacteristic?
    private let advertisedName: String
    private var rxSysex: [UInt8]? = nil
    private var ts13: UInt16 = 0 // 13-bit BLE MIDI timestamp counter

    private let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    private let midiCharUUID = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

    public init(advertisedName: String) {
        self.advertisedName = advertisedName
        super.init()
    }

    public func open() throws {
        manager = CBPeripheralManager(delegate: self, queue: queue, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
        #if DEBUG
        print("[BLE-P] Peripheral init (advertised=\(advertisedName))")
        #endif
    }

    public func close() throws {
        manager?.stopAdvertising()
        if let s = service { manager?.remove(s) }
        subscribers.removeAll()
        manager = nil
    }

    // Restart advertising on demand (e.g., when scanners time out)
    public func restartAdvertising() {
        guard let m = manager else { return }
        #if DEBUG
        print("[BLE-P] Restart advertising as \(advertisedName)")
        #endif
        let adv: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: [midiServiceUUID], CBAdvertisementDataLocalNameKey: advertisedName]
        if m.isAdvertising { m.stopAdvertising() }
        m.startAdvertising(adv)
    }

    // Connected centrals count (approximate)
    public var connectedCentralsCount: Int { subscribers.count }
    public var isAdvertising: Bool { manager?.isAdvertising ?? false }

    public func send(umpWords: [UInt32]) throws {
        guard let m = manager, let c = characteristic else { return }
        guard !umpWords.isEmpty else { return }
        #if DEBUG
        print("[BLE-P] TX UMP words=\(umpWords.count)")
        #endif
        let mt = UInt8((umpWords[0] >> 28) & 0xF)
        var midiBytes: [UInt8] = []
        var midiMessages: [[UInt8]] = []
        switch mt {
        case 0x4:
            // Convert to MIDI 1 messages
            midiMessages = BLEMidiTransport.umpCV2ToMIDI1Packets(umpWords)
        case 0x3:
            // SysEx7 → classic MIDI SysEx bytes (we will chunk below)
            midiBytes = [0xF0]
            midiBytes.append(contentsOf: BLEMidiTransport.decodeSysEx7UMP(umpWords))
            midiBytes.append(0xF7)
            midiMessages = [midiBytes]
        case 0x2:
            let status = UInt8((umpWords[0] >> 16) & 0xFF)
            let d1 = UInt8((umpWords[0] >> 8) & 0xFF)
            let d2 = UInt8(umpWords[0] & 0xFF)
            let hi = status & 0xF0
            midiMessages = [(hi == 0xC0 || hi == 0xD0) ? [status, d1] : [status, d1, d2]]
        case 0x1:
            let status = UInt8((umpWords[0] >> 16) & 0xFF)
            let d1 = UInt8((umpWords[0] >> 8) & 0xFF)
            let d2 = UInt8(umpWords[0] & 0xFF)
            switch status {
            case 0xF8, 0xFA, 0xFB, 0xFC, 0xFE, 0xFF, 0xF6: midiMessages = [[status]]
            case 0xF1, 0xF3: midiMessages = [[status, d1]]
            case 0xF2: midiMessages = [[status, d1, d2]]
            default: midiMessages = [[status]]
            }
        default: break
        }
        // Encode to BLE MIDI packets: [timestampHi][timestampLo][midi bytes...], max 20 bytes per update
        func nextTS() -> (UInt8, UInt8) {
            let ts = ts13 & 0x1FFF
            let hi = 0x80 | UInt8((ts >> 7) & 0x7F)
            let lo = 0x80 | UInt8(ts & 0x7F)
            ts13 = (ts13 &+ 1) & 0x1FFF
            return (hi, lo)
        }
        for msg in midiMessages {
            var idx = 0
            while idx < msg.count {
                let (hi, lo) = nextTS()
                var packet = Data([hi, lo])
                let remaining = msg.count - idx
                let room = max(0, 20 - packet.count)
                let n = min(room, remaining)
                packet.append(contentsOf: msg[idx..<(idx+n)])
                idx += n
                _ = m.updateValue(packet, for: c, onSubscribedCentrals: nil)
            }
        }
    }
}

@available(macOS 12.0, *)
extension BLEMidiPeripheralTransport: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        #if DEBUG
        print("[BLE-P] State=\(peripheral.state.rawValue)")
        #endif
        guard peripheral.state == .poweredOn else { return }
        let props: CBCharacteristicProperties = [.notify, .writeWithoutResponse, .read]
        let perms: CBAttributePermissions = [.writeable, .readable]
        let ch = CBMutableCharacteristic(type: midiCharUUID, properties: props, value: nil, permissions: perms)
        let svc = CBMutableService(type: midiServiceUUID, primary: true)
        svc.characteristics = [ch]
        self.service = svc; self.characteristic = ch
        peripheral.add(svc)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            #if DEBUG
            print("[BLE-P] didAdd service error: \(error)")
            #endif
            return
        }
        #if DEBUG
        print("[BLE-P] Service added → start advertising as \(advertisedName)")
        #endif
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [midiServiceUUID], CBAdvertisementDataLocalNameKey: advertisedName])
    }

    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        #if DEBUG
        if let error = error { print("[BLE-P] Advertising error: \(error)") }
        else { print("[BLE-P] Advertising started") }
        #endif
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribers.append(central)
        #if DEBUG
        print("[BLE-P] Central subscribed: id=\(central.identifier)")
        #endif
    }
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.removeAll { $0.identifier == central.identifier }
        #if DEBUG
        print("[BLE-P] Central unsubscribed: id=\(central.identifier)")
        #endif
    }
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        request.value = Data()
        peripheral.respond(to: request, withResult: .success)
        #if DEBUG
        print("[BLE-P] RX read: ok")
        #endif
    }
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let c = characteristic else { return }
        #if DEBUG
        print("[BLE-P] RX writes: count=\(requests.count)")
        #endif
        var umps: [[UInt32]] = []
        for r in requests where r.characteristic.uuid == c.uuid {
            guard let v = r.value else { continue }
            #if DEBUG
            print("[BLE-P] RX bytes=\(v.count)")
            #endif
            let msgs = BLEMidiTransport.parseBLEMidiStream(v)
            for m in msgs {
                guard let status = m.first else { continue }
                if status == 0xF0 {
                    if rxSysex == nil { rxSysex = [] }
                    rxSysex?.append(contentsOf: m.dropFirst())
                } else if status == 0xF7 {
                    let payload = rxSysex ?? []
                    umps.append(contentsOf: BLEMidiTransport.encodeSysEx7UMP(payload))
                    rxSysex = nil
                } else {
                    let d1: UInt8 = m.count > 1 ? m[1] : 0
                    let d2: UInt8 = m.count > 2 ? m[2] : 0
                    let w1 = (UInt32(0x2) << 28) | (0 << 24) | (UInt32(status) << 16) | (UInt32(d1) << 8) | UInt32(d2)
                    umps.append([w1])
                }
                peripheral.respond(to: r, withResult: .success)
            }
        }
        if !umps.isEmpty {
            if let batch = onReceiveUmps { batch(umps) }
            if let single = onReceiveUMP { for u in umps { single(u) } }
        }
    }
}

#endif
