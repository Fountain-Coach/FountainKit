# GatewayAPI

The Gateway API package exposes strongly-typed clients generated from the
Fountain gateway OpenAPI document. The `GatewayClient` wrapper builds on the
generated `GatewayAPI.Client`, wiring in the shared transports provided by
`ApiClientsCore` for both `URLSession` and `AsyncHTTPClient`.

## Usage

```swift
import GatewayAPI

let baseURL = URL(string: "http://gateway.local")!
let client = GatewayClient(baseURL: baseURL)

let healthPayload = try await client.health()
let metrics = try await client.metrics()
```

For Linux or other server deployments:

```swift
import AsyncHTTPClient

let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
let client = GatewayClient(
    baseURL: baseURL,
    httpClient: httpClient,
    defaultHeaders: ["Authorization": "Bearer TOKEN"]
)
```

## Migration Notes

- The legacy `GatewayClient` actor that implemented bespoke REST calls has been
  replaced with the generated `GatewayClient` wrapper. Consumers should switch
  to the new struct and adopt the typed responses (`OpenAPIObjectContainer`
  for `/health` and `[String: Int]` for `/metrics`).
- Default headers can be supplied through the initialiser; they are injected via
  `APIClientHelpers.DefaultHeadersMiddleware`.
- Additional gateway endpoints are available through the underlying generated
  `GatewayAPI.Client` instance should advanced scenarios require lower-level
  access.

