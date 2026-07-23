# Assessment — per-module classification

> **Provenance (ADR-0004):** agent-drafted from
> `assessment/agents/classification.prompt.md` against `legacy/db/init/*`,
> `legacy/ords/modules.sql`, and ADR-0001..0005. Verdicts below are the
> agent's reading of the code; the architect decides in the review footer.

Scope: the three PL/SQL packages (`PKG_PRICING`, `PKG_ORDERS`,
`PKG_STATEMENTS`) and the ORDS REST facade. R-lane vocabulary:
rehost / replatform / refactor / retire. Where a verdict lands on an
ADR-0003 lane (extract-to-Java / translate-to-SQL / retain-as-PLpgSQL) the
mapping is argued from the code, not from the ADR.

---

## PKG_PRICING (`legacy/db/init/02_pkg_pricing.sql`)

### Complexity: 3 / 5

A single procedure, but a genuinely branchy discount cascade (tier band →
class discount → conditional promo override with two sub-branches), plus
package-level session state (`g_class_disc` initialized in the package init
block) and rounding-sensitive arithmetic that the comments explicitly fence
off (`TRUNC`, helpdesk #4711).

### Coupling notes

- **Inbound:** `PKG_ORDERS.place_order` calls `get_quote` per line — twice
  per line, in fact (comment RT-2203: quote logic is THE single source of
  pricing). The ORDS handler `GET /pricing/quote` calls it directly.
- **Outbound:** reads `customers`, `products`, `price_tiers`, `promotions`.
  No writes, no sequences, no commits — pure computation over reads.
- **Hidden state:** class-discount table lives in package memory
  (A=10, B=5, C=0), not in a table. Any target must source these constants
  from somewhere explicit.

### R-lane verdict: **refactor** (ADR-0003 lane: extract → Java service)

The code is side-effect-free, single-row reads plus arithmetic, with all the
behavioral interest in branch logic — exactly the shape that unit-tests well
as a plain Java domain class with the four lookups injected as data. Nothing
here needs the database's transactional machinery; the only DB features used
are `SELECT INTO` and a cursor used as a poor man's `FETCH FIRST 1`. The
extract-to-Java mapping is justified by the code's characteristics
(deterministic function of inputs + reference data), independent of ADR-0003
asserting it. The one structural consequence: because `PKG_ORDERS` consumes
this logic in-database today (RT-2203), extraction makes the *translated*
order flow depend on the *extracted* Java pricing component — acceptable only
because both land in the same service (ADR-0002), but it couples two lanes'
correctness and must be tested as a pair, not module-by-module.

### Risk register (parity hazards)

1. **`TRUNC(l_price, 2)`, not `ROUND`** — the marquee quirk. `BigDecimal`
   defaults (`HALF_UP`) silently break it; must be `RoundingMode.DOWN` at
   scale 2, applied at exactly this point in the cascade (truncate the unit
   price, *then* multiply by qty — `x_total := x_unit_price * p_qty`).
2. **Discount composition order** — tier and class discounts compose
   multiplicatively `(1 - t/100)*(1 - c/100)`, not additively. 4-dp list
   prices (e.g. product 1002 at 12.3456) make the difference observable.
3. **Promo selection is `ROWNUM = 1` with no `ORDER BY`** — with two
   simultaneously active promos for one product the picked row is
   arbitrary (physical/index order). Seed data never exercises this, so a
   "cleaner" deterministic implementation would pass every current test and
   still diverge on future data. Needs an explicit decision, not silent fix.
4. **Promo wins only if cheaper** — promo price beats the discounted price
   only when strictly lower; promo *pct* applies to **list** price and again
   only if the result beats the tier+class price. Easy to get subtly wrong.
5. **Date window is `TRUNC(SYSDATE) BETWEEN start_dt AND end_dt`** —
   day-granular, inclusive both ends; a timestamp-based Java comparison
   shifts boundary days.
6. **`NO_DATA_FOUND` semantics** — inactive customer or product surfaces as
   "not found" (HTTP 404 via facade), not a validation error. `status =
   'ACTIVE'` is part of the lookup predicate, not a separate check.
7. **Error identity** — ORA-20010 "QTY MUST BE POSITIVE" for `qty <= 0` or
   NULL; the facade maps -20010..-20012 to 400. Message text is part of the
   observed wire contract.

---

## PKG_ORDERS (`legacy/db/init/03_pkg_orders.sql`)

### Complexity: 4 / 5

The heaviest module: multi-step transaction (credit check → per-line pricing
→ order insert → per-line `SELECT ... FOR UPDATE` stock reservation → line
inserts → audit insert → `COMMIT`), explicit rollback-on-any-error, named
exception contract (-20001/-20002), a cross-package dependency, and a
JSON-parsing entry point (`place_order_json` via `JSON_TABLE`).

### Coupling notes

- **Inbound:** ORDS handler `POST /orders` calls `place_order_json`.
- **Outbound:** `PKG_PRICING.get_quote` (per line, **twice** — once in the
  pricing pass, once at line-insert time); reads `credit_limits`,
  `customers`, `orders` (exposure sum); writes `orders`, `order_lines`,
  `stock`, `audit_log`; consumes `seq_orders` and `seq_audit`; owns its own
  transaction boundary (`COMMIT`/`ROLLBACK` inside the procedure).

### R-lane verdict: **refactor** (ADR-0003 lane: translate → SQL under `@Transactional`)

The value of this module is its transactional envelope — credit exposure,
stock reservation, and audit all-or-nothing (helpdesk #3302: nothing
survives a failed order). That envelope maps directly onto
`JdbcTemplate` + `@Transactional`, and plain SQL keeps the `FOR UPDATE`
row-locking and the `SUM(total_amt)` exposure query recognizably identical
to the original — which is why translate beats an ORM re-modeling here.
One honest caveat to ADR-0003's rationale: calling this logic "inherently
set-based" overstates it. The procedure is row-by-row — per-line pessimistic
locks taken in input order, per-line stock errors naming the failing product
— and a naive "one set-based UPDATE" translation would *lose* parity
(error identity, lock granularity/ordering, which line fails first). The
translate lane is still right, but the translation must be loop-shaped SQL,
not aggregate-shaped SQL. Verdict agrees with ADR-0003's destination;
the "set-based" justification should be softened to "SQL-shaped with
transactional side effects."

### Risk register (parity hazards)

1. **Double pricing per line** — total is computed in a first `get_quote`
   pass (used for the credit check and `orders.total_amt`), then each line
   is priced *again* at insert. Under Oracle statement-level read
   consistency a concurrent promo/price change between passes can make
   `orders.total_amt ≠ SUM(order_lines.line_amt)`. A sensible Java rewrite
   prices once and reuses — which quietly fixes a latent legacy behavior.
   Fine to fix, but it must be a recorded decision, not an accident.
2. **Credit check race** — exposure is `SUM` over OPEN+SHIPPED with no lock;
   two concurrent orders can both pass. Serializable isolation or
   `SELECT ... FOR UPDATE` on the customer in the target would *tighten*
   behavior; matching parity means keeping the race (READ COMMITTED).
3. **Boundary is strict `>`** — an order landing exactly on the credit limit
   is allowed (`l_outstanding + x_total > l_limit` rejects only overspill).
4. **Error contract** — ORA-20001 → 422, ORA-20002 → 409 (facade mapping);
   message text embeds customer/product ids
   (`'INSUFFICIENT STOCK FOR PRODUCT ' || id`). Which product fails first
   depends on input line order — preserve iteration order.
5. **Stock semantics** — availability is `qty_on_hand - qty_reserved`;
   placing an order only bumps `qty_reserved` (and `updated_dt`); nothing
   here decrements `qty_on_hand`. Don't "improve" this into a decrement.
6. **Rollback swallows audit** — failed orders leave *no* audit row (the
   audit insert shares the transaction). Moving audit to a separate
   transaction/log stream changes observable DB state.
7. **`place_order_json` parsing quirks** — `JSON_TABLE` yields NULLs for
   missing/malformed fields rather than parse errors; an empty or absent
   `lines` array becomes ORA-20012 ("ORDER HAS NO LINES") → 400. Strict
   Jackson-style validation would reclassify these failures.
8. **Sequence gaps** — `seq_orders.NEXTVAL` is consumed before the inserts;
   failed orders burn ids. Only matters if anything asserts id continuity
   (nothing should, but note it for the parity corpus).

---

## PKG_STATEMENTS (`legacy/db/init/04_pkg_statements.sql`)

### Complexity: 2 / 5

Linear control flow: validate period, delete-then-regenerate, one cursor
loop over active customers with a single `DECODE`-based aggregate per
customer, conditional insert, audit, commit. The quirks are behavioral, not
structural.

### Coupling notes

- **Inbound:** ORDS handler `POST /statements/run`; the header comment says
  the real trigger is cron on ORAPRD02 (03:00 first Sunday) — the HTTP
  endpoint is the demo-visible stand-in for a batch schedule.
- **Outbound:** reads `customers`, `orders`; deletes/inserts `statements`;
  writes `audit_log`; consumes `seq_statements`, `seq_audit`; owns
  `COMMIT`/`ROLLBACK`. **No dependency on either other package** — the most
  isolated module in the estate.

### R-lane verdict: **replatform** (ADR-0003 lane: retain → converted PL/pgSQL)

Replatform in the classic sense: move the code to the new database with
minimal change (SCT-style mechanical conversion to PL/pgSQL behind a thin
wrapper), rather than rewriting it. The code supports this on
cost/benefit grounds — it is fully self-contained, set-in-its-ways batch
logic with zero coupling to the modules being rewritten, so retaining it
unblocks the wave plan without dragging month-end reconciliation risk into
the Java codebase. **However, this is the one place the code pushes back on
ADR-0003's stated rationale.** The ADR justifies retention as "highest
parity risk"; on inspection this is the *simplest* module — the whole loop
collapses to one `INSERT ... SELECT ... GROUP BY` and its quirks (below) are
few, enumerable, and easily corpus-tested. By pure code characteristics it
is a *translate-to-SQL* candidate, arguably an easier one than `PKG_ORDERS`.
The honest defense of the retain lane is strategic, not technical: lowest
change *value* (frozen batch, cron-driven, no redesign pressure), plus the
demo's need to exhibit the retained-tier pattern with its burn-down story.
Recorded as a tension for the architect: keep the lane, but re-ground its
rationale in change-value and demonstration intent, or the ADR's
"parity risk dominates" claim will not survive review of this file.

### Risk register (parity hazards)

1. **Period validation is two-layered and quirky** — `TO_DATE(p_period ||
   '-01')` catches garbage, then a literal `LENGTH != 7 OR SUBSTR(5,1) !=
   '-'` check catches lenient parses (e.g. `2026-7`, which `TO_DATE`
   happily accepts). Both fail as ORA-20003 → 400. A regex-only rewrite
   changes which inputs fail and with what message.
2. **Rerun semantics** — `DELETE ... WHERE period = p_period` then
   regenerate: reruns change `stmt_id` and `run_dt` for the same period.
   Statement ids are not stable identifiers; nothing downstream may assume
   they are.
3. **Inactive customers silently vanish** — the cursor filters
   `status = 'ACTIVE'`, so a customer deactivated mid-month gets *no*
   statement even with orders in the period. Preserve; do not "fix."
4. **Zero-activity suppression** — `l_cnt > 0` gates the insert (the 2008
   "zero statements in the post" complaint). `order_cnt` counts all
   non-CANCELLED orders; `open_amt` = OPEN+SHIPPED; `invoiced_amt` =
   INVOICED only. CANCELLED is excluded from the count but so is its amount
   — three different status filters in one query, easy to conflate.
5. **Period bucketing via `TO_CHAR(order_dt, 'YYYY-MM')`** — string
   bucketing of a DATE that carries a time component; a rewrite using
   half-open date ranges is semantically identical here but must be shown
   equivalent, not assumed.
6. **Audit row on success only** (same rollback-swallows-audit pattern as
   `PKG_ORDERS`), and the audit row carries the statement count in its
   `details` string.

---

## ORDS facade (`legacy/ords/modules.sql`)

### Complexity: 2 / 5

Four thin handlers with no business logic — but the hand-rolled
serialization (`HTP.p` string concatenation, the `n2j` number formatter,
`'ORA' || SQLCODE` error bodies) *is* the wire contract the strangler must
match byte-for-byte-ish, which gives a trivially small file outsized
behavioral weight.

### Coupling notes

- **Inbound:** every external consumer; post-M1 the nginx strangler router
  (ADR-0005) is the only caller, flipping routes away per `waves.yml`.
- **Outbound:** delegates to all three packages plus one inline
  `JSON_OBJECT` query (`GET /orders/:id`) that bypasses the packages
  entirely and reads `orders`/`order_lines` directly — the facade is not a
  pure package proxy.

### R-lane verdict: **retire**

The facade is the strangler seam itself, not a migration workload. Its
logic is presentation-only (parameter coercion, JSON assembly, SQLCODE→HTTP
mapping) and its natural fate under ADR-0005 is route-by-route
decommissioning: as each wave flips in `waves.yml`, the corresponding
handler stops receiving traffic, and when the last route flips the ORDS
container is deleted. Nothing here maps to an ADR-0003 lane because nothing
here is business logic to place — what survives is the *contract* it
defines (README error table, FS-0005 RFC 7807 mapping), which migrates into
the target's exception handlers and the parity corpus, not into code
translated from this file.

### Risk register (parity hazards)

1. **Bespoke number serialization** — `n2j` uses
   `TO_CHAR(p, 'FM999999999990.09999')` + `RTRIM('.')` (quote endpoint) and
   a 2-dp variant for order totals. This is neither canonical JSON nor
   Jackson's default rendering (README shows `"total":809.5`,
   `"unit_price":16.19`). Parity comparison must be numeric, or the target
   must replicate the formatter; decide explicitly in FS-0005.
