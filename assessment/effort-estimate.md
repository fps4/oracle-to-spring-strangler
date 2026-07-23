# Assessment — effort estimate (t-shirt)

> **Provenance (ADR-0004):** agent-drafted from
> `assessment/agents/effort-estimate.prompt.md` against
> `assessment/classification.md`, `assessment/wave-plan.md`, and the legacy
> source under `legacy/db/init/`. Sizes are the agent's judgment of relative
> effort; the architect decides in the review footer.

Scale: **S** < **M** < **L** < **XL**, relative to each other within this
estate only. Per ADR-0004 this lab publishes no person-day or velocity
numbers — it has no delivery history to calibrate them against, and t-shirt
sizes are the most precision the evidence supports. Sizes include the
module's share of parity-case authoring but NOT the shared corpus/runner
infrastructure, which is estimated separately as a cross-cutting item.

---

## Module work items (per classified lane)

### 1. `PKG_PRICING` — extract → Java service (Wave 1) — **M**

The code is small (one procedure, ~80 lines) but the size is carried by the
parity hazard register, not the line count: seven distinct hazards
(classification), including the marquee `TRUNC`-not-`ROUND` quirk, the
multiplicative discount composition, the strictly-cheaper promo override,
and the day-granular date window.

**Assumptions:**

- The four reference lookups (`customers`, `products`, `price_tiers`,
  `promotions`) are injected as data via straightforward repository reads —
  no caching layer, no session-state re-creation beyond hardcoding
  A=10/B=5/C=0 as an explicit constant table.
- `BigDecimal` with `RoundingMode.DOWN` at scale 2, applied
  truncate-then-multiply, reproduces Oracle `TRUNC(x, 2)` for all corpus
  inputs (4-dp list prices included).
- The BR-PRC-07 nondeterminism (`ROWNUM = 1`, no `ORDER BY`) is resolved by
  a recorded accepted deviation in `parity/contract.md`, not by attempting
  to reproduce Oracle physical row order.

**What moves it a size:** if numeric parity cannot be closed with
`BigDecimal` arithmetic alone (e.g. an intermediate-precision divergence in
the discount cascade surfaces on 4-dp prices) and the tolerance contract
turns into a formatter-replication exercise (BR-API-01), this becomes L.
If the corpus passes on the first honest run, it was an S that looked like
an M — but budget for the M.

### 2. `PKG_ORDERS` — translate → SQL under `@Transactional` (Wave 2) — **L**

The heaviest module (complexity 4/5): multi-step transaction, per-line
pessimistic locking in input order, error identity embedding ids in message
text, eight parity hazards, and a cross-lane coupling — the translated flow
consumes the extracted Java pricing component, so the pair must be
parity-tested together (classification cross-cutting note), which puts
integration-shaped test effort inside this item.

**Assumptions:**

- Translation is loop-shaped per the classification's caveat: per-line
  `SELECT ... FOR UPDATE` in input order, per-line error identity — NOT
  rewritten as one set-based statement.
- Postgres `SELECT ... FOR UPDATE` under READ COMMITTED reproduces the
  Oracle lock-and-check semantics closely enough that the corpus (including
  the low-stock specimen, product 1003) cannot tell them apart; the credit
  check race (BR-ORD-04) is deliberately preserved, not tightened.
- The double-pricing-per-line quirk (BR-ORD-09) is resolved as a recorded
  accepted deviation (price once, reuse) rather than faithfully reproduced.
- `place_order_json`'s lenient `JSON_TABLE` degradation paths (NULLs for
  malformed fields, missing lines → -20012) are reproduced by configuring
  Jackson/manual parsing to be equally lenient — no stricter validation.

**What moves it a size:** the Wave 2 rollback data-reconciliation gap
flagged in the wave plan. If the architect requires an implemented
back-fill procedure for target-window orders (not just a stated
accepted-loss window) before cutover, that is additional transactional
tooling with its own tests — XL. If JSON leniency parity proves fiddly
(each degradation path needing bespoke handling), that alone will not move
the size but will consume the L's slack.

### 3. `GET /orders/:id` — direct read reimplementation (Wave 2) — **S**

