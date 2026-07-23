---
title: "FS-0004 — Strangler routing & migration waves"
status: draft
last_updated: 2026-07-22
owners: [architect]
related:
  - docs/product/FS-0002-ai-assisted-assessment.md
  - docs/product/FS-0003-target-service.md
  - docs/design/decisions/0005-ords-facade-and-nginx-router.md
spec:
  feature: strangler-routing
  kind: functional_spec
  summary: |
    The strangler fig made tangible: an nginx routing layer in front of both stacks where a
    per-endpoint wave file is the single source of cutover truth — a config change (PR) is a
    migration wave, a git revert is the rollback. Wave state is visible at a glance and each
    wave's history pairs with its parity evidence.
---

# FS-0004 — Strangler routing & migration waves

- **Status:** draft
- **Raised:** 2026-07-22
- **Owner:** @farid (architect)
- **Milestone:** M1 (wave 1) → M2 (wave 2)

## Why

"Strangler fig" is on every modernization slide; almost nobody shows the
routing mechanics, the wave as a reviewable change, or rollback as a revert.
Making the cutover a one-line config diff is the most persuasive 30 seconds of
the interview walkthrough.

## Scope

1. **`strangler/waves.yml`** — the single source of cutover truth: each
   routed endpoint mapped to `legacy` or `target`, grouped into named waves
   with a status (`planned` / `cut-over` / `rolled-back`) and a link to the
   parity evidence that gated it.
2. **nginx router** (see ADR-0005 for why not Spring Cloud Gateway) fronting
   both stacks on one port; its route config **generated** from `waves.yml`
   by a small script — no hand-edited duplication.
3. **Unified API surface**: consumers call `http://localhost:8080/api/...`;
   whether ORDS or Spring answers is invisible except for an
   `X-Served-By: legacy|target` debug header (demo affordance).
4. **Wave 1** (M1): `pricing/quote` → target. **Wave 2** (M2): `orders`
   **and `orders/{id}`** → target (the read flips with the write:
   read-after-write coherence — see amendment note below).
   `statements/run` remains on the retained-PL/pgSQL path via the
   target service (its "cutover" is the wrapper, per ADR-0003).
5. **Rollback drill**: one documented, executed rollback (wave flipped back,
   header proves it, commit history shows revert) — kept in the history as an
   exhibit, referenced from the walkthrough doc.

## Out of scope

- Percentage-based canary or shadow traffic at the router (dual-run
  comparison lives in the parity harness, FS-0005 — keeping the router dumb
  is the point).
- AuthN/Z at the router (demo scope; noted as where gateway policy would sit
  in a real estate).

## Acceptance criteria (EARS)

- THE routing behavior SHALL be fully determined by `waves.yml`; regenerating
  the router config from an unchanged `waves.yml` SHALL be a no-op.
- WHEN a wave entry flips between `legacy` and `target`, THE change SHALL
  require only editing `waves.yml` and reloading the router.
- EVERY response through the router SHALL carry `X-Served-By` identifying the
  answering stack.
- EACH wave marked `cut-over` in `waves.yml` SHALL link to parity evidence
  (FS-0005 report) produced before the cutover.
- THE repo history SHALL contain at least one executed rollback (revert of a
  wave) with its narrative in the walkthrough doc.

## Definition of done

- Wave 1 and wave 2 cut over as PRs whose diff is essentially the `waves.yml`
  change + parity evidence link.
- The rollback exhibit exists and is referenced from the walkthrough.

## Amendments

- **2026-07-23 (M1 build): four routed endpoints, not three.** The
  original scope listed three endpoints; the dependency map documents a
  fourth, `GET /orders/{id}` ([E23], [E24]), which the wave plan flagged
  ("it must be routed by `waves.yml` like everything else or it silently
  pins ORDS alive forever") and the M0 architect review endorsed. Scope
  item 4 now flips it with wave 2 alongside `POST /orders` — same
  tables, read-after-write coherence. Mechanically both live under one
  `/api/orders` prefix route in `waves.yml`.
