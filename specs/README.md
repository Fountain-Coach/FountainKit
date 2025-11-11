# FountainAI Agent Descriptor Package

This package contains the **FountainAI Interoperability Contract** and its **machine-readable companion**, ready for humans and tools alike.

---

## 📦 Contents

- `specs/AGENTS.md` — Human-readable specification describing how OpenAPI microservices and MIDI 2.0 instruments interoperate.
- `specs/schemas/agent-descriptor.schema.json` — Machine-readable validation schema for the `x-agent-*` metadata block used in every agent.

---

## 🧭 What This Is

- `AGENTS.md` is the **narrative standard** — what humans read and edit.
- `agent-descriptor.schema.json` is the **validator** — what tools or CI pipelines can use to check if an agent’s descriptor is valid.

They describe the same thing at two levels:
- **Markdown:** conceptual and descriptive
- **JSON Schema:** structural and verifiable

---

## 🛠️ How to Validate (Optional)

If you want to validate an agent descriptor file (e.g., `agents/spectralizer.yaml`), you can use:

Preferred: convert YAML → JSON, then validate with `ajv`.

Using `yq` + `npx ajv-cli` (no global installs):
```bash
yq -o=json agents/spectralizer.yaml | npx --yes ajv-cli validate -s specs/schemas/agent-descriptor.schema.json -d -
```

Alternatively, use the bundled Swift validator executable:
```bash
swift run --package-path Packages/FountainApps agent-validate agents/spectralizer.yaml
```

If validation passes quietly, the descriptor conforms. Otherwise, the error output will tell you what to fix.

---

## 🧍 How to Ignore It (Safely)

If you don’t plan to automate anything yet:
- Keep writing agent descriptors freely.
- Don’t run validators.
- Treat the JSON Schema simply as **helper documentation for future tooling**.

---

## 🗂️ Suggested Repo Layout

```
fountainai/
├── specs/
│   ├── AGENTS.md
│   └── schemas/
│       └── agent-descriptor.schema.json
└── agents/  # optional working staging area only (not canonical)
    ├── spectralizer.yaml
    ├── planner.yaml
    └── ...
```

---

## 🔖 References

- Semantic Versioning 2.0.0 — https://semver.org
- OpenAPI 3.1 Specification — https://spec.openapis.org/oas/v3.1.0
- MIDI 2.0 (CI & Property Exchange) — https://midi.org

---

## 🪶 Status

- Version: 1.0.0
- Status: Draft for internal use
- Maintainers: FountainAI Core Architecture Group
- Homepage: https://fountain.coach/specs/AGENTS.md
