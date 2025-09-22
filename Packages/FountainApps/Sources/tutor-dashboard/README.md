# Tutor Dashboard CLI

The Tutor Dashboard is a terminal UI that discovers Fountain services from their OpenAPI documents and polls each instance for health information. It ships as part of `FountainApps` so operators can inspect a local deployment from the command line.

## OpenAPI discovery

By default the dashboard scans [`Packages/FountainSpecCuration/openapi/v1`](../../../FountainSpecCuration/openapi/v1) for specs. Each service document declares discovery metadata (`x-fountain`) that drives the dashboard rows and health checks. Override the location with `--openapi-root <path>` or the `TUTOR_DASHBOARD_OPENAPI_ROOT` environment variable.

## Environment and refresh configuration

Set `TUTOR_DASHBOARD_ENV` to point at a `.env` file with service credentials. Refresh cadence can be tuned with `--refresh-interval` or `TUTOR_DASHBOARD_REFRESH_SECONDS`.

## Running

```bash
swift run --package-path Packages/FountainApps tutor-dashboard
```

Use `--help` to see available flags. The dashboard exits cleanly with `q` and refreshes on demand with `r`.
