---
title: "FS-0005 — Behavioral-parity harness (golden master, dual-run)"
status: draft
last_updated: 2026-07-22
owners: [architect]
related:
  - docs/product/FS-0001-legacy-estate.md
  - docs/product/FS-0003-target-service.md
  - docs/product/FS-0004-strangler-routing.md
spec:
  feature: parity-harness
  kind: functional_spec
  summary: |
    The wave exit gate: a recorded golden-master corpus replayed against both stacks
    (dual-run), a diff engine with an explicit tolerance contract (what may differ, what may
    never), and a human-readable report. Parity green is the only ticket to cutover; the
    harness runs in CI on every PR touching target code.
---

# FS-0005 — Behavioral-parity harness

- **Status:** draft
- **Raised:** 2026-07-22
- **Owner:** @farid (architect)
- **Milestone:** M2

## Why

Equivalence testing is the JD line candidates hand-wave hardest
("we tested thoroughly"). A runnable harness with an explicit tolerance
contract — *this may differ, this may never* — is the difference between
claiming parity discipline and demonstrating it. It also protects the frozen
legacy specimen (FS-0001) against accidental behavior drift in the target.

## Scope

1. **Corpus** — `parity/corpus/*.jsonl`: recorded request sets per endpoint,
   generated deterministically against the seeded legacy stack (fixed seed →
   reproducible corpus). Includes the edge cases the assessment catalogued:
   TRUNC half-cent rounding inputs, credit-limit boundary orders,
   insufficient-stock orders, empty statement periods.
2. **Dual-run runner** — a small Node.js CLI (`parity/runner`): replays the
   corpus against the legacy (ORDS) and target (Spring) endpoints directly
   (bypassing the router), captures responses *and* relevant DB side-state
   (stock deltas, audit rows) via per-case reset + snapshot queries.
3. **Tolerance contract** — `parity/contract.md`, the explicit rules:
   - MAY differ: field ordering, whitespace, timestamp values, generated IDs
     (compared structurally), HTTP header sets.
   - MUST match: business values (prices, totals, statuses), error *class*
     mapping (named PL/SQL exception ↔ RFC 7807 problem type table),
     side-effect state (stock, audit, order rows after each case).
4. **Report** — `make parity` emits a markdown + JSON report per run:
   pass/fail per case, diff detail on failure; reports for gated waves are
   committed under `parity/evidence/wave-N/`.
5. **CI integration** — GitHub Actions job running the full harness on every
   PR that touches `services/` or `strangler/`; a deliberately-failing PR
   left open as the "parity caught this" exhibit (FS-0006).

## Out of scope

- Live shadow-traffic mirroring at the router (the runner *is* the dual-run;
  keeping it out of the request path keeps the demo honest and simple).
- Performance comparison between stacks (ADR-0004 territory).
- Fuzzing / property-based generation (corpus is curated from the assessment;
  noted as a real-engagement extension).

## Acceptance criteria (EARS)

- THE corpus SHALL be reproducible from the seeded legacy stack and SHALL
  include every edge case flagged in the business-rule catalog (FS-0002),
  including the TRUNC rounding inputs.
- THE runner SHALL compare responses under the tolerance contract and SHALL
  additionally compare side-effect state for mutating endpoints.
- WHEN any MUST-match rule fails, `make parity` SHALL exit non-zero and the
  report SHALL show the exact diff.
- EACH wave cutover (FS-0004) SHALL reference a committed evidence report
  produced by this harness against the exact commit being cut over.
- THE harness SHALL run in CI on every PR touching `services/` or
  `strangler/`.

## Definition of done

- `make parity` green for waves 1–2 evidence; evidence committed.
- `contract.md` reviewed: every MAY/MUST rule has a one-line rationale.
- The failing-PR exhibit exists and is linked from the walkthrough doc.
