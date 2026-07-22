# Migration wave plan — strangling the ORDS endpoints onto Spring

Generated from `assessment/agents/wave-plan.prompt.md`.
Inputs read in full: `assessment/business-rule-catalog.md`,
`assessment/dependency-map.md`, `assessment/classification.md`,
`docs/product/FS-0004-strangler-routing.md` (wave mechanics),
`docs/product/FS-0005-parity-harness.md` (gate mechanics). Lane assignments
come from the classification; dependency prerequisites from the dependency
map; gate contents reference catalog BR ids.

Mechanics recap (FS-0004): a wave is a PR that flips endpoint entries in
`strangler/waves.yml` from `legacy` to `target`; the nginx config is
regenerated from that file; `X-Served-By` proves who answered; a rollback is
a git revert of the wave PR. A wave may be marked `cut-over` only with a
committed parity-evidence report (FS-0005, `parity/evidence/wave-N/`)
produced against the exact commit being cut over.

> **Scope flag — "three endpoints" vs four.** The generator prompt and
> FS-0004 speak of three legacy endpoints (`pricing/quote`, `orders`,
> `statements/run`), but the dependency map documents **four**: FS-0004's
> wave list omits `GET /orders/:id`, the package-bypassing read endpoint
> ([E23], [E24]). It must be routed by `waves.yml` like everything else or
> it silently pins ORDS alive forever. This plan places it in Wave 2
> alongside `POST /orders` (same tables, read-after-write coherence — see
> Wave 2 notes). FS-0004 should be amended to name it.

## Wave table

| Wave | Endpoints | Target lane (classification) | Dependency prerequisites (dependency map) | Status |
|---|---|---|---|---|
| 1 | `GET /pricing/quote` | Extract → Java service (refactor) | None. `PKG_PRICING` is a leaf: calls no package, reads only `customers`, `products`, `price_tiers`, `promotions` [E1–E4], zero writes, zero sequences. Router (FS-0004) and parity harness (FS-0005) must exist. | planned |
| 2 | `POST /orders`, `GET /orders/:id` | `POST /orders`: Translate → SQL under `@Transactional` (refactor). `GET /orders/:id`: direct-SQL read reimplementation (no package to port; contract-only). | **Wave 1 complete and gated** — `PKG_ORDERS` calls `pkg_pricing.get_quote` twice per line [E19, E20]; the translated order flow consumes the extracted Java pricing component, so pricing parity must already be proven. Writes `orders`, `order_lines`, `stock`, `audit_log` [E7–E11]; uses `seq_orders`, `seq_audit` [E16, E17]. `GET /orders/:id` needs only read parity on `orders`/`order_lines` [E23, E24]. | planned |
| 3 | `POST /statements/run` | Retain → converted PL/pgSQL behind a thin wrapper (replatform, transitional per ADR-0003) | Independent of Waves 1–2: `PKG_STATEMENTS` calls no other package and nothing calls it. Reads `customers`, `orders` [E12, E13]; writes `statements`, `audit_log` [E14, E15]; uses `seq_statements`, `seq_audit` [E18]. Reads the `orders` table, so it must run against wherever order data lives after Wave 2 — sequencing it after Wave 2 avoids a split-brain read. | planned |
| 4 | Decommission (no route flips; ORDS + legacy packages retired) | Retire (classification verdict for the ORDS facade) | Waves 1–3 all `cut-over` with committed evidence; rollback drill exhibit exists (FS-0004); observation window elapsed. | planned |

---

## Wave 1 — `GET /pricing/quote` → extracted Java pricing service

**Why pricing is first (dependency-map grounds).** The dependency map's
sequencing section is unambiguous: `PKG_PRICING` is the only shared
dependency in the estate and is itself a leaf — no package calls, four
read-only tables, no writes, no sequences, no commits. A wrong answer
during parity testing corrupts nothing (lowest blast radius), and migrating
it first unblocks the hardest consumer, `PKG_ORDERS`, which invokes
`get_quote` twice per order line as its pricing source of truth (RT-2203).
The map's conclusion — "Pricing therefore migrates before (or at latest
together with) orders; it can never migrate after" — is adopted here as the
Wave 1 → Wave 2 ordering constraint.

