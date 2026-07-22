---
title: "ADR-0003 — Three-way PL/SQL logic placement is the centerpiece"
status: accepted
last_updated: 2026-07-22
owners: [architect]
---

# ADR-0003 — Three-way PL/SQL logic placement

## Context

The defining architecture question in Oracle-estate migrations is where the
PL/SQL business logic lands. Real engagements answer it per workload; demo
repos usually pick one approach and silently pretend it generalizes.

## Decision

Each of the three legacy packages migrates by a *different*, deliberately
chosen lane, and the choice is documented at the module:

| Legacy module | Lane | Rationale (short form) |
|---|---|---|
| `PKG_PRICING` | **Extract → Java service** | Domain under active redesign; rules are branchy, unit-testable, framework-free in the target; best long-term home |
| `PKG_ORDERS` | **Translate → set-based SQL** (`JdbcTemplate`, `@Transactional`) | Logic is inherently set-based with transactional side effects; plain SQL is truer to original behavior than ORM entities |
| `PKG_STATEMENTS` | **Retain → converted PL/pgSQL** (SCT output, thin wrapper) | Highest parity risk / lowest change value; a transitional tier with an explicit burn-down noted in the wave plan |

The wave plan and walkthrough present this as the reusable decision framework:
extract where redesigning, translate where set-based, retain where parity risk
dominates — then burn down the retained tier.

## Consequences

- The repo demonstrates migration *judgment*, not a single technique.
- The retained tier must be honestly labeled transitional (not "best
  practice") — including its planned demolition.
- Parity tests (FS-0005) must cover all three lanes with equal rigor, since
  each fails differently.
