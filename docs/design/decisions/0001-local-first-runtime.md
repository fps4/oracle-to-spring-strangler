---
title: "ADR-0001 — Local-first runtime; cloud IaC is plan-only"
status: accepted
last_updated: 2026-07-22
owners: [architect]
---

# ADR-0001 — Local-first runtime; cloud IaC is plan-only

## Context

The repo must be reviewable by cold strangers (hiring managers, interviewers)
and cheap to keep alive indefinitely. An always-on EKS/RDS environment costs
real money, rots, and adds nothing a reviewer can't get locally. But the JDs
this repo targets name EKS/Aurora/Terraform explicitly, so the cloud story
must be *present and credible*.

## Decision

`docker compose up` is the canonical runtime and must always work end-to-end
on a clean machine with zero cloud credentials. The Kubernetes story is
demonstrated on a local kind profile (probes, graceful shutdown, Kustomize).
Terraform for EKS + RDS is written to production standards and verified to
`validate`/`plan` in CI — but **never applied automatically**; a committed,
redacted plan output is the evidence, and `apply` is a documented manual act
with a cost warning.

## Consequences

- Reviewers reach the demo in minutes; the repo has zero standing cost.
- The EKS claim is "IaC written and planned, deployed on demand" — honest and
  verifiable, aligned with ADR-0004.
- CI needs a plan-only Terraform job (mocked/offline providers where needed).
- Aurora-specific behavior is approximated by PostgreSQL 16 locally; the
  delta (connection scaling, failover) is documented, not simulated.
