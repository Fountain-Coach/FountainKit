# ArcSpec Compiler (stub)

This SwiftPM executable will translate ArcSpec YAML files into OpenAPI documents
and invoke Apple’s Swift OpenAPI Generator as part of the studio pipeline.

Current status: placeholder CLI that prints usage. Implementation tasks:

- Parse ArcSpec schema (`docs/ArcSpec.md`).
- Emit OpenAPI (YAML/JSON) into `Packages/FountainSpecCuration/openapi/v*/`.
- Optionally shell out to `swift openapi generate …` for client generation.
- Wire into CI to ensure ArcSpec diffs regenerate specs.

Run (stub):

```bash
swift run --package-path Tools/ArcSpecCompiler arcspec-compiler path/to/spec.arc.yml
```
