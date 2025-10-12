# ArcSpec Directory

Place authored ArcSpec YAML files here using the pattern:

```
<corpus>/<arc-name>.arc.yml
```

Example (when seeding `the-four-stars` corpus):

```
Packages/FountainSpecCuration/arcspec/polyglot/echo-lattice.arc.yml
```

Each file must conform to the schema described in `docs/ArcSpec.md`. Specs
added here feed the ArcSpec compiler, which will emit OpenAPI definitions into
`openapi/v*/`.

## Repository Rules

- Organise specs by corpus; create subdirectories as needed.
- Do not commit generated OpenAPI output from the compiler—only the authored
  `.arc.yml` sources.
- When adding a new spec, run the compiler and the relevant lint suite before
  submitting (see `openapi/arcspec_studio_plan.md`).

Use `.arc.yml` extension so the compiler and tooling can discover specs
unambiguously.
