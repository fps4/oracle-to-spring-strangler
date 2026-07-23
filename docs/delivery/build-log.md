---
title: AI-assisted build log
status: draft
last_updated: 2026-07-22
owners: [architect]
---

# Build log (ADR-0004: the meta-story must be accurate)

Actual AI-assisted build effort per milestone. Wall-clock includes agent
runtime; "architect time" is human review/decision time only.

| Milestone | Date(s) | Method | Wall clock | Architect time | Notes |
|---|---|---|---|---|---|
| Specs & ADRs | 2026-07-22 | Claude Code session | — | — | committed before any code |
| M0 build | 2026-07-22/23 | Claude Code, 1 session; 5 assessment artifacts drafted by 5 subagents from committed prompts | ~1.5 h authoring + ~0.5 h verification | pending PR review | verified on remote amd64 Docker host (ds1): `make up && make smoke-legacy` 19/19 green; seed determinism proven by identical order checksums across two clean initializations; 3 first-boot fixes needed (SQL*Plus trailing-comment termination, PL/SQL declare order, local function in SQL) |
| M1 build | 2026-07-23 | Claude Code, 1 session (FS-0003 service + FS-0004 router authored inline) | ~1.5 h authoring + verification | pending PR review | `mvn verify` green in Maven-in-Docker (21 unit/slice + 15 Testcontainers tests; 1 assertion fix: PgJDBC returns smallint as Integer); local env quirk worked around (Docker 29 min-API vs docker-java, see memory note / api.version=1.44); full-stack smoke on ds1 via `stack-smoke` workflow -- result recorded on the PR |

Update this table when a milestone's verification completes — estimates or
rounded-up claims violate the honesty rule.
