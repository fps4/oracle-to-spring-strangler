# oracle-to-spring-strangler

A **working legacy-modernization lab**: an Oracle PL/SQL "legacy" system migrated
live to Spring Boot on Kubernetes/PostgreSQL by the **strangler fig pattern** —
with AI-assisted assessment artifacts, per-endpoint cutover waves, and
behavioral-parity gates as wave exit criteria.

This repo demonstrates the *job* of a modernization architect, not just a stack:

```
legacy (Oracle XE + PL/SQL + ORDS)
  → AI-assisted assessment (business-rule catalog, dependency map, classification)
  → migration waves (strangler routing per endpoint)
  → Spring Boot service on K8s + PostgreSQL (Flyway, Testcontainers, OAuth2)
  → behavioral parity gates (golden-master dual-run diff)
  → decommission
```

## Honesty statement

This is a **demonstration lab built at learning depth**, authored AI-assisted
(agentic workflow; prompts and agent definitions are committed under
`assessment/`). It is not a production system and makes no production claims —
see ADR-0004. The architecture decisions, migration sequencing, and parity
discipline are the portfolio artifact; the Spring code is deliberately one
small, honest service.

## Start here

- [`docs/overview.md`](docs/overview.md) — what this is, in six sentences
- [`docs/README.md`](docs/README.md) — full docs index (specs, ADRs, roadmap)
- [`AGENTS.md`](AGENTS.md) — how agents work in this repo

## Runtime

Local-first (ADR-0001): `docker compose up` brings up Oracle XE + ORDS, the
strangler proxy, the Spring service, and PostgreSQL. Terraform for EKS/RDS
exists as reviewable IaC (`infra/`), applied only on demand — no always-on
cloud cost.

**Resource note:** the Oracle XE image is heavy — budget ~3 GB image pull,
~2.5 GB RAM for the container, several minutes on first boot. The image is
amd64-only; on Apple Silicon use Docker Desktop's Rosetta emulation or a
remote amd64 `DOCKER_HOST`.

```bash
make up            # full stack: oracle + ords + postgres + pricing-service + router
make smoke         # legacy anchors (19 checks) + target/router checks (M1)
make verify        # pricing-service test suite (Java 21 + Docker for Testcontainers)
make clean         # wipe volumes; next `make up` re-seeds deterministically
```

One public port: consumers call `http://localhost:8080/api/...` and the
nginx router answers from whichever stack [`strangler/waves.yml`](strangler/waves.yml)
routes to — the `X-Served-By: legacy|target` header says which. A migration
wave is a PR that edits `waves.yml`; rollback is a git revert (FS-0004).
Direct debug ports: ORDS `8081`, pricing-service `8082`.

## Status

**M1 in progress** — M0 (legacy estate FS-0001, assessment FS-0002) merged;
M1 adds the target service (FS-0003: three-way PL/SQL placement, Flyway,
Testcontainers) and the strangler router (FS-0004), with wave 1
(`pricing/quote` → target) cut over as its own PR. M2–M3 (parity harness,
infra) are spec-only. See [`docs/delivery/roadmap/README.md`](docs/delivery/roadmap/README.md).

## License

MIT
