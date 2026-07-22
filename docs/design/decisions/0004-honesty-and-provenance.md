---
title: "ADR-0004 — Honesty rule: learning-depth claims, committed AI provenance"
status: accepted
last_updated: 2026-07-22
owners: [architect]
---

# ADR-0004 — Honesty rule & AI provenance

## Context

The repo exists to back interview claims. The owner's calibrated position is:
modernization architecture at senior depth, Spring Boot at governed-teams +
hands-on-learning depth, built AI-assisted. Any drift toward implying
production history, load-tested scale, or veteran Java fluency would convert
an asset into a liability the first time an interviewer probes.

## Decision

1. The README carries an explicit **honesty statement** above the fold:
   demonstration lab, learning depth, AI-assisted build, no production claims.
2. Nothing in code, docs, commit messages, or metrics may imply operational
   history, load testing, or scale that doesn't exist.
3. All AI-generated assessment artifacts commit their generating
   prompts/agents next to the outputs (provenance is a feature, FS-0002), and
   carry an architect-review footer separating agent-drafted from
   human-decided content.
4. Build effort is tracked and stated ("built AI-assisted in ~N days") — the
   meta-story is part of the pitch and must be accurate.

## Consequences

- Interview-safe under hostile probing; the repo's claims and the owner's
  spoken claims are the same claims.
- Some superficial "wow" is deliberately foregone (no fake scale numbers).
- Reviewers see an AI-assisted delivery method actually working — which is
  itself the strongest version of the "AI-assisted modernization" JD line.
