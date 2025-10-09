# Implementation Plan: Integrating Apple’s Swift OpenAPI Generator into FountainKit and the Fountain Coach Ecosystem

## Background and current architecture

FountainKit is a modular Swift Package Manager (SPM) workspace that decomposes the original FountainAI monolith into focused packages.  The root `AGENTS.md` describes the packages and establishes engineering conventions.  Key parts of the architecture include:

- **FountainCore** – runtime primitives, a store client and adapters.
- **FountainAPIClients** – generated OpenAPI clients and Tutor Dashboard models built on `FountainCore`.
- **FountainGatewayKit** – gateway persona orchestrator, security/budget plug‑ins and shared utilities.
- **FountainServiceKit‑<Service>** – libraries for planner, function‑caller, bootstrap, awareness, persistence, tools factory and tool server.
- **FountainTelemetryKit** – a streaming stack (MIDI‑2, `SSEOverMIDI`, `FlexBridge`) and diagnostics.
- **FountainTooling** – OpenAPI curator CLI/service, client generators and GUI tooling.
- **FountainApps** – executable entry points that stitch the kits together.
- **FountainSpecCuration** – OpenAPI specs, fixtures and regeneration scripts shared across packages.

`AGENTS.md` stresses several coding standards that are relevant for this effort: avoid duplicating shared types and move them into `FountainCore`; use dependency injection across package seams; and **treat OpenAPI documents as the authoritative description for every HTTP surface**, updating specs and regenerating clients before merging【84172849365932†L26-L34】.  These practices already align well with a spec‑driven development approach.

## Why adopt Apple’s Swift OpenAPI Generator

Apple’s Swift OpenAPI Generator is an SPM build‑tool plug‑in that consumes an OpenAPI document and generates Swift code for both clients and server stubs.  Key benefits include:

- **Build‑time generation and synchronicity** – the plugin generates code during the build so it is always in sync with the spec and the generated sources do *not* need to be committed【180031530885722†L22-L26】.
- **Support for OpenAPI 3.0/3.1 and streaming** – it works with OpenAPI 3.0/3.1 and supports streaming request/response bodies, enabling JSON event streams or large payloads【180031530885722†L30-L37】.
 - **Rich type support and decoupled transports** – it supports JSON, multipart, URL‑encoded form, base‑64 and raw bytes and represents them as type‑safe value types【180031530885722†L30-L36】.  The generated client and server code are decoupled from any specific HTTP library; different `ClientTransport` and `ServerTransport` implementations (URLSession, AsyncHTTPClient, **SwiftNIO‑based servers**, Lambda, etc.) can be plugged in【735777087227345†L228-L247】.  This decoupling is important because FountainKit intends to avoid heavyweight server frameworks like Vapor or Hummingbird and instead build directly on **SwiftNIO** to minimise third‑party dependencies.
- **Clear adoption steps** – to adopt the plugin you add dependencies on the generator, the runtime library and a transport implementation, enable the plugin for your target, and add two files: `openapi.yaml` (the spec) and `openapi‑generator‑config.yaml` (the configuration specifying whether to generate a client or server)【735777087227345†L108-L124】.
- **Configurable generation** – the configuration file can instruct the plugin to generate `types`, `client` and/or `server` code.  It can also filter the paths for which code is generated; for example a config may include:

  ```yaml
  generate:
    - client
    - types
  filter:
    paths:
      - /v1/computers-inventory
      - /v1/jamf-pro-version
  ```

  which directs the generator to emit only the specified operations and the corresponding model types【501983111765691†L176-L200】.  A third option `server` generates server stubs【501983111765691†L195-L197】.

These features make Apple’s generator a strong replacement for the bespoke OpenAPI curator and code‑generation scripts currently in `FountainTooling`.

## Implementation plan

### 1. Audit and curate OpenAPI documents

1. **Inventory existing specs** – review `FountainSpecCuration` and any other packages for existing OpenAPI specifications.  Ensure that every HTTP surface of the Fountain Coach ecosystem is captured in a spec.  Add missing specs for gateway endpoints, service APIs and telemetry streams.
2. **Normalize specs** – migrate all specs to OpenAPI 3.1 wherever possible for maximum feature support; verify they are valid with tools such as `spectral` or `openapi‑lint`.  Fill in missing `operationId` values and ensure consistent naming; missing operation IDs cause the generator to produce unreadable method names【501983111765691†L176-L200】.
3. **Adopt a single source of truth** – store each spec under `Packages/FountainSpecCuration/Specs/<ServiceName>/openapi.yaml` and reference it from client and server packages.  Document ownership of specs in AGENTS.md to avoid divergence.

### 2. Prepare `FountainCore` for plugin integration

