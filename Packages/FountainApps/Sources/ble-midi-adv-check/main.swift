import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
import MIDI2Transports

@main
struct Main {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let name = env["BLE_ADV_NAME"] ?? "QuietFrame"
        let seconds = Double(env["BLE_ADV_SECONDS"] ?? "5") ?? 5
        if #available(macOS 12.0, *) {
            let transport = BLEMidiPeripheralTransport(advertisedName: name)
            do { try transport.open() } catch {
                FileHandle.standardError.write(Data("[ble-adv-check] open failed: \(error)\n".utf8))
                exit(2)
            }
            let until = Date().addingTimeInterval(max(1, min(seconds, 30)))
            while Date() < until {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            print("[ble-adv-check] OK — advertising \(name) for ~\(Int(seconds))s")
            do { try transport.close() } catch {}
            exit(0)
        } else {
            FileHandle.standardError.write(Data("[ble-adv-check] requires macOS 12+\n".utf8))
            exit(1)
        }
    }
}

#else
@main
struct Main { static func main() { print("CoreBluetooth unavailable"); exit(0) } }
#endif

