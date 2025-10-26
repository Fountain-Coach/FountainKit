# AGENT — Planner Service

Planner turns objectives into tool steps. The spec sits at `Packages/FountainServiceKit-Planner/Sources/PlannerService/openapi.yaml`. Profiles constrain which tools are available, step shapes are deterministic, and unsafe operations are rejected up front. Prompts/configurations are versioned and testable.

Unit tests use golden fixtures for objective→steps mapping (AudioTalk tasks). Integration verifies that steps execute deterministically via FunctionCaller. End‑to‑end, the service plans a complete AudioTalk flow (parse → map → apply). CI builds and tests this package; new planner profiles must land alongside tests for their patterns.