- **Add dependencies** – in `Packages/FountainCore/Package.swift` add a package dependency on `swift‑openapi‑runtime`.  This runtime provides the protocol definitions used by generated clients and server stubs【735777087227345†L110-L124】.
 - **Provide transports** – create abstractions for `ClientTransport` and `ServerTransport` so higher‑level packages don’t import specific HTTP libraries.  For example, define a `FountainTransport` protocol that wraps a chosen client transport (such as `OpenAPIAsyncHTTPClient` or `OpenAPIURLSession` for clients) and a server transport implemented atop **SwiftNIO**.  Because Fountain Coach avoids Vapor and Hummingbird, this NIO‑based server transport will adopt `ServerTransport` from `swift‑openapi‑runtime` and connect to SwiftNIO’s HTTP server APIs.  Expose these transports through `FountainCore` so that service and gateway packages depend only on the abstractions.
- **Centralize common types** – if multiple services share schemas, define them as Swift structs in `FountainCore` rather than letting each generated `Components.Schemas` include its own copy.  You can then instruct the generator config to generate only clients/servers and reuse the shared models.

### 3. Integrate the plugin into package manifests

For each package that exposes or consumes an HTTP API, perform the following steps:

1. **Add plugin and runtime dependencies** – in the package manifest (`Package.swift`), add dependencies on:
   - `swift‑openapi‑generator` (for the build‑tool plug‑in).
   - `swift‑openapi‑runtime` (always required).
   - A chosen transport implementation.  For client packages use `swift‑openapi‑urlsession` (URLSession) or `swift‑openapi‑async‑http‑client`.  For server packages, avoid the framework‑specific transports provided by `swift‑openapi‑vapor` or `swift‑openapi‑hummingbird`; instead, implement and use a **SwiftNIO‑based** transport conforming to `ServerTransport`【735777087227345†L228-L247】.

2. **Enable the plugin on targets** – in each target’s declaration add:

   ```swift
   .target(
     name: "FountainServiceKitPlanner",
     dependencies: [
       "FountainCore",
       .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
       // Use AsyncHTTPClient for outbound client calls
       .product(name: "OpenAPIAsyncHTTPClient", package: "swift-openapi-async-http-client")
       // Add your own SwiftNIO-based server transport here (e.g., FountainNioServerTransport)
     ],
     plugins: [
       .plugin(name: "OpenAPIGeneratorPlugin", package: "swift-openapi-generator")
     ]
   ),
   ```

   For client packages choose an appropriate transport such as `OpenAPIAsyncHTTPClient` or `OpenAPIURLSession` and supply your chosen configuration.  For server packages, avoid depending on `swift‑openapi‑vapor` or `swift‑openapi‑hummingbird`; instead, implement a custom `ServerTransport` using SwiftNIO and add it as a dependency.

3. **Add spec and config files** – create `openapi.yaml` and `openapi‑generator‑config.yaml` in the target’s source directory.  The config should specify what to generate:

   - **Client packages (FountainAPIClients)**: set `generate: [types, client]` to generate model types and client code.  If the package should expose only a subset of operations, use the `filter.paths` property to list those endpoints【501983111765691†L176-L200】.
   - **Service packages (FountainServiceKit‑*) and `FountainGatewayKit`**: set `generate: [types, server]` to create server stubs and the associated model types.  If you generate middleware or additional helpers, include them as necessary.
   - **Gateway + aggregator packages**: when the gateway both consumes upstream services and exposes its own API, include two config files or two targets – one that generates `client` code for upstream calls and another that generates `server` code for the gateway’s public API.

4. **Implement handlers/clients** – for server targets, conform to the generated `APIProtocol` and implement each operation.  For client targets, wrap the generated `Client` in a higher‑level type that configures the base URL, transport and any middleware (authentication, logging).  The Jamf Pro example shows how to wrap the generated `Client` in a `JamfProAPIClient` struct to handle token injection【501983111765691†L176-L200】.

### 4. Refactor specific FountainKit packages

1. **FountainAPIClients** – remove existing manually generated clients.  For each upstream service, include its OpenAPI spec and config file to generate types and client code.  Provide wrappers that configure base URLs and inject authentication or other middleware.  Expose these wrappers through `FountainAPIClients` so other packages depend only on `FountainCore` and `FountainAPIClients`.

2. **FountainServiceKit‑<Service>** – for each service (planner, function‑caller, bootstrap, awareness, persist, tools factory, tool server), create or verify an OpenAPI spec describing its HTTP interface.  Add the plugin and runtime dependencies.  Generate types and server code.  Migrate existing handlers to conform to `APIProtocol` and register routes via the transport.  Move shared models into `FountainCore` if used across services.

3. **FountainGatewayKit** – treat the gateway as both an HTTP server and a client aggregator.  Use the plugin to generate server stubs for the gateway’s public API and client code for internal service calls.  Provide bridging functions to orchestrate calls and enforce security/budget plug‑ins.

4. **FountainTooling** – deprecate the bespoke OpenAPI curator CLI for code generation.  Instead, provide scripts or a CLI that validates specs, lints them, and runs `swift build` (which automatically triggers code generation via the plugin).  If a dedicated CLI is still needed (e.g., for spec curation), let it call the plugin’s CLI interface rather than separate templates.

5. **FountainSpecCuration** – reorganize specs into namespaced directories and ensure they are valid.  Provide sample fixtures for tests.  Add scripts to update specs from live systems when necessary.  This package becomes the canonical spec repository consumed by the plugin.

