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

Update this table when a milestone's verification completes — estimates or
rounded-up claims violate the honesty rule.