No package to port — the ORDS handler bypasses the packages with one inline
`JSON_OBJECT` query. The work is one read endpoint: date-only `order_dt`
rendering, lines ordered by `line_no`, `"lines":null` on zero rows, 404
with the hardcoded `ORA-01403` body.

**Assumptions:**

- Ships in the same wave PR as `POST /orders` (read-after-write coherence,
  per the wave plan) and reuses its schema/data access — no independent
  persistence work.
- The non-numeric-id 500 path (BR-API-07 — ORDS's own error shape, outside
  the JSON contract) is pinned as an accepted-deviation candidate, not
  byte-reproduced.

**What moves it a size:** if the tolerance contract decides the
`JSON_OBJECT` number rendering (a second serialization style, distinct from
`n2j`) must be replicated rather than compared numerically, this inherits a
formatter-matching problem it did not create — M.

### 4. `PKG_STATEMENTS` — retain → converted PL/pgSQL + wrapper (Wave 3) — **M**

The code itself is the simplest in the estate (complexity 2/5, linear
control flow) and a mechanical SCT-style conversion is small. The M is the
surrounding work: the thin wrapper endpoint with its error mapping, the
Oracle→PL/pgSQL divergences that mechanical conversion must get right
(`DECODE`, `TO_CHAR(date)` bucketing, `RAISE_APPLICATION_ERROR` codes →
wrapper-visible errors, sequence syntax, `SYSDATE` vs `now()` granularity),
and the two-layer period-validation quirk (BR-STM-01) whose lenient-parse
edge (`'2026-7'`) must fail identically.

**Assumptions:**

- Conversion is mechanical and stays procedural — no "improvement" into the
  one `INSERT ... SELECT` it could collapse to (that is the burn-down's
  job, explicitly out of scope here).
- The -20003/-20xxx error identity survives the PL/pgSQL boundary in a form
  the wrapper can map to the same HTTP contract (BR-API-08).
- Runs after Wave 2 so its `orders` reads hit the post-migration store — no
  split-brain read handling needed in this item.

**What moves it a size:** if Postgres date/exception semantics force a
non-mechanical rewrite of the validation block or the `TO_CHAR` bucketing
(equivalence must be shown, not assumed — BR-STM hazard 5), the "mechanical"
premise fails and this drifts toward L. The planned burn-down (retain →
translate later) is deliberately NOT included in this size; when triggered
it is an S on its own, because this wave's chief deliverable — the corpus —
is reused unchanged as the demolition gate.

### 5. ORDS facade — retire, route-by-route (Wave 4 decommission) — **S**

No code migrates. The work is the decommission PR itself: remove the ORDS
upstream from the generated nginx config, delete the container from the
compose runtime, verify the decommission gate's five evidence items, and
confirm the CI parity job stays green with golden masters as the permanent
oracle. The facade's real content — the error table and serialization
contract — was re-homed incrementally into Waves 1–3 and is costed there.

**Assumptions:**

- Waves 1–3 are all `cut-over` with committed evidence; the observation
  window and rollback-drill exhibit already exist (they are wave-plan gate
  items, not new work here).
- The accepted-deviation register in `parity/contract.md` is complete by
  this point — this item audits it, it does not author it.

**What moves it a size:** discovery during the observation window of a
consumer depending on a legacy-only behavior (e.g. the uncharted
non-numeric-id ORDS 500 shape) reopens a prior wave — the cost lands there,
but this item stalls until it clears.

---

## Cross-cutting work items (implied by the wave plan)

### 6. Strangler routing layer (`waves.yml` → nginx, FS-0004) — **M**

The seam everything else depends on: `waves.yml` as the routing source of
truth, config generation, `X-Served-By` attribution, revert-as-rollback
mechanics, and the executed rollback drill exhibit (a Wave 4 gate item).

**Assumptions:**

- Four endpoints total (the wave plan's scope flag: FS-0004's three plus
  `GET /orders/:id`) — a fixed, small route table.
- Plain reverse-proxying suffices: no request transformation, no
  header-dependent splitting, no percentage rollout.
- The rollback drill is performed on Wave 1 (provably consequence-free
  revert), as the wave plan proposes.