**The PKG_ORDERS → PKG_PRICING reconciliation (what stays duplicated).**
During the Wave 1 → Wave 2 transition window, pricing logic exists twice:

- the **extracted Java pricing component** answers `GET /pricing/quote`
  through the router;
- the **original `pkg_pricing.get_quote`** keeps answering in-database for
  `POST /orders`, which is still routed to legacy and still calls it via
  [E19, E20].

This duplication is deliberate and acceptable because: (1) the legacy
specimen is frozen (FS-0001) — the PL/SQL side cannot drift, so the only
drift risk is a target-side pricing bug, which the Wave 1 gate below pins
against the full BR-PRC corpus including the TRUNC specimen; (2) the
alternative — rerouting `PKG_ORDERS`'s internal calls out to Java —
would put a network hop inside the legacy transaction and change the very
behavior we are trying to preserve; (3) the window is bounded: it ends at
Wave 2 cutover, when the translated order flow starts consuming the
extracted Java component directly (classification cross-cutting note: the
pair must then be parity-tested *together*, not module-by-module). The
residual risk during the window is a quote-vs-order price mismatch visible
to a consumer who quotes on target and orders on legacy — exactly the
mismatch the parity gate exists to rule out.

**Exit criterion — parity gate.** `make parity` green on the quote corpus
against both stacks, evidence committed to `parity/evidence/wave-1/`. The
gate protects:

- Validation: BR-PRC-01 (qty positive, ORA-20010 → 400), BR-PRC-02 and
  BR-PRC-03 (missing/inactive customer/product → unhandled NO_DATA_FOUND →
  404, indistinguishable entities).
- Calculation: BR-PRC-04 (best tier band, 0 if none), BR-PRC-05 (hardcoded
  A=10/B=5/C=0), BR-PRC-06 (multiplicative compounding), BR-PRC-08
  (absolute promo strictly cheaper), BR-PRC-09 (pct promo off LIST price,
  strictly cheaper), BR-PRC-12 (truncate-then-multiply order of
  operations).
