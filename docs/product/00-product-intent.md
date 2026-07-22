---
title: "Product intent — oracle-to-spring-strangler"
status: draft
last_updated: 2026-07-22
owners: [architect]
related:
  - docs/overview.md
  - docs/delivery/roadmap/README.md
maestro:
  feature: product-intent
  kind: product_intent
  summary: |
    A portfolio lab proving legacy-modernization architecture end-to-end: authentic Oracle
    PL/SQL legacy, AI-assisted assessment with committed provenance, strangler-fig cutover in
    waves, three-way PL/SQL logic placement in a Spring Boot target, and golden-master parity
    gates. Audience: hiring managers and brokers for Java-target modernization architect roles.
---

# Product intent

## Who this is for

1. **Hiring managers / end clients** filling legacy-modernization architect
   roles with Java/Spring Boot target stacks (the recurring NL contract
   profile: Oracle APEX/PL-SQL or mainframe estate → AWS + Spring Boot,
   AI-assisted assessment named in the JD).
2. **Interviewers** in technical screens — the repo is a 15-minute guided
   walkthrough that answers "have you actually done this?" with running code.
3. **The owner** — the build itself is the upskilling vehicle that converts
   Spring Boot from design-review level to honestly-demoable
   (see wiki `upskilling-guides/spring-boot-for-architects.md` §8; this repo
   subsumes that exercise).

## The problem it solves

Every candidate for these roles claims modernization experience; almost none
can *show* the migration itself. Greenfield Spring demos prove stack
familiarity — a commodity. What the roles actually pay architect day-rates for
is assessment under ambiguity, wave sequencing, parity discipline, and orderly
decommissioning. No public repo the owner is aware of demonstrates that
end-to-end at reviewable size.

## What it is

One repo, one fictional domain (wholesale orders & pricing), five surfaces:

1. **An authentic legacy specimen** — Oracle XE, 3 PL/SQL packages with
   genuinely gnarly business logic, exposed over ORDS (the real HTTP shape of
   APEX-era estates). (FS-0001)
2. **AI-assisted assessment** — business-rule catalog, dependency map,
   per-module rehost/refactor/retain/retire classification, wave plan — with
   the generating prompts/agents committed. (FS-0002)
3. **The target** — one Spring Boot 3 service on PostgreSQL implementing the
   three-way PL/SQL logic placement, each path with its ADR. (FS-0003)
4. **The strangler** — a routing layer where a config change *is* a migration
   wave; per-endpoint cutover flags, rollback by revert. (FS-0004)
5. **The parity harness** — golden-master corpus replayed against both stacks;
   diff report; "parity green" as the wave exit criterion. (FS-0005)

Plus reviewable IaC and CI (FS-0006) — local-first, cloud-optional.

## What it is not

- Not a production system, and never claims to be (ADR-0004).
- Not a microservices showcase — one service, by decision (ADR-0002).
- Not a mainframe demo — the owner's authentic wedge is the Oracle side;
  COBOL cosplay would undermine the honesty positioning.
- Not a replacement for `event-driven-payments-platform` /
  `multi-cloud-api-gateway-pattern` (wiki `research/05-demo-repos.md`) — those
  evidence streaming/gateway depth; this evidences the modernization job.

## Success criteria

1. A cold reviewer can run `docker compose up`, hit the legacy endpoint, flip
   a wave flag, hit the same endpoint on Spring, and run `make parity` — in
   under 15 minutes on a clean machine.
2. The repo supports a 15-minute interview walkthrough with a narrative arc
   (assess → classify → wave 1 → parity → decommission) and at least three
   "architect-grade" talking points that are *in the code*, not just the docs
   (three-way logic placement; parity-as-exit-gate; self-invocation/transaction
   boundary handling).
3. The assessment artifacts demonstrably came from the committed
   prompts/agents (re-runnable), evidencing the AI-assisted-modernization JD
   line with receipts.
4. Total build effort stays inside ~4 weekends (scope guard: ADR-0002), with
   the AI-assisted build time tracked and stated in the README — the meta-story
   ("this lab was built agentically in X days") is itself a pitch for the
   assessment phase of a real engagement.
