import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth

final class Scanner: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private let service = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    private let sem = DispatchSemaphore(value: 0)
    private let timeout: TimeInterval
    init(timeout: TimeInterval) { self.timeout = timeout; super.init() }
    func run() {
        central = CBCentralManager(delegate: self, queue: .main)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { self.sem.signal() }
        _ = sem.wait(timeout: .now() + timeout + 0.5)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "(unnamed)"
        print("BLE-MIDI: name=\(name) id=\(peripheral.identifier.uuidString) rssi=\(RSSI)")
    }
}

@main
struct Main {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let t = Double(env["BLE_SCAN_SECONDS"] ?? "5") ?? 5
        let s = Scanner(timeout: max(1, min(t, 30)))
        s.run()
    }
}

#else
@main
struct Main { static func main() { print("CoreBluetooth unavailable") } }
#endif

