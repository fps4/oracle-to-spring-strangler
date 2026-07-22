---
title: "ADR-0005 — ORDS as the legacy facade; nginx as the strangler router"
status: accepted
last_updated: 2026-07-22
owners: [architect]
---

# ADR-0005 — ORDS facade & nginx router

## Context

Two edge choices shape the demo's authenticity. (1) The legacy system needs an
HTTP surface without building an APEX UI (no reviewable value on GitHub).
(2) The strangler needs a routing layer, and the obvious Java-flavored choice
(Spring Cloud Gateway) would put target-stack technology in the migration
plumbing — and imply Spring Cloud operational claims ADR-0004 discourages.

## Decision

- **ORDS (Oracle REST Data Services)** exposes the PL/SQL packages as REST.
  This is the genuine HTTP shape of APEX-era estates (APEX itself runs on
  ORDS), so the specimen stays authentic while remaining reviewable via curl.
- **nginx** is the strangler router: stack-neutral, boring, config-generated
  from `waves.yml` (FS-0004). In a real estate this role is played by the
  incumbent gateway/LB — the demo mirrors that reality rather than smuggling
  the target framework into the transition layer. The router stays dumb by
  design; policy/auth would sit here in a real estate and is explicitly noted
  as out of demo scope.

## Consequences

- The legacy side needs an ORDS container and endpoint definitions (FS-0001)
  — modest extra setup, high authenticity payoff.
- Router behavior is testable as pure config generation; rollback is a git
  revert.
- No Spring Cloud anywhere — consistent with ADR-0002 and the owner's
  "minimize Spring Cloud on K8s" architectural stance.
