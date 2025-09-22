import Foundation
import FountainExamples

@main
struct HelloFountainAITeatro {
    static func main() async throws {
        let example = GatewayPlannerFunctionCallerExample()
        _ = try await example.seedDemoData()
        let outcome = try await example.runDemoFlow(objective: "Render Teatro greeting")

        print("Gateway→Planner→Function-Caller demo")
        print("Objective: \(outcome.plan.objective)")
        if let function = outcome.functions.functions.first {
            print("First function: \(function.name) [\(function.function_id)]")
        }
        for result in outcome.execution.results {
            print("Executed step: \(result.step) -> \(result.output)")
        }
    }
}
