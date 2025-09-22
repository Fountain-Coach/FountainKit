import Foundation
import TutorDashboard

struct ServiceRowModel: Sendable, Equatable {
    let descriptor: ServiceDescriptor
    let baseURL: URL
    let healthStatuses: [ServiceStatus.EndpointStatus]
    let capabilityStatuses: [ServiceStatus.EndpointStatus]

    init(status: ServiceStatus) {
        self.descriptor = status.descriptor
        self.baseURL = status.baseURL
        self.healthStatuses = status.health
        self.capabilityStatuses = status.capabilities
    }

    var serviceName: String { descriptor.title }

    var baseDisplay: String { baseURL.absoluteString }

    var healthSummary: String {
        guard !healthStatuses.isEmpty else { return "—" }
        if healthStatuses.allSatisfy({ $0.ok }) {
            return healthStatuses.count == 1 ? "Healthy" : "Healthy (\(healthStatuses.count))"
        }
        let problems = healthStatuses.compactMap { status -> String? in
            guard !status.ok else { return nil }
            if let code = status.statusCode {
                return "\(status.path) \(code)"
            }
            if let message = status.message, !message.isEmpty {
                return "\(status.path) \(message)"
            }
            return "\(status.path) error"
        }
        return problems.joined(separator: "; ")
    }

    var capabilitySummary: String {
        if capabilityStatuses.isEmpty {
            return descriptor.capabilityPaths.isEmpty ? "—" : "Needs: capabilities"
        }

        var parts: [String] = []
        let available = Set(capabilityStatuses.flatMap { $0.capabilities }).sorted()
        let missing = Set(capabilityStatuses.flatMap { $0.missingCapabilities }).sorted()
        let failures = capabilityStatuses.filter { !$0.ok }

        if !available.isEmpty {
            parts.append(available.joined(separator: ", "))
        }
        if !missing.isEmpty {
            parts.append("Needs: " + missing.joined(separator: ", "))
        }
        for failure in failures {
            if let code = failure.statusCode {
                parts.append("Error \(failure.path) \(code)")
            } else if let message = failure.message, !message.isEmpty {
                parts.append("Error \(failure.path) \(message)")
            } else {
                parts.append("Error \(failure.path)")
            }
        }

        return parts.isEmpty ? "—" : parts.joined(separator: " | ")
    }

    var detailLines: [String] {
        var lines: [String] = []
        lines.append("Service: \(descriptor.title)")
        lines.append("Base URL: \(baseURL.absoluteString)")
        if let binary = descriptor.binaryName {
            lines.append("Binary: \(binary)")
        }
        lines.append("Port: \(descriptor.port)")
        lines.append("Health endpoints:")
        if healthStatuses.isEmpty {
            lines.append("  • None documented in OpenAPI spec")
        } else {
            for status in healthStatuses {
                let symbol = status.ok ? "✓" : "✗"
                let detail: String
                if status.ok {
                    if let code = status.statusCode {
                        detail = "HTTP \(code)"
                    } else {
                        detail = "reachable"
                    }
                } else if let code = status.statusCode {
                    detail = "HTTP \(code)"
                } else if let message = status.message, !message.isEmpty {
                    detail = message
                } else {
                    detail = "unreachable"
                }
                lines.append("  \(symbol) \(status.path) — \(detail)")
            }
        }

        lines.append("Capabilities:")
        if capabilityStatuses.isEmpty {
            if descriptor.capabilityPaths.isEmpty {
                lines.append("  • No capabilities endpoint documented")
            } else {
                lines.append("  • Needs: \(descriptor.capabilityPaths.joined(separator: ", "))")
            }
        } else {
            for status in capabilityStatuses {
                if status.ok {
                    let available = status.capabilities.joined(separator: ", ")
                    let missing = status.missingCapabilities.joined(separator: ", ")
                    let suffix: String
                    if !available.isEmpty && !missing.isEmpty {
                        suffix = "available: \(available); needs: \(missing)"
                    } else if !available.isEmpty {
                        suffix = "available: \(available)"
                    } else if !missing.isEmpty {
                        suffix = "needs: \(missing)"
                    } else {
                        suffix = "reachable"
                    }
                    lines.append("  ✓ \(status.path) — \(suffix)")
                } else {
                    let detail: String
                    if let code = status.statusCode {
                        detail = "HTTP \(code)"
                    } else if let message = status.message, !message.isEmpty {
                        detail = message
                    } else {
                        detail = "unreachable"
                    }
                    lines.append("  ✗ \(status.path) — \(detail)")
                }
            }
        }

        return lines
    }
}
