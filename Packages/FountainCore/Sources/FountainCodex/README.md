FountainRuntime (formerly imported as FountainCodex)

Purpose
- Shared service/runtime library used by Gateway and microservices.
- Provides a small HTTP runtime abstraction (HTTPKernel), a NIO-based HTTP server, and request/response types for tests and apps.
- Includes OpenAPI tooling (load/validate spec, generate models/clients/servers) for contract-first development.
- Bundles lightweight DNS utilities (ZoneManager, DNSServer) used by the Gateway integration tests.

Recommended Import
- Prefer `import FountainRuntime` for new code.
- Legacy code may continue to use `import FountainCodex` during a transition period.

Suggested Future Split (optional)
- `FountainHTTP`: HTTPKernel/NIOHTTPServer/client abstractions
- `FountainOpenAPI`: spec loader/validator/generators
- `FountainDNS`: DNS helpers for tests

