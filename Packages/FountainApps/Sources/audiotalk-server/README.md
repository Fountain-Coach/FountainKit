# AudioTalk Server

A minimal NIO-based server that hosts the AudioTalk OpenAPI using generated handlers.

- Binary: `audiotalk-server`
- Port: `AUDIOTALK_PORT` (default `8080`), or `PORT` fallback
- Spec: `GET /openapi.yaml`
- Health: `GET /audiotalk/meta/health`

## Run

```
swift run --package-path Packages/FountainApps audiotalk-server
```

Use the companion CLI for quick interactions:

```
swift run --package-path Packages/FountainApps audiotalk-cli --help
```

