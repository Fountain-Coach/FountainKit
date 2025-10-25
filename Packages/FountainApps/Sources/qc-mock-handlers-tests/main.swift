import Foundation
import qc_mock_service

@main
struct Main {
    static func main() {
        do {
            try QCMockServiceSelfTest.runSync()
            print("[qc-mock-handlers-tests] PASS")
        } catch {
            fputs("[qc-mock-handlers-tests] FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}

