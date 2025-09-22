# Publishing Frontend

`publishing-frontend` is a lightweight CLI that boots the static asset host used by the Gateway publishing plugin. It loads configuration from `PublishingFrontend` (in `FountainGatewayKit`) and serves HTML/JS bundles referenced by the Gateway UI routes.

## API surface

This executable does not expose its own REST API beyond the assets rendered by the Gateway. All HTTP contracts for publishing interactions are described by the Gateway specification at [`Packages/FountainSpecCuration/openapi/v1/gateway.yml`](../../../FountainSpecCuration/openapi/v1/gateway.yml).

## Usage

```bash
swift run --package-path Packages/FountainApps publishing-frontend
```

Use `--help` or `--version` for CLI flags. Configuration is resolved from the standard `PublishingFrontend` configuration files and environment variables.
