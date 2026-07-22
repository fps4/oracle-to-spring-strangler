---
title: "FS-0006 — Infra, CI & the walkthrough surface"
status: draft
last_updated: 2026-07-22
owners: [architect]
related:
  - docs/design/decisions/0001-local-first-runtime.md
  - docs/product/FS-0005-parity-harness.md
spec:
  feature: infra-and-ci
  kind: functional_spec
  summary: |
    Local-first runtime (compose default, kind profile for the K8s story), reviewable
    Terraform for EKS/RDS that plans cleanly but is never always-on, GitHub Actions CI
    (build + tests + parity), and the 15-minute interview walkthrough doc that strings the
    whole arc together. C4 diagrams document current and target state.
---

# FS-0006 — Infra, CI & walkthrough

- **Status:** draft
- **Raised:** 2026-07-22
- **Owner:** @farid (architect)
- **Milestone:** M2 (CI) → M3 (kind profile, Terraform, walkthrough)

## Why

The reviewer experience is the product: a cold reviewer must reach the "aha"
(flip a wave, run parity) in under 15 minutes with zero cloud spend (product
intent success criterion 1). The Terraform proves the EKS/RDS story without an
AWS bill; the walkthrough doc makes the repo interview-ready rather than
merely browsable.

## Scope

1. **Root `docker-compose.yml` + `Makefile`** — the default path:
   `make up` (Oracle XE + ORDS, PostgreSQL, pricing-service, nginx router),
   `make smoke`, `make parity`, `make down`. README badges the required
   resources (Oracle XE image is heavy — state the RAM/disk needs plainly).
2. **`infra/kind/`** — optional local-K8s profile: kind cluster manifest,
   Kustomize overlays deploying the target service with Actuator-wired
   liveness/readiness probes and graceful-shutdown preStop — the EKS story
   demonstrated without EKS.
3. **`infra/terraform/`** — modules for EKS + RDS PostgreSQL (+ VPC, IAM
   baseline), written to real standards (remote-state ready, tagged,
   variables documented). **Plan-only by policy** (ADR-0001): a committed,
   redacted `terraform plan` output under `infra/terraform/PLAN.md` is the
   evidence; `apply` is a documented manual act with a cost note.
4. **GitHub Actions** — `ci.yml`: build + `mvnw verify` (Testcontainers) +
   parity harness on PRs touching `services/`/`strangler/`; badge in README.
   Includes the deliberately-failing "parity caught this" exhibit PR
   (FS-0005), left open and labeled.
5. **`docs/walkthrough.md`** — the 15-minute guided demo script: assess →
   classify → wave 1 cutover diff → parity report → rollback exhibit →
   decommission story; with timestamps and the three architect talking points
   from the product intent inlined where they occur.
6. **C4 diagrams** (Mermaid, in `docs/design/`): context + container views of
   current (legacy), transition (strangler), and target states.

## Out of scope

- Always-on cloud environments, custom domains, TLS termination stories.
- Multi-environment promotion pipelines (dev/prod) — noted in the walkthrough
  as real-engagement scope, out of demo scope.
- AWS DMS *execution* (SCT conversion notes live in FS-0003; running DMS
  replication is an optional documented exercise, not CI).

## Acceptance criteria (EARS)

- ON a clean machine with Docker, `make up && make smoke` SHALL succeed with
  no cloud credentials and no accounts beyond GitHub.
- THE kind profile SHALL deploy the target service with working liveness and
  readiness probes backed by Actuator health groups.
- `terraform validate` and `terraform plan` SHALL succeed in CI against mocked
  credentials or plan-only mode; NO CI job SHALL run `apply`.
- THE walkthrough doc SHALL be executable as written in ≤ 15 minutes and
  SHALL reference only committed artifacts (no "imagine that...").
- THE README SHALL carry the CI badge and the honesty statement (ADR-0004)
  above the fold.

## Definition of done

- A colleague (or agent, cold context) follows `docs/walkthrough.md`
  end-to-end successfully and confirms the ≤ 15-minute budget.
- PLAN.md committed; CI green; exhibit PR open and labeled.
