# FountainServiceKit-SemanticBrowser

`SemanticBrowserService` wraps the Semantic Browser runtime that powers the `/v1` HTTP surface defined in [`openapi/v1/semantic-browser.yml`](../FountainSpecCuration/openapi/v1/semantic-browser.yml).

## Modules

* `SemanticBrowserService` – in-memory semantic memory service, Typesense backend integration, and the embeddable HTTP kernel used by the executable server.

## Usage

The service exposes the same APIs that the legacy `semantic-browser` SwiftPM package provided:

```swift
import SemanticBrowserService

let service = SemanticMemoryService()
let kernel = makeSemanticKernel(service: service)
```

Tests and sample code for the executable can be found under [`Packages/FountainApps/Sources/semantic-browser-server`](../FountainApps/Sources/semantic-browser-server).