**What moves it a size:** any requirement beyond binary legacy/target
routing — shadow traffic, response diffing at the proxy, per-consumer
pinning — is a different (and larger) router. As specified, this is
near-fixed cost.

### 7. Parity corpus + runner (FS-0005) — **L**

The largest cross-cutting item and the project's center of gravity. The
runner must compare responses across both stacks AND side-effect state
(stock deltas, audit rows, order/line rows — first needed at Wave 2), apply
a tolerance contract (numeric comparison vs the two distinct legacy number
formatters; structural comparison of sequence-assigned ids), maintain the
accepted-deviation register, and emit committed evidence reports per wave
(`parity/evidence/wave-N/`). The corpus itself must pin ~30 BR ids across
three modules plus the API contract, including the deliberately awkward
specimens (4-dp TRUNC product 1002, credit-reject customer 3, low-stock
product 1003, `'2026-13'`/`'2026-7'` period edges, empty-period runs).

**Assumptions:**

- Both stacks run side-by-side in compose against the deterministic seed
  (FS-0001), so expected values are stable across clean startups; the
  evergreen-promo SYSDATE windows are the only calendar-relative inputs.
- Side-state snapshotting is table-scoped diffs against the known schema
  (10 tables), not a generic DB-diff engine.
- One runner serves all three waves; per-wave cost after Wave 1 is corpus
  authoring plus evidence generation, not runner rework.

**What moves it a size:** the tolerance contract. If numeric-equivalence
comparison is accepted, the runner stays L. If byte-level body matching is
demanded, replicating `n2j` (`FM999999999990.09999` + `RTRIM`), its 2-dp
variant, AND `JSON_OBJECT`'s independent rendering pushes this to XL — the
wave plan already routes this decision to FS-0005; it is the single most
leveraged call in the estimate.

### 8. Schema conversion (Oracle DDL + seed → Postgres) — **M**

Ten tables, three sequences, four indexes — mechanically small. The size is
in the seed and the types: `NUMBER(9,4)` list prices must keep exact scale
(the TRUNC quirk is only observable at 4 dp), `DATE`-with-time-component
semantics must survive the move (order_dt bucketing, promo day-granular
windows), and the deterministic bulk seed is a PL/SQL block driven by
`DBMS_RANDOM.SEED(20260722)` — Postgres cannot re-run it bit-identically.

**Assumptions:**

- Seed parity is achieved by exporting the Oracle-generated rows once and
  loading the same rows into Postgres (data copy), NOT by porting the
  random generator — the two stacks must hold identical business data for
  side-state comparison to mean anything.
- `NUMBER(p,s)` → `NUMERIC(p,s)` mappings preserve every scale the quirks
  depend on; Oracle `DATE` maps to a type the converted PL/pgSQL and the
  translated SQL both handle consistently (likely `timestamp(0)`).
- No triggers, views, or storage features beyond what the DDL shows (there
  are none in `01_schema.sql`).

**What moves it a size:** if anyone insists on porting the generator
instead of copying data, chasing `DBMS_RANDOM` reproducibility is an
open-ended sink — L and climbing. The data-copy assumption is the guard
rail; it should be recorded as a decision.

### 9. CI wiring (parity job, FS-0005 scope item 5) — **M**

A pipeline that boots both stacks (Oracle XE container + ORDS + Postgres +
target service), waits for deterministic seeding, runs `make parity`, and
publishes evidence artifacts; green required on wave PRs and, at Wave 4, on
the decommission PR with golden masters replacing the live legacy oracle.

**Assumptions:**

- The CI runner can run the `gvenzl` Oracle XE image (resources, licensing
  posture, startup time in minutes not tens of minutes).
- The compose topology used locally is reused in CI — no parallel
  CI-specific environment definition.
- Golden-master capture (for the post-decommission mode) is a runner
  feature (item 7), not separate CI work.

**What moves it a size:** if Oracle-in-CI proves infeasible (runner limits,
image policy) the job needs a split design — record-replay against
committed golden masters for PR CI, live-oracle runs only on dedicated
infrastructure — which is a different and larger piece of work: L.