6. **FountainTelemetryKit** – streaming endpoints (e.g., MIDI/SSE) should be described in the OpenAPI spec using the new `stream` support.  Generate the server and client code and integrate with existing streaming implementations.

7. **FountainApps** – update executables to use the generated clients and server stubs rather than manually wiring HTTP calls.  Ensure they register handlers from service kits and compose transports.

### 5. Continuous integration and build tooling

- **Build scripts** – update build scripts and CI pipelines to run `swift build` at the top level, triggering the plugin.  Ensure the pipeline fails if any code cannot be generated.  Use `swift test --package‑path Packages/<Package>` to run unit tests for each touched package as described in AGENTS.md【84172849365932†L35-L39】.
- **Spec validation** – add a job that lints all `openapi.yaml` files and fails the build if they are invalid.  Optionally run the plugin’s CLI manually (`swift run OpenAPIGenerator`) to check generation outside of build.
- **Dependency updates** – track upstream updates to the plugin, runtime and transports.  Because the generated code isn’t committed, ensure that any breaking changes to the plugin do not silently break packages.

### 6. Developer workflow

1. **Add or change an API** – edit the appropriate OpenAPI document in `FountainSpecCuration`.  Write tests and examples alongside the spec.
2. **Update configuration** – modify the target’s `openapi‑generator‑config.yaml` to include new operations or to filter paths.
3. **Regenerate code** – run `swift build` in the package directory to regenerate code.  The generated `Client`, `APIProtocol`, `Operations` and `Components` types will update automatically【180031530885722†L22-L26】.
4. **Implement logic** – for servers, update the `APIProtocol` conforming type to handle the new operations.  For clients, adjust wrappers or business logic as needed.  Do **not** manually edit the generated files.
5. **Run tests** – ensure `swift test` passes for the touched packages.  Follow AGENTS.md guidance to avoid cross‑package `@testable import` and to maintain `Sendable` conformance【84172849365932†L26-L39】.
6. **Review and merge** – code reviewers should check that the spec, config file and implementation are consistent.  The review checklist should include verifying that the spec is updated and that the build passes with the generator enabled.

### 7. Migration and phasing

- **Phase 1 – Prototype in a single service** – pick a smaller service kit (e.g., `FountainServiceKit‑Planner`) and fully migrate it to use the plugin.  This involves writing a comprehensive spec, generating stubs and implementing handlers.  Use this as a template for other packages.
- **Phase 2 – Clients** – migrate `FountainAPIClients` to use generated clients for selected upstream services.  Provide wrappers and gradually replace old client code.
- **Phase 3 – Gateway and remaining services** – migrate the gateway and the remaining service kits.  Ensure cross‑service calls use generated clients, and export only the API surface defined in specs.
- **Phase 4 – Deprecate legacy tooling** – remove code‑generation scripts from `FountainTooling`.  Ensure all packages are on the plugin and update developer documentation.

## Updating the root `AGENTS.md`

`AGENTS.md` should be updated to reflect spec‑driven development and the use of Apple’s Swift OpenAPI Generator.  Proposed additions:

1. **Spec‑driven development** – emphasize that every HTTP surface must have an authoritative OpenAPI document.  When adding an endpoint, first update `openapi.yaml` in `FountainSpecCuration` and regenerate code before writing implementation.  Update the coding standards section to require spec updates and code regeneration prior to merging【84172849365932†L26-L34】.

2. **Plugin workflow** – document that the repository uses the `OpenAPIGeneratorPlugin`.  Explain that running `swift build` generates clients and server stubs at build time and that developers should never manually modify generated files【180031530885722†L22-L26】.

3. **Configuration files** – instruct developers to create or update `openapi‑generator‑config.yaml` for each target.  Explain the `generate` options (`types`, `client`, `server`) and the `filter` mechanism for limiting the scope of generated code【501983111765691†L176-L200】.

4. **Testing and review** – add to the review checklist: verify that OpenAPI specs are updated and valid; ensure that `openapi‑generator‑config.yaml` is present and correct; check that builds succeed with the plugin enabled; confirm that no generated code is manually edited; and ensure new operations are covered by tests.

5. **Package organization** – remind contributors not to duplicate shared types; instead, move common schemas into `FountainCore` and reference them.  Instruct them to maintain alphabetically sorted dependency declarations and to use dependency injection to keep packages decoupled【84172849365932†L26-L41】.

6. **Spec curation ownership** – assign responsibility for maintaining `FountainSpecCuration` and ensure that updates to specs are reviewed by the owning team.  Encourage automatic spec extraction from running services where possible.

## Conclusion

Adopting Apple’s Swift OpenAPI Generator will modernize the Fountain Coach codebase and fully realize the **spec‑driven development** principles already hinted at in `AGENTS.md`.  By curating accurate OpenAPI documents, generating clients and server stubs at build time and updating developer workflows, FountainKit and the broader Fountain Coach ecosystem will benefit from type‑safe networking, reduced boilerplate, consistent APIs and easier maintenance.  A phased approach starting with a single service kit and gradually expanding to all packages will minimize disruption and allow the team to refine best practices before organisation‑wide adoption.
