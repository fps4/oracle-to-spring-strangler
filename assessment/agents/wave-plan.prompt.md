# Generator prompt — wave-plan.md

Paired output: `assessment/wave-plan.md`
Run with: any agentic coding assistant. Pipeline note: this prompt runs
AFTER the catalog, dependency map and classification exist — it reads them.

---

You are the assessment phase of an Oracle-to-Spring modernization. Read:

- `assessment/business-rule-catalog.md`
- `assessment/dependency-map.md`
- `assessment/classification.md`
- `docs/product/FS-0004-strangler-routing.md` (the wave mechanics)
- `docs/product/FS-0005-parity-harness.md` (the gate mechanics)

Produce `assessment/wave-plan.md`: the migration wave plan for strangling
the three legacy endpoints onto the Spring target.

Requirements:

- **Wave table**: wave number, endpoints in the wave, target lane (from the
  classification), explicit dependency prerequisites (from the dependency
  map), and status (all `planned` at authoring time).
- **Per wave**: an **exit criterion expressed as a parity gate** — which
  corpus cases must pass (reference the specific catalogued rules/quirks the
  gate protects, by BR id) — and a **rollback statement** (what reverting the
  wave means mechanically, per FS-0004).
- Wave 1 MUST be the pricing quote endpoint (read-only, no side effects,
  lowest blast radius) — justify from the dependency map, and reconcile with
  the fact that PKG_ORDERS calls PKG_PRICING (what stays duplicated during
  the transition window, and why that is acceptable).
- Cover the retained-PL/pgSQL tier: its "cutover" wave (the wrapper), and a
  **burn-down note** for eventually demolishing it (ADR-0003 requires the
  transitional tier to have a stated end).
- End with a **decommission wave**: what marks legacy endpoints retired and
  what evidence must exist first.

Keep it consistent with the three input artifacts — if you find a
contradiction between them, flag it in-line rather than papering over it.
End the file with an `## Architect review` footer left EMPTY for the human pass.
