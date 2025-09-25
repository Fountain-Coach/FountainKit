# FountainExamples

The `FountainExamples` package hosts integration demos that stitch together the
independent FountainKit libraries. Each example is built as a normal SwiftPM
target so CI can compile and exercise them alongside the rest of the workspace.

## HelloFountainAITeatro

`hello-fountainai-teatro` demonstrates a minimal gateway → planner →
function-caller flow. The executable seeds an in-memory Fountain Store, routes a
user objective through the planner service, and enumerates the available
functions through the function caller service after passing gateway evaluation.

### Build & run

```bash
swift run --package-path Packages/FountainExamples hello-fountainai-teatro
```

The program prints the evaluated objective, the discovered function, and the
result of executing the generated plan.

### Tests

Integration coverage lives in the package’s test suite:

```bash
swift test --package-path Packages/FountainExamples
```

Running the tests exercises the same cross-package flow to ensure regressions in
any of the participating kits are caught during CI.

## LocalAgent integration hint

To mirror the LocalAgent integration guide, you can seed a demo
`schedule_meeting` function in the embedded store from your own example code:

```swift
let example = GatewayPlannerFunctionCallerExample()
try await example.seedScheduleMeetingFunction()
```

Pair this with the `openapi/personas/local-agent.md` persona and a running
LocalAgent service at `http://127.0.0.1:8080` to exercise function-calling.