---

## Summary table

| # | Work item | Lane / wave | Size |
|---|---|---|---|
| 1 | `PKG_PRICING` extract → Java | refactor / Wave 1 | **M** |
| 2 | `PKG_ORDERS` translate → SQL | refactor / Wave 2 | **L** |
| 3 | `GET /orders/:id` direct read | contract-only / Wave 2 | **S** |
| 4 | `PKG_STATEMENTS` convert → PL/pgSQL + wrapper | replatform / Wave 3 | **M** |
| 5 | ORDS facade decommission | retire / Wave 4 | **S** |
| 6 | Strangler routing layer | cross-cutting (FS-0004) | **M** |
| 7 | Parity corpus + runner | cross-cutting (FS-0005) | **L** |
| 8 | Schema conversion + seed data copy | cross-cutting | **M** |
| 9 | CI wiring for parity | cross-cutting (FS-0005) | **M** |

---

## Calibration basis — read before reusing these numbers

**This is a demo-scale estate**: 3 PL/SQL packages, ~10 tables, 4 HTTP
endpoints, ~350 lines of package code, and a seed corpus designed to make
every quirk reachable. The sizes above are calibrated against *each other*
within that estate, and against nothing else — there is no delivery history
behind them (ADR-0004), which is why they are t-shirts and not person-days.

On a real estate, these estimates would NOT scale linearly, in different
directions per item:

- **Parity corpus + runner (item 7) — grows with edge cases, not module
  count.** The runner is built once; the corpus grows with the number of
  *behavioral quirks worth pinning*, which on a 20-year estate is driven by
  accumulated helpdesk-ticket archaeology (this estate's #4711, #3302,
  RT-1189 pattern, multiplied by hundreds), undocumented consumer
  dependencies, and data-shape diversity — none of which is proportional to
  package count. Expect this to dominate real-estate effort by a wider
  margin than L-vs-M suggests here.
- **Routing layer (item 6) — near-fixed cost that amortizes.** Forty
  endpoints instead of four barely changes the router; it changes the
  number of wave PRs. On a real estate this item shrinks in relative terms.
- **Schema conversion (item 8) — scales with vendor-feature usage, not
  table count.** This schema uses no triggers, no materialized views, no
  partitioning, no VPD, no scheduler jobs. Each such feature on a real
  estate is its own conversion problem; 500 plain tables are cheaper than
  50 tables wearing those features.
- **Per-module sizes (items 1–4) — scale with quirk density and coupling,
  not lines.** `PKG_PRICING` at 80 lines is an M because of seven hazards;
  a 2,000-line package with three hazards can be smaller work. The
  demo modules were written to be quirk-dense; real estates are uneven, and
  the classification pass (complexity × coupling × hazard count) is the
  scaling function — not module count and not LOC.
- **CI wiring (item 9) — the Oracle-in-CI question gets harder, not
  easier**, on a real estate (licensed editions, data volumes, refresh
  cadence). The M here rests entirely on XE-in-a-container being possible.
- **What DOES scale roughly linearly:** wave-PR mechanics (item 6's
  per-wave marginal cost), evidence-report generation per wave, and
  mechanical PL/pgSQL conversion of *simple* retained modules — the parts
  that are deliberately procedural.

Finally, the estimates inherit every open decision flagged upstream: the
tolerance contract (moves items 3 and 7), the Wave 2 rollback data
procedure (moves item 2), and the seed data-copy decision (moves item 8).
Sizes assume the resolutions stated in each item's assumptions; a different
architect call on any of them re-sizes the item, which is exactly what the
assumption lists are for.

## Architect review

> Status: **pending sign-off** — this footer was drafted in the build session;
> the architect's merge of the M0 PR constitutes the human decision (ADR-0004).

- **Ratified:** all nine t-shirt sizes as drafted; no person-day figures
  (ADR-0004). The parity corpus/runner as the estate's center of gravity
  matches the product intent — parity discipline is the product.
- **Architect note:** the schema-conversion assumption (seed parity via
  copying Oracle-generated rows, not porting the generator) is accepted for
  M1 planning and revisited when FS-0003 Flyway work starts.
