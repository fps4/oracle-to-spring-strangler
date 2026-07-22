# Generator prompt — classification.md

Paired output: `assessment/classification.md`
Run with: any agentic coding assistant with read access to `legacy/` and
`docs/design/decisions/` (this repo used Claude Code; see
`assessment/agents/README.md`).

---

You are performing the assessment phase of an Oracle-to-Spring modernization.
Read every file under `legacy/db/init/`, `legacy/ords/modules.sql`, and the
ADRs under `docs/design/decisions/` (especially ADR-0003, the three-way
placement decision framework).

Produce `assessment/classification.md`: per-module disposition for the three
PL/SQL packages AND the ORDS facade itself.

For each module:

- **Complexity score** — 1-5 with a one-line justification grounded in the
  code (branching, state, side effects, SQL shape).
- **Coupling notes** — inbound/outbound dependencies from the code.
- **R-lane verdict** — exactly ONE of rehost / replatform / refactor /
  retire, with a one-paragraph rationale. Where the verdict maps onto an
  ADR-0003 lane (extract-to-Java / translate-to-SQL / retain-as-PLpgSQL),
  say so explicitly and justify the mapping from the code's characteristics,
  not from the ADR's authority.
- **Risk register** — what breaks parity if migrated carelessly (name the
  specific quirks/side effects).

Be willing to disagree with ADR-0003 if the code argues otherwise — record
the tension honestly; the architect decides in review.
Close with a summary table (module, complexity, verdict, target lane).
End the file with an `## Architect review` footer left EMPTY for the human pass.
