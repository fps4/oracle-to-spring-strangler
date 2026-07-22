---
title: Roadmap — oracle-to-spring-strangler
status: draft
last_updated: 2026-07-22
owners: [architect]
---

# Roadmap

Four milestones ≈ four weekends (ADR-0002 scope guard). Each milestone ends
demoable — if building stops early, the repo still tells a coherent story.
Track actual AI-assisted build time per milestone (ADR-0004: the meta-story
must be accurate).

## M0 — The specimen & the assessment *(weekend 1)*

The legacy estate runs and has been professionally assessed.

- FS-0001: Oracle XE + schema + seed + 3 PL/SQL packages + ORDS, in compose.
- FS-0002: all five assessment artifacts + paired agent provenance.
- Repo hygiene: README (with honesty statement), AGENTS.md, CI skeleton.
- **Exit demo:** curl the four ORDS endpoints; walk the business-rule catalog
  pointing at the PL/SQL lines it was extracted from.

## M1 — The target & wave 1 *(weekend 2)*

The strangler takes its first bite.

- FS-0003: pricing-service — Flyway (SCT-converted schema + notes), the
  three-way logic placement implemented, tests green (`mvnw verify`).
- FS-0004: nginx router + `waves.yml`; **wave 1** (pricing/quote → target)
  cut over as a PR.
- **Exit demo:** same request through the router before/after the wave flip;
  `X-Served-By` flips from `legacy` to `target`; unit test pins the TRUNC
  quirk.

## M2 — Parity discipline & wave 2 *(weekend 3)*

Cutover becomes gated, not vibes-based.

- FS-0005: corpus, dual-run runner, tolerance contract, evidence reports;
  retro-evidence for wave 1, gated cutover for **wave 2** (orders → target).
- FS-0006 (part): full CI (build + verify + parity); failing-PR exhibit;
  executed rollback drill kept in history (FS-0004).
- **Exit demo:** `make parity` green; show the exhibit PR where parity caught
  a real deviation.

## M3 — The cloud story & the walkthrough *(weekend 4)*

Reviewer experience and the EKS/IaC evidence.

- FS-0006 (rest): kind profile with Actuator-wired probes; Terraform EKS/RDS
  modules + committed PLAN.md; C4 diagrams; `docs/walkthrough.md` timed
  ≤ 15 min.
- Decommission story: `waves.yml` marks legacy pricing/orders endpoints
  retired; walkthrough closes the arc (assess → … → decommission).
- **Stretch (only if M0–M3 closed):** Debezium CDC Oracle→PostgreSQL data-sync
  path for zero-downtime cutover narrative (sanctioned by ADR-0002).

## Non-goals ledger

Second domain/service · Kafka in core · Spring Cloud · always-on cloud ·
mainframe stubs · load testing. See ADR-0002 / ADR-0004 before reopening any
of these.
