import Foundation
import SwiftUI

@MainActor
enum PrometheusCanvas {
    static func buildPrometheusOverviewCanvas(vm: EditorVM) {
        // Clear existing
        vm.nodes.removeAll()
        vm.edges.removeAll()
        vm.selection = nil
        vm.selected.removeAll()

        // Grid + layout params
        let g = max(1, vm.grid)
        let colW = g * 12
        let rowH = g * 9

        // Helpers
        func addNode(id: String, title: String, x: Int, y: Int, w: Int = 240, h: Int = 120) {
            var ports: [PBPort] = []
            ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
            ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
            let n = PBNode(id: id, title: title, x: x, y: y, w: w, h: h, ports: canonicalSortPorts(ports))
            vm.nodes.append(n)
        }

        // Top row: Prometheus server + Alertmanager
        let serverAddr = (ProcessInfo.processInfo.environment["PROMETHEUS_SERVER_URL"] ?? "http://127.0.0.1:9090")
        let alertAddr = (ProcessInfo.processInfo.environment["ALERTMANAGER_URL"] ?? "http://127.0.0.1:9093")
        addNode(id: "prometheus", title: "prom.server\naddr=\(serverAddr)\nscrape=15s eval=15s", x: g*6, y: g*4)
        addNode(id: "alertmanager", title: "prom.alertmanager\naddr=\(alertAddr)", x: g*22, y: g*4)

        // Rule group under server
        addNode(id: "rules_core", title: "prom.ruleGroup\nname=core\nfile=Configuration/prom-rules/core.yml\ninterval=15s", x: g*6, y: g*14)

        // Scrape targets grid
        let targets = defaultTargets()
        var col = 0
        var row = 0
        for t in targets {
            let url = resolveURL(t)
            let title = "prom.scrapeTarget\njob=\(t.job)\nurl=\(url.absoluteString)\nscheme=\(url.scheme ?? "http")\ninterval=15s timeout=5s\nlabels=service=\(t.job)"
            let x = g*4 + col*colW
            let y = g*22 + row*rowH
            let idBase = t.job.replacingOccurrences(of: " ", with: "-")
            addNode(id: "scrape_\(idBase)", title: title, x: x, y: y)
            col += 1
            if col >= 5 { col = 0; row += 1 }
        }

        // Query panels at bottom
        addNode(id: "q_up_gateway", title: "prom.queryPanel\nexpr=up{job=\"gateway\"}\nrange=5m step=30s refresh=10s", x: g*6, y: g*(22 + row*9 + 10))
        addNode(id: "q_http_rate", title: "prom.queryPanel\nexpr=rate(prometheus_http_requests_total[5m])\nrange=5m step=30s refresh=10s", x: g*22, y: g*(22 + row*9 + 10))
    }
}

