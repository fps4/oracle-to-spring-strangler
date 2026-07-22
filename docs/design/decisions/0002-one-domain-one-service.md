---
title: "ADR-0002 — One domain, one Spring service; scope is the product"
status: accepted
last_updated: 2026-07-22
owners: [architect]
---

# ADR-0002 — One domain, one Spring service

## Context

Portfolio repos die of scope. The temptation here is strong: more services,
Kafka everywhere, a second domain, Spring Cloud. The repo's audience hires for
migration judgment, not typing volume — and the owner's Spring hands-on claim
is deliberately calibrated at learning depth (ADR-0004), which a sprawling
codebase would silently overclaim.

## Decision

Exactly **one** fictional domain (wholesale orders & pricing) and **one**
Spring Boot service (`pricing-service`). No Spring Cloud (the router and K8s
provide platform concerns). No Kafka in core scope; a Debezium CDC path for
cutover data-sync is the *only* sanctioned stretch, gated to M3 and only after
all core milestones close. Total build effort target: ~4 weekends.

## Consequences

- The three-way logic placement (ADR-0003) lives in one navigable service —
  reviewable in one sitting.
- The restraint itself becomes an interview talking point ("what I chose not
  to build, and why").
- If the market later demands a Kafka-flavored variant, that belongs in a
  separate streaming-focused demo repo, not here.
