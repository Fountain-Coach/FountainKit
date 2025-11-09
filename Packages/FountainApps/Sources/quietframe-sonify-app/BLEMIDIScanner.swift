import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
import SwiftUI

@MainActor final class BLEMIDIScanner: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate {
    static let shared = BLEMIDIScanner()
    @Published var devices: [(name: String, rssi: Int)] = []
    private var central: CBCentralManager!
    private override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            let service = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
            central.scanForPeripherals(withServices: [service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let n = peripheral.name ?? "(unnamed)"
        Task { @MainActor in
            if let idx = self.devices.firstIndex(where: { $0.name == n }) {
                self.devices[idx] = (n, RSSI.intValue)
            } else {
                self.devices.append((n, RSSI.intValue))
            }
        }
    }
}
#endif
