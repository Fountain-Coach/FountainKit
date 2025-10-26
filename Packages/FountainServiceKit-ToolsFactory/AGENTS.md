# AGENT — ToolsFactory Service

ToolsFactory catalogs and registers tools. Spec: `Packages/FountainServiceKit-ToolsFactory/Sources/ToolsFactoryService/openapi.yaml`. Tool lists are corpus‑scoped; registration is idempotent; list formats are stable.

Unit tests cover registration normalization and corpus filtering. Integration registers the AudioTalk spec and asserts the list contains expected entries. CI builds and tests this package; Studio autostart registers AudioTalk tools during dev.
