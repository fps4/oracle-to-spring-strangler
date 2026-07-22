---
title: oracle-to-spring-strangler documentation index
status: draft
last_updated: 2026-07-22
owners: [architect]
---

# oracle-to-spring-strangler docs

This repo is **spec-driven**: product intent precedes design precedes code.
Agents build against these documents (see [`../AGENTS.md`](../AGENTS.md)).

## Start here

- [`overview.md`](./overview.md) — what this is, in six sentences
- [`../README.md`](../README.md) — repo orientation for humans
- [`../AGENTS.md`](../AGENTS.md) — agent operating rules and target layout

## Product — what we're building and why

| Spec | Title | Milestone |
|---|---|---|
| [00](./product/00-product-intent.md) | Product intent | — |
| [FS-0001](./product/FS-0001-legacy-estate.md) | Legacy estate: Oracle XE + PL/SQL + ORDS | M0 |
| [FS-0002](./product/FS-0002-ai-assisted-assessment.md) | AI-assisted assessment with provenance | M0 |
| [FS-0003](./product/FS-0003-target-service.md) | Target service: Spring Boot 3, three-way logic placement | M1 |
| [FS-0004](./product/FS-0004-strangler-routing.md) | Strangler routing & migration waves | M1 → M2 |
| [FS-0005](./product/FS-0005-parity-harness.md) | Behavioral-parity harness | M2 |
| [FS-0006](./product/FS-0006-infra-and-ci.md) | Infra, CI & walkthrough | M2 → M3 |

## Design — locked decisions

| ADR | Decision |
|---|---|
| [0001](./design/decisions/0001-local-first-runtime.md) | Local-first runtime; cloud IaC plan-only |
| [0002](./design/decisions/0002-one-domain-one-service.md) | One domain, one Spring service — scope is the product |
| [0003](./design/decisions/0003-three-way-plsql-placement.md) | Three-way PL/SQL logic placement is the centerpiece |
| [0004](./design/decisions/0004-honesty-and-provenance.md) | Honesty rule: learning-depth claims, committed AI provenance |
| [0005](./design/decisions/0005-ords-facade-and-nginx-router.md) | ORDS legacy facade; nginx strangler router |

C4 diagrams land under `design/` in M3 (FS-0006).

## Delivery

- [`delivery/roadmap/README.md`](./delivery/roadmap/README.md) — milestones
  M0–M3, one weekend each, exit demos per milestone.

## Positioning

This repo covers the *modernization* story (assess → waves → parity →
decommission). Streaming and API-platform depth are separate demo tracks —
deliberately not mixed in here (ADR-0002).
