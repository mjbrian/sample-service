# sample-service

A small Go HTTP service and its Helm chart. It is the app every platform feature gets tested against.

See [platform-bootstrap](https://github.com/mjbrian/platform-bootstrap) for how this repo fits with the others.

## What lives here

| Path | Purpose |
| --- | --- |
| `cmd/server/` | Entry point, migrations, tracing setup |
| `internal/` | HTTP handlers and storage |
| `charts/sample-service/` | The Helm chart, with tests and a values schema |
| `Dockerfile` | Multi stage build to a distroless image |

## Endpoints

`/healthz` for liveness, `/readyz` for readiness, `/metrics` for Prometheus, and `/api/hello` and `/api/greetings` for the app.

## How changes ship

Merging to `main` runs the shared pipeline from `platform-tools`. It tests, builds a signed multi arch image, publishes the chart when its version changes, and opens a promotion pull request on `platform-gitops`.

This repo never decides where or which version runs. That lives in `platform-gitops`.

## Local commands

`task test`, `task lint`, `task build`, and `task run`.
