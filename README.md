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
make up            # oracle + ords (+ target stack from M1)
make smoke-legacy  # verify the four legacy endpoints, incl. the TRUNC quirk
make clean         # wipe volumes; next `make up` re-seeds deterministically
```

## Status

**M0 in progress** — legacy estate (FS-0001) and AI-assisted assessment
(FS-0002) built; M1–M3 (target service, strangler waves, parity, infra) are
spec-only. See [`docs/delivery/roadmap/README.md`](docs/delivery/roadmap/README.md)
for milestones M0–M3.

## License

MIT
