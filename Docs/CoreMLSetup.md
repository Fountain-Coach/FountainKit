Core ML Setup for LocalAgent

Goal
- Run LocalAgent with the Core ML backend and a compiled .mlmodelc.

Steps
- Prepare a Core ML model:
  - Convert an instruct model to Core ML (example: Apple’s “On‑Device Llama 3.1 with Core ML” pipeline).
  - Output should be a compiled bundle (.mlmodelc). Place it under:
    External/LocalAgent/AgentService/Models/coreml-model.mlmodelc

- Configure LocalAgent to use Core ML:
  - Configuration/local-agent.json → backend: coreml
  - LocalAgentManager writes AgentService/agent-config.json and starts the service with AGENT_CONFIG.
  - You can verify:
    curl http://127.0.0.1:8080/chat -H 'content-type: application/json' -d '{"model":"local-coreml","messages":[{"role":"user","content":"hello"}]}'

- Bring up the environment (Gateway optional):
  - Only LocalAgent and Planner are required for direct cli flows.
  - Start/stop LocalAgent via:
    swift run --package-path Packages/FountainApps local-agent-manager start --repo-root .
    swift run --package-path Packages/FountainApps local-agent-manager stop --repo-root .

Direct, no‑gateway CLI
- Chat to the local model:
  swift run --package-path Packages/FountainApps engraver-direct chat "Hello"
- Generate a plan directly from the Planner:
  swift run --package-path Packages/FountainApps engraver-direct plan "Book a meeting at 10am"

Notes
- CoreMLBackend confirms model availability and returns a diagnostic if the path is missing.
- Inference/tokenization wiring is scaffolded; use your converted model’s interface to implement token loops next.