- Quirks: BR-PRC-07 (ROWNUM=1 promo pick — corpus cannot expose it on seed
  data; the target's deterministic choice must be recorded as an accepted
  deviation in `parity/contract.md`), BR-PRC-10 (no promo → silent 'N'),
  and above all BR-PRC-11 (**preserve bug-for-bug**: TRUNC not ROUND, 2 dp
  — corpus MUST include the 4-dp specimen product 1002 at 12.3456 per
  FS-0005's "TRUNC rounding inputs" acceptance criterion).
- HTTP contract: BR-API-01 (response shape/number rendering — numeric
  comparison or replicated formatter, decided in the tolerance contract),
  BR-API-02 (404 body with hardcoded `ORA-01403`), BR-API-03
  (−20010..−20012 → 400, else 500), BR-API-09 (error body shape → RFC 7807
  mapping at the boundary), BR-API-10 (unauthenticated pass-through — no
  auth introduced silently).

**Rollback statement.** Revert the Wave 1 PR: `waves.yml` entry for
`pricing/quote` flips back to `legacy`, nginx config regenerates, reload.
Because the endpoint is read-only with zero side effects, rollback has **no
data consequences whatsoever** — no state was written on either stack.
This is the wave used for the FS-0004 rollback drill exhibit precisely
because its revert is provably consequence-free.

---

## Wave 2 — `POST /orders` + `GET /orders/:id` → translated SQL + direct read

**Scope.** The translated order flow (`JdbcTemplate` + `@Transactional`,
loop-shaped per the classification's caveat — per-line pessimistic locks in
input order, per-line error identity, NOT one set-based statement) and the
reimplemented order read. They flip together: `GET /orders/:id` reads what
`POST /orders` writes, and splitting them across stacks would make a
freshly placed target-side order unreadable (or a legacy order invisible)
depending on which store the read hits.

> **Contradiction flag (classification vs ADR-0003).** ADR-0003 justifies
> the translate lane as "logic is inherently set-based"; the classification
> shows the procedure is row-by-row and warns that an aggregate-shaped
> translation would *lose* parity (lock granularity, which line fails
> first, error message ids). This plan follows the classification: the lane
> stands, the rationale wording in ADR-0003 should be softened to
> "SQL-shaped with transactional side effects."

**Dependency prerequisites.** Wave 1 gated and cut over (pricing parity is
a hard precondition — BR-ORD-03 makes every BR-PRC rule transitive into
order placement). Target-side pessimistic locking equivalent to
`SELECT ... FOR UPDATE` [E8] in place. Side-state snapshot machinery in the
parity runner (FS-0005 scope item 2) working, since this is the first
mutating wave.

**Exit criterion — parity gate.** `make parity` green on the orders corpus
(responses AND side-effect state: stock deltas, audit rows, order/line rows
after each case, per FS-0005), evidence in `parity/evidence/wave-2/`. The
gate protects:

- Validation and ordering: BR-ORD-01 (empty order → ORA-20012 → 400,
  checked before customer lookup), BR-ORD-02 (ACTIVE + credit-limit row,
  else 404), BR-ORD-05 (strict `>` credit boundary — exactly-on-limit
  accepted; seed customer 3 is the reject specimen), BR-ORD-07
  (per-line stock check under row lock, ORA-20002 → 409, input-order
  failure identity; seed product 1003 is the low-stock specimen).
- Transitive pricing: BR-ORD-03 → BR-PRC-01..12 replayed through the
  order path, exercising the extracted-pricing + translated-orders pair
  as a unit (classification cross-cutting note).
- Side effects: BR-ORD-06 (OPEN header, sequence id — ids compared
  structurally per the tolerance contract, gaps normal), BR-ORD-08
  (qty_reserved incremented, qty_on_hand untouched), BR-ORD-10 (1-based
  line numbering, per-line independent tier pricing), BR-ORD-11 (audit row
  `cust=<id> total=<n> lines=<n>`; `audit_user` excluded per catalog note),
  BR-ORD-12 (all-or-nothing transaction — failure cases must show zero
  residual rows in the side-state snapshot).
- Quirks and contract: BR-ORD-04 (exposure = OPEN+SHIPPED, unlocked read —
  target must not be stricter), BR-ORD-09 (double pricing — if the target
  prices once, record it as an accepted deviation in `parity/contract.md`,
  per the catalog and classification), BR-ORD-13 (JSON degradation paths:
  missing lines → 400, missing customer_id → 404, non-numeric → 500 — no
  stricter validation), BR-API-04 (201, literal "OPEN", 1–2 dp total, no
  Location header), BR-API-05 (the load-bearing status map: 20001→422,
  20002→409, 1403→404, 20010..12→400, else 500), BR-API-06 (read
  projection: date-only order_dt, lines by line_no, `"lines":null` on zero
  rows), BR-API-07 (unknown order → 404 hardcoded `ORA-01403`; non-numeric
  id 500-path is an accepted-deviation candidate), BR-API-09 (error body
  shape).

**Rollback statement.** Revert the Wave 2 PR: both entries flip back to
`legacy`, config regenerates, reload — mechanically identical to Wave 1
per FS-0004. **Unlike Wave 1, this revert is not consequence-free**: orders
accepted by the target during the cut-over window live in the target's
store, where legacy `PKG_ORDERS` cannot see them — legacy credit exposure
(BR-ORD-04) and stock reservations (BR-ORD-08) would silently exclude
them, and `GET /orders/:id` on legacy would 404 them. FS-0004's
"rollback is a git revert" holds for routing but is silent on this data
reconciliation; the wave PR must therefore state the rollback data
procedure (back-fill target-window orders into the legacy store, or
declare an accepted loss window) **before** cutover. Flagged for the
architect as a gap between FS-0004's rollback claim and the realities of
the first mutating wave.

---

## Wave 3 — `POST /statements/run` → retained-PL/pgSQL tier (the wrapper cutover)

**Scope.** Per ADR-0003 and FS-0004 scope item 4, `PKG_STATEMENTS` is not
rewritten: it is mechanically converted (SCT-style) to PL/pgSQL and invoked
through a thin wrapper in the target service. The "cutover" of this wave is
routing `statements/run` to that wrapper — the business logic deliberately
stays procedural code in the database, honestly labeled transitional.

> **Contradiction flag (classification vs ADR-0003, recorded, not
> papered over).** ADR-0003's stated rationale for retention is "highest
> parity risk / lowest change value." The classification, from the code,
> finds the opposite on the first half: `PKG_STATEMENTS` is the *simplest*
> module in the estate (complexity 2/5, quirks few and enumerable) and by
> pure code characteristics a translate-to-SQL candidate easier than
> `PKG_ORDERS`. This plan keeps the retain lane — the change-value and
> demonstration arguments hold — but the burn-down below leans on the
> classification's finding: *because* the module is simple, demolishing the
> transitional tier later is cheap and credible. ADR-0003's rationale
> should be re-grounded in change value before this survives review.

**Dependency prerequisites.** None on other packages (the most isolated
module in the estate — no inter-package edges in either direction). It
does read the `orders` table [E13], so it runs after Wave 2 so that
month-end aggregates see the same order store the target writes to.
Conversion artifact (PL/pgSQL) deployed and wrapper endpoint implemented.

**Exit criterion — parity gate.** `make parity` green on the statements
corpus (including FS-0005's "empty statement periods" cases), evidence in
`parity/evidence/wave-3/`. The gate protects:

- BR-STM-01 (two-layer period validation — corpus must include `'2026-13'`
  which fails the parse check and `'2026-7'` which passes parse but fails
  the length check, both → ORA-20003 → 400; a regex-only rewrite of the
  wrapper's edge would change which inputs fail).
- BR-STM-02 (rerun wipes and rebuilds the period; failed rerun leaves the
  previous run intact), BR-STM-03 (ACTIVE-at-run-time filter — deactivated
  customers silently get no statement; preserve), BR-STM-04 (open =
  OPEN+SHIPPED, invoiced = INVOICED, count excludes CANCELLED — three
  different status filters, kept consistent with BR-ORD-04's exposure
  definition), BR-STM-05 (no activity → no statement row, and the echoed
  count is the parity check value), BR-STM-06 (sequence-keyed inserts, ids
  unstable across reruns — compared structurally), BR-STM-07 (one audit
  row per run, `period=<p> stmts=<n>`, written even for zero-statement
  runs), BR-STM-08 (whole run atomic).
- BR-API-08 (bad period → 400, else 500, success 200 with
  `{"period":...,"statements":N}`; missing period key ≡ bad period) and
  BR-API-09 (error body shape). The catalog's BR-API-08/BR-API-10 hazard —
  a batch job exposed over unauthenticated HTTP — carries over to the
  wrapper unchanged during the transition (no silent auth fix), but must
  be resolved before this endpoint outlives the demo scope.

**Rollback statement.** Revert the Wave 3 PR; `statements/run` routes back
to ORDS → `pkg_statements.run_monthly`. Rollback is clean by construction:
the run is rerun-safe (BR-STM-02 — wipe-and-rebuild per period), so any
period generated by the retained tier during the window is simply
regenerated by a legacy rerun. Statement ids are explicitly not stable
identifiers (BR-STM-02 migration note), so the id churn a rollback-rerun
causes is within contract.

**Burn-down note (ADR-0003 requires the transitional tier to have a stated
end).** The retained PL/pgSQL tier is scaffolding, not architecture. Its
demolition is planned as follows:

- **Trigger:** after the wrapper has produced N consecutive clean month-end
  runs in parity with committed evidence (proposed N=3), and no earlier
  than Wave 4 readiness review.
- **Destination lane:** translate → SQL, the lane the classification found
  the code naturally fits (the whole loop collapses to one
  `INSERT ... SELECT ... GROUP BY`); the existing Wave 3 corpus
  (BR-STM-01..08, BR-API-08) is reused unchanged as the demolition gate —
  the retained tier's chief deliverable is precisely this corpus.
- **Done means:** the PL/pgSQL objects are dropped, the wrapper body is
  replaced by the translated SQL, and the wave file's history shows the
  tier existed and was demolished — the "then burn down the retained tier"
  step of ADR-0003's framework demonstrated, not just promised.

---

## Wave 4 — Decommission: retiring the legacy endpoints

**What "retired" means mechanically.** No `waves.yml` entry points at
`legacy`; the nginx upstream for ORDS is removed from the generated
config; the ORDS container and its module definitions
(`legacy/ords/modules.sql`) are deleted from the compose runtime; the three
PL/SQL packages remain only as the frozen specimen source (FS-0001) for
audit/archaeology, never executed. Per the classification, the facade's
lane is *retire*: nothing in it migrates — what survives is its contract,
already re-homed into the target's exception mapping and the parity corpus
(BR-API-01..10).

**Evidence that must exist first (the decommission gate):**

1. Waves 1–3 all marked `cut-over` in `waves.yml`, each linking committed
   parity evidence (`parity/evidence/wave-1..3/`) produced against the
   exact cut-over commits (FS-0005 acceptance criterion).
2. The executed rollback drill exhibit in repo history with its
   walkthrough narrative (FS-0004 acceptance criterion) — proof the escape
   hatch worked while it still existed.
3. An observation window on each cut-over route with `X-Served-By: target`
   on all responses and zero traffic reaching the ORDS upstream (router
   logs), demonstrating no consumer still depends on a legacy-only
   behavior.
4. The CI parity job (FS-0005 scope item 5) green on the decommission PR
   itself — the corpus outlives the legacy stack as the target's
   regression suite; the recorded golden-master responses become the
   permanent oracle once the live legacy oracle is gone.
5. The accepted-deviation register in `parity/contract.md` complete: every
   knowingly changed behavior (BR-PRC-07 promo determinism, BR-ORD-09
   single-pass pricing if taken, BR-API-07 non-numeric-id 500 body) is
   recorded as a decision, not an accident — the ADR-0004 honesty
   requirement applied to the finish line.

**Rollback statement.** None. Decommission is the one deliberately
irreversible wave — that is what the evidence list above is for. Reverting
the decommission PR would restore routing config but not a running,
data-current ORDS/Oracle stack; the gate exists precisely because this
revert stops being meaningful. Wave 4 must therefore not merge until items
1–5 are all satisfied.

---

## Contradictions found between input artifacts (index)

Flagged in-line above; collected for the architect:

1. **FS-0004 / generator prompt vs dependency map:** "three endpoints" vs
   four — `GET /orders/:id` is absent from FS-0004's wave list; placed in
   Wave 2 here.
2. **ADR-0003 vs classification (PKG_ORDERS):** "inherently set-based"
   rationale vs the code's row-by-row reality; lane kept, wording should
   change, translation must stay loop-shaped.
3. **ADR-0003 vs classification (PKG_STATEMENTS):** "highest parity risk"
   rationale vs measured lowest complexity; lane kept on change-value
   grounds, burn-down made cheaper by the same finding.
4. **FS-0004 rollback claim vs mutating waves:** "rollback is a git
   revert" is complete for Wave 1 (read-only) but under-specified for
   Wave 2, where target-window orders need a stated data-reconciliation
   procedure.

## Architect review

> Status: **pending sign-off** — this footer was drafted in the build session;
> the architect's merge of the M0 PR constitutes the human decision (ADR-0004).

- **Ratified:** four-wave structure; wave 1 = pricing quote (leaf, read-only)
  matching FS-0004; bounded pricing duplication during the wave-1→2 window
  (the frozen specimen cannot drift, so duplication risk is one-sided).
- **Spec gap confirmed (flagged by the agent, endorsed):** FS-0004 lists
  three routed endpoints; the estate has four — `GET /orders/{id}` is absent.
  The wave plan's answer (flip it with wave 2 for read-after-write coherence)
  is right; FS-0004 amendment proposed at PR review.
- **Carried forward:** wave-2 rollback needs a data-reconciliation statement
  for orders captured on the target during the cutover window — assigned to
  FS-0004 M2 work, not papered over here.
