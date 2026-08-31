# Contributing

This repository carries the Docker Compose quickstart for Herder
Community Edition, not the product itself. Contributions that improve
the quickstart are welcome: compose fixes, clearer documentation,
portability fixes for other container runtimes. Product features and
bug reports about Herder itself are also welcome as issues; the
product is not developed in this repository.

## Testing a change

```
docker compose config -q
docker compose up -d
```

A change to the compose files or environment defaults should bring a
stack up cleanly on a machine with nothing but Docker installed. A
broken quickstart is a defect.

## Conventions

- Commits and PR titles: `type(area): imperative summary`, for example
  `fix(compose): clickhouse healthcheck waits for the native port`.
- One change per PR. PRs are squash merged.
