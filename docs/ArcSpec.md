# ArcSpec Authoring Guide

ArcSpecs capture emerging corpus patterns (“arcs”) before they become
fully-fledged tools. Each spec is a concise, human-written contract that
defines which resources, operators, and guarantees the LLM should expose
through FountainKit.

This document describes the ArcSpec YAML schema, authoring conventions, and
tooling expectations that feed the ArcSpec → OpenAPI → Swift pipeline.

---

## File Location

- Place ArcSpec documents under `Packages/FountainSpecCuration/arcspec/`.
- Use the naming pattern `<corpus>/<arc-name>.arc.yml` (e.g.
  `polyglot/echo-lattice.arc.yml`).
- Version each spec with a `version` field; create new files when breaking
  changes are required.

## YAML Schema

```yaml
arc: "Polyglot Hamlet – Echo Lattice"
version: 0.1
corpus:
  id: polyglot-hamlet
  refs:
    - type: git
      url: https://github.com/Fountain-Coach/the-four-stars
resources:
  - id: corpus
    kind: text.corpus
    facets: [work, translation, stanza, meter, timestamp]
operators:
  - id: echo.align
    intent: "Align semantically equivalent lines across languages."
    input:
      - {name: passages, type: PassageRef[], required: true}
      - {name: languages, type: LangCode[], required: true}
    output:
      type: EchoLattice
      guarantees:
        - stable ids
        - time-anchored
        - lossless mapping
  - id: echo.condense
    intent: "Compress an echo lattice into a minimal motif set."
    input:
      - {name: lattice, type: EchoLattice, required: true}
      - {name: target_cardinality, type: Int, default: 32}
    output:
      type: MotifSet
policies:
  execution:
    network: deny
    cpu_seconds: 30
    memory_mb: 512
  artifacts:
    base_path: /data/corpora/polyglot-hamlet/studios
```

### Top-Level Fields

| Field | Description | Required |
| --- | --- | --- |
| `arc` | Human-readable name of the phenomenon. | ✅ |
| `version` | SemVer-like, incremented on schema changes. | ✅ |
| `corpus` | Source corpus metadata (id + references). | ✅ |
| `resources` | Inputs the operators may use (typed by domain). | ✅ |
| `operators` | Declarative operator contracts; drives OpenAPI generation. | ✅ |
| `policies` | Optional execution & artifact policies (defaults set by registry). | ⚪️ |

#### Resources

Each resource entry describes the semantic dataset operators may touch. The
`kind` field should map to a taxonomy understood by the ArcSpec compiler
(e.g., `text.corpus`, `audio.stem`, `graph.motif`). `facets` provide inline
dimensions the compiler can expose as filter parameters.

#### Operators

An operator is the heart of the spec:

- `id` becomes the canonical operation name. Use reverse DNS style
  if necessary to avoid collisions (`echo.align`, `rhythm.transpose`).
- `intent` is a short, user-facing description surfaced in generated docs.
- `input` declares a list of arguments:
  - `type` is a logical schema name; the compiler will map to OpenAPI/Swift
    types via a registry.
  - `default` values are optional and must respect Swift literal syntax.
- `output` declares the return schema and any guarantees (e.g., stability,
  determinism).

#### Policies

Policies let authors override default execution settings for studios that draw
on this ArcSpec. Most specs can omit policies; when present, they should mirror
the fields supported by the sandbox runner (network mode, CPU/memory quotas,
artifact path prefixes).

## Authoring Checklist

1. **Seed the corpus**  
   Ensure the source corpus is imported into FountainStore (e.g. seed
   `the-four-stars` into the `polyglot-hamlet` corpus) so operators have
   real data.

2. **Capture the core arc**  
   Distill the phenomenon into a short phrase and intent statements.

3. **List operators**  
   Limit each spec to a cohesive operator set. Split into multiple ArcSpecs if
   the operators target different corpora or workflows.

4. **Validate types**  
   Check that the `type` strings correspond to known schema definitions in
   FountainCore or the ArcSpec type registry. Propose new schemas if needed.

5. **Run the compiler** *(placeholder)*  
   Once the ArcSpec compiler is available, run:

   ```bash
   swift run arcspec-compiler path/to/spec.arc.yml --out openapi/v1
   ```

   The generated OpenAPI specs must pass `openapi/lint-matrix.sh`.

6. **Review policies**  
   Confirm execution limits and artifact paths are appropriate for the corpus.

## Tooling Status

- ✅ ArcSpec schema defined (this document).
- ⬜️ ArcSpec compiler (`arcspec-compiler`) – TBD.
- ⬜️ Corpus seeding pipeline for `the-four-stars`.
- ⬜️ Studio templates and registry entries.

## References

- Concept: *FountainKit Concept Paper – Swift as the LLM Superpower*
- Concept: *PRESETS – From Imagination to Interface*
- Implementation Plan: `openapi/arcspec_studio_plan.md`

---

**Maintainers:** update this document as the ArcSpec compiler evolves or new
schema conventions are introduced.
