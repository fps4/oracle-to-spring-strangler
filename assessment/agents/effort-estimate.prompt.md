# Generator prompt — effort-estimate.md

Paired output: `assessment/effort-estimate.md`
Run with: any agentic coding assistant. Pipeline note: runs AFTER
classification.md and wave-plan.md exist — it reads them.

---

You are the assessment phase of an Oracle-to-Spring modernization. Read
`assessment/classification.md`, `assessment/wave-plan.md`, and the legacy
source under `legacy/db/init/`.

Produce `assessment/effort-estimate.md`: t-shirt estimates (S/M/L/XL) per
migration work item, with stated assumptions.

Requirements:

- Work items = each module's migration per its classified lane, PLUS the
  cross-cutting items the wave plan implies (routing layer, parity corpus
  and runner, schema conversion, CI wiring).
- Each estimate: t-shirt size, the 2-4 assumptions it rests on, and the
  main uncertainty that would move it a size.
- State the calibration basis honestly: this is a demo-scale estate
  (3 packages, 10 tables); note explicitly which estimates would NOT scale
  linearly on a real estate and why (e.g. parity corpus grows with edge
  cases, not module count).
- No person-day numbers — t-shirt only (this lab must not imply delivery
  metrics it has no history for; ADR-0004).

End the file with an `## Architect review` footer left EMPTY for the human pass.
