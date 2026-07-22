---
title: oracle-to-spring-strangler overview
status: draft
last_updated: 2026-07-22
owners: [architect]
related:
  - docs/README.md
  - docs/product/00-product-intent.md
  - docs/delivery/roadmap/README.md
---

# oracle-to-spring-strangler

A working legacy-modernization lab that demonstrates the full architect
journey in one repo: a deliberately authentic Oracle "legacy" system (XE +
PL/SQL packages + ORDS HTTP facade) is assessed with AI-assisted tooling,
classified into migration waves, and strangled endpoint-by-endpoint onto a
Spring Boot 3 / PostgreSQL target behind a routing layer — with a
golden-master parity harness as the exit gate for every wave. The centerpiece
architecture decision is the **three-way placement of PL/SQL business logic**
(extract to Java service / translate to plain SQL / retain converted PL/pgSQL
as a transitional tier), each path implemented and ADR-documented. Everything
runs locally with `docker compose up`; Terraform for EKS/RDS is present as
reviewable IaC, never always-on. The repo is itself built AI-assisted, and the
assessment artifacts commit their prompts — provenance is part of the product.
It exists as a portfolio asset for legacy-modernization architect roles
(Java/Spring target stacks), evidencing the *job* — assessment, sequencing,
parity, decommissioning — at honest, learning-depth Spring hands-on.

Start with the [product intent](product/00-product-intent.md) for the what &
why, the [ADRs](design/decisions/) for locked decisions, or the
[roadmap](delivery/roadmap/README.md) for milestones M0–M3.