2. **Error body shape** — `{"error_code":"ORA-20001","message":"..."}` with
   `SQLERRM` truncated to 200 chars and embedded double quotes replaced by
   single quotes (a hand-rolled escaping quirk that can alter message text).
   The RFC 7807 translation table starts from these exact bodies.
3. **Status mapping lives only here** — -20001→422, -20002→409, -20003→400,
   -20010..-20012→400, `NO_DATA_FOUND`→404, else 500; success is 201 for
   `POST /orders` but default 200 for `POST /statements/run`. The packages
   know nothing of HTTP; retire the facade and this table must be
   re-homed, per endpoint, with tests.
4. **`GET /orders/:id` has no `WHEN OTHERS`** — a non-numeric `:id`
   (`TO_NUMBER` → ORA-01722) escapes the handler and surfaces as ORDS's own
   500 error shape, *not* the JSON error contract. An uncharted edge; the
   parity corpus should pin it before the target accidentally improves it.
5. **`GET /orders/:id` bypasses the packages** — its JSON projection
   (`order_dt` as `YYYY-MM-DD`, line array ordered by `line_no`, raw
   `NUMBER` values from `JSON_OBJECT`, which formats numbers differently
   than `n2j`) is a second, independent serialization style on the same API.

---

## Summary

| Module | Complexity | R-lane verdict | Target lane (ADR-0003 / ADR-0005) | ADR-0003 agreement |
|---|---|---|---|---|
| `PKG_PRICING` | 3 / 5 | refactor | Extract → Java service | Agrees |
| `PKG_ORDERS` | 4 / 5 | refactor | Translate → SQL (`JdbcTemplate`, `@Transactional`) | Agrees on lane; "inherently set-based" overstated — translation must stay loop-shaped to preserve per-line lock and error semantics |
| `PKG_STATEMENTS` | 2 / 5 | replatform | Retain → converted PL/pgSQL (transitional, burn-down planned) | Agrees on lane; disputes rationale — code shows *lowest* complexity and modest parity risk; retention is justified by change-value and demo intent, not by "highest parity risk" |
| ORDS facade | 2 / 5 | retire | Decommission route-by-route behind nginx (ADR-0005); contract survives as FS-0005 parity spec | n/a (not an ADR-0003 workload) |

Cross-cutting note: extracting `PKG_PRICING` while translating `PKG_ORDERS`
splits RT-2203's "single source of pricing" across two lanes; parity testing
must cover the *pair* (order placement exercising the extracted pricing
engine), not each module in isolation.

## Architect review


> Status: **pending sign-off** — this footer was drafted in the build session;
> the architect's merge of the M0 PR constitutes the human decision (ADR-0004).

- **Verified:** complexity scores and coupling notes reviewed against source;
  all four verdicts confirmed grounded in code characteristics.
- **Ratified:** PKG_ORDERS stays in the translate lane, but the agent's
  finding stands: the translation must remain loop-shaped to preserve
  per-line lock acquisition and error identity. This *narrows* FS-0003's
  "set-based SQL" wording — flagged at PR review as a spec-wording amendment
  (translate-to-plain-SQL, loop-shaped where semantics demand).
- **Open item for the architect (genuine tension, kept visible):** the
  classification disputes ADR-0003's "highest parity risk" rationale for
  retaining PKG_STATEMENTS — the code is the estate's simplest module.
  Options: (a) amend ADR-0003's rationale to lowest-change-value +
  demonstrate-the-retained-tier, or (b) record the tension here only.
  The lane itself is not in question. Decide at PR review.
