# Generator prompt — business-rule-catalog.md

Paired output: `assessment/business-rule-catalog.md`
Run with: any agentic coding assistant with read access to `legacy/`
(this repo used Claude Code; see `assessment/agents/README.md`).

---

You are performing the assessment phase of an Oracle-to-Spring modernization.
Read every file under `legacy/db/init/` (schema, PKG_PRICING, PKG_ORDERS,
PKG_STATEMENTS, seed) and `legacy/ords/modules.sql` (HTTP facade).

Produce `assessment/business-rule-catalog.md`: a catalog of EVERY business
rule embedded in the three PL/SQL packages and the ORDS handlers.

For each rule record:

- **Rule ID** — `BR-<PKG>-<nn>` (e.g. `BR-PRC-01`).
- **Statement** — one plain-language sentence a business owner would confirm.
- **Source anchor** — package.procedure, file path, line number(s).
- **Kind** — calculation | validation | side-effect | error-contract | data-quirk.
- **Migration notes** — side effects, transaction behavior, quirks, and
  anything that must be preserved bug-for-bug.

Non-negotiables:

- The TRUNC currency-rounding quirk MUST appear as its own rule, flagged
  `preserve bug-for-bug`, with the code comment's history noted.
- The PLACE_ORDER side-effect set (credit check, stock reservation, audit
  insert, single-transaction rollback) MUST be catalogued rule-by-rule.
- Include the error contract (named exceptions to HTTP status mapping in the
  ORDS handlers) as rules — the target must reproduce it.
- Include implicit/accidental rules (e.g. unhandled NO_DATA_FOUND behavior,
  promotion selection with ROWNUM=1, statement skip-if-no-activity): legacy
  behavior is the contract whether intended or not.
- Do NOT invent rules that are not in the code. Every anchor must be real.

Format: markdown, one `##` section per package plus one for the facade,
a summary table (rule count by kind) at top. End the file with an
`## Architect review` footer left EMPTY for the human pass.
