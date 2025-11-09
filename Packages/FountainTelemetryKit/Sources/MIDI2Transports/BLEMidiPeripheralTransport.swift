import Foundation

#if canImport(CoreBluetooth)
import CoreBluetooth

@available(macOS 12.0, *)
public final class BLEMidiPeripheralTransport: NSObject, MIDITransport, @unchecked Sendable {
    public var onReceiveUMP: (([UInt32]) -> Void)?
    public var onReceiveUmps: (([[UInt32]]) -> Void)?

    private let queue = DispatchQueue(label: "BLEMidiPeripheralQueue")
    private var manager: CBPeripheralManager!
    private var subscribers: [CBCentral] = []
    private var service: CBMutableService?
    private var characteristic: CBMutableCharacteristic?
    private let advertisedName: String
    private var rxSysex: [UInt8]? = nil

    private let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    private let midiCharUUID = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

    public init(advertisedName: String) {
        self.advertisedName = advertisedName
        super.init()
    }

    public func open() throws {
        manager = CBPeripheralManager(delegate: self, queue: queue)
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

    public func send(umpWords: [UInt32]) throws {
        guard let m = manager, let c = characteristic else { return }
        guard !umpWords.isEmpty else { return }
        #if DEBUG
        print("[BLE-P] TX UMP words=\(umpWords.count)")
        #endif
        let mt = UInt8((umpWords[0] >> 28) & 0xF)
        var packets: [Data] = []
        switch mt {
        case 0x4:
            for bytes in BLEMidiTransport.umpCV2ToMIDI1Packets(umpWords) { var d = Data([0x80]); d.append(contentsOf: bytes); packets.append(d) }
        case 0x2:
            let status = UInt8((umpWords[0] >> 16) & 0xFF)
            let d1 = UInt8((umpWords[0] >> 8) & 0xFF)
            let d2 = UInt8(umpWords[0] & 0xFF)
            let hi = status & 0xF0
            let bytes: [UInt8] = (hi == 0xC0 || hi == 0xD0) ? [status, d1] : [status, d1, d2]
            var d = Data([0x80]); d.append(contentsOf: bytes); packets.append(d)
        case 0x3:
            let payload = BLEMidiTransport.decodeSysEx7UMP(umpWords)
            var idx = 0
            while idx < payload.count {
                let n = min(19, payload.count - idx)
                var d = Data([0x80, 0xF0])
                d.append(contentsOf: payload[idx..<(idx+n)])
                if idx + n >= payload.count { d.append(0xF7) }
                packets.append(d)
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
            var d = Data([0x80]); d.append(contentsOf: bytes); packets.append(d)
        default:
            break
        }
        for p in packets { _ = m.updateValue(p, for: c, onSubscribedCentrals: nil) }
    }
}

@available(macOS 12.0, *)
extension BLEMidiPeripheralTransport: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        #if DEBUG
        print("[BLE-P] State=\(peripheral.state.rawValue)")
        #endif
        guard peripheral.state == .poweredOn else { return }
        let props: CBCharacteristicProperties = [.notify, .writeWithoutResponse]
        let perms: CBAttributePermissions = [.writeable]
        let ch = CBMutableCharacteristic(type: midiCharUUID, properties: props, value: nil, permissions: perms)
        let svc = CBMutableService(type: midiServiceUUID, primary: true)
        svc.characteristics = [ch]
        self.service = svc; self.characteristic = ch
        peripheral.add(svc)
        #if DEBUG
        print("[BLE-P] Service added → start advertising as \(advertisedName)")
        #endif
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [midiServiceUUID], CBAdvertisementDataLocalNameKey: advertisedName])
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
            }
        }
        if !umps.isEmpty {
            if let batch = onReceiveUmps { batch(umps) }
            if let single = onReceiveUMP { for u in umps { single(u) } }
        }
    }
}

#endif
