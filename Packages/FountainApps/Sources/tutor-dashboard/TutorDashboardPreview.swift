import Foundation
import TutorDashboard

struct TutorDashboardPreview {
    var configuration: DashboardConfiguration

    func render(width: Int) async throws {
        let discovery = ServiceDiscovery(openAPIRoot: configuration.openAPIRoot)
        let descriptors = try discovery.loadServices()
        let poller = ServiceStatusPoller()
        let statuses = await poller.fetchStatus(for: descriptors, environment: configuration.environment)
        let rows = statuses.map(ServiceRowModel.init(status:))
        let formatter = ServiceTableFormatter(
            rows: rows,
            selectedIndex: 0,
            isRefreshing: false,
            message: rows.isEmpty ? "No services discovered" : nil
        )
        let snapshot = formatter.lines(width: max(20, width), height: nil).joined(separator: "\n")
        print(snapshot)
    }
}
