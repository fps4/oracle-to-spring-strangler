# Business rule catalog — legacy PL/SQL + ORDS facade

Generated from `assessment/agents/business-rule-catalog.prompt.md`.
Sources read in full: `legacy/db/init/01_schema.sql`, `02_pkg_pricing.sql`,
`03_pkg_orders.sql`, `04_pkg_statements.sql`, `05_seed.sql`,
`legacy/ords/modules.sql`. Legacy behavior is the contract whether intended
or not; rules flagged `preserve bug-for-bug` must not be "fixed" in the target.

## Summary

| Kind           | Count |
|----------------|-------|
| calculation    | 9     |
| validation     | 8     |
| side-effect    | 9     |
| error-contract | 6     |
| data-quirk     | 11    |
| **Total**      | **43** |

---

## PKG_PRICING — quote calculation

Source: `legacy/db/init/02_pkg_pricing.sql` (`pkg_pricing.get_quote`).

### BR-PRC-01 — Quantity must be positive

- **Statement:** A quote is refused when the requested quantity is missing, zero, or negative.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 52–54.
- **Kind:** validation
- **Migration notes:** Raises `ORA-20010 'QTY MUST BE POSITIVE'`. The ORDS quote handler maps -20010..-20012 to HTTP 400 (see BR-API-03). NULL qty is rejected the same as non-positive.

### BR-PRC-02 — Customer must exist and be ACTIVE

- **Statement:** Quotes are only produced for customers that exist and have status ACTIVE.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 56–59.
- **Kind:** validation
- **Migration notes:** Implicit rule: a missing or non-ACTIVE customer raises an **unhandled** `NO_DATA_FOUND` (ORA-01403) that propagates out of the package; the ORDS facade converts it to HTTP 404 (BR-API-02). There is no distinct "customer inactive" error — inactive and nonexistent are indistinguishable to callers.

### BR-PRC-03 — Product must exist and be ACTIVE

- **Statement:** Quotes are only produced for products that exist and have status ACTIVE.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 61–64.
- **Kind:** validation
- **Migration notes:** Same unhandled `NO_DATA_FOUND` → 404 behavior as BR-PRC-02. The 404 body cannot distinguish "customer not found" from "product not found" ("customer or product not found", `legacy/ords/modules.sql` line 66).

### BR-PRC-04 — Volume tier discount picks the best matching band

- **Statement:** The volume discount is the percentage of the highest tier whose minimum quantity the ordered quantity reaches; if no tier matches, the volume discount is zero.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 45–50 (cursor, `ORDER BY min_qty DESC`) and 66–70 (default 0, single fetch).
- **Kind:** calculation
- **Migration notes:** `x_tier_disc` is initialized to 0 and a single `FETCH` overwrites it only when a row exists — the "0 if none" behavior depends on that init. Tiers are per-product (`price_tiers`, `uq_tiers (product_id, min_qty)`, `01_schema.sql` lines 55–63).

### BR-PRC-05 — Customer-class discount is hardcoded: A=10%, B=5%, C=0%

- **Statement:** Class-A customers get 10% off, class-B 5%, class-C 0%, from a table hardcoded in the package, not the database.
- **Source anchor:** `pkg_pricing` body, `legacy/db/init/02_pkg_pricing.sql`, line 72 (lookup) and lines 107–111 (package init block).
- **Kind:** calculation
- **Migration notes:** The associative array is loaded once per session in the package initialization block. Any class outside A/B/C would raise `NO_DATA_FOUND` on the array lookup, but the schema CHECK constraint `ck_cust_class` (`01_schema.sql` line 21) makes that unreachable in practice. Target may hardcode the same values but must keep them out of any per-request configuration that could drift.

### BR-PRC-06 — Tier and class discounts compound multiplicatively

- **Statement:** The discounted price is list price times (1 − tier%) times (1 − class%) — the discounts multiply, they do not add.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 74–76.
- **Kind:** calculation
- **Migration notes:** E.g. 15% tier + 10% class = 23.5% effective, not 25%. No intermediate rounding occurs here; rounding happens once at the end (BR-PRC-11).

### BR-PRC-07 — Promotion selection is arbitrary when several are active (ROWNUM = 1)

- **Statement:** When more than one promotion is active for a product on the quote date, one of them is picked arbitrarily and the rest are ignored.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 80–86 (`AND ROWNUM = 1`, no ORDER BY).
- **Kind:** data-quirk
- **Migration notes:** `ROWNUM = 1` without `ORDER BY` means the chosen promo depends on Oracle's access path — an accidental rule. The active window test is `TRUNC(SYSDATE) BETWEEN start_dt AND end_dt` (date-level, inclusive on both ends). Current seed data has at most one active promo per product (`05_seed.sql` lines 40–42), so parity tests won't expose the ambiguity, but the target must document its own deterministic choice as a deliberate deviation or reproduce "first row wins" against identical data.

### BR-PRC-08 — Absolute promo price wins only if it is cheaper

- **Statement:** A promotion with an absolute price replaces the discounted price only when the promo price is strictly lower than the tier/class-discounted price.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 88–90 (comment "promo price wins only if cheaper (RT-1189)" at line 78).
- **Kind:** calculation
- **Migration notes:** Strict `<` comparison — an equal promo price does NOT set `promo_applied='Y'`. Absolute price takes precedence over promo percentage when both columns are populated (the `IF/ELSIF` ordering, lines 88–91). Ticket RT-1189 is the recorded business intent.

### BR-PRC-09 — Percentage promo applies to LIST price and wins only if cheaper

- **Statement:** A percentage promotion is computed off the undiscounted list price (not the tier/class-discounted price) and replaces the price only when the result is strictly cheaper.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 91–95.
- **Kind:** calculation
- **Migration notes:** The base is `x_list_price`, so a 12.5% promo can lose to a 10%+5% compounded tier/class discount and then not apply at all (`promo_applied` stays 'N'). Preserve the strict `<` and the list-price base exactly.

### BR-PRC-10 — Absence of a promotion is silently ignored

- **Statement:** If no promotion is active for the product, the quote proceeds on the discounted price with promo_applied = 'N' and no error.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 79 (`x_promo_applied := 'N'`) and 97–99 (`WHEN NO_DATA_FOUND THEN NULL`).
- **Kind:** data-quirk
- **Migration notes:** This inner-block `NO_DATA_FOUND` swallow is deliberate, in contrast to the unhandled ones in BR-PRC-02/03. `promo_applied` is a `'Y'`/`'N'` VARCHAR2 flag in the API response — keep the letter values, not booleans, at the strangler boundary.

### BR-PRC-11 — Unit price is TRUNCATED (not rounded) to 2 decimals — `preserve bug-for-bug`

- **Statement:** The final unit price is truncated (cut, never rounded up) to 2 decimal places before extending to a line total.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, lines 101–103 (`x_unit_price := TRUNC(l_price, 2);`).
- **Kind:** data-quirk — **preserve bug-for-bug**
- **Migration notes:** The code comment records the history: "DO NOT CHANGE: finance reconciles against truncated unit price (helpdesk #4711, Aug 2009). ROUND() broke month-end, reverted." (lines 101–102); the file header repeats "do not touch rounding!" (line 1). Products carry 4-dp list prices (`01_schema.sql` line 37, "quirk source"); seed product 1002 at 12.3456 is the designated TRUNC specimen (`05_seed.sql` line 23). The target must use truncation toward zero (e.g. `RoundingMode.DOWN` on BigDecimal), never half-up rounding. `order_lines.unit_price` is NUMBER(9,2) "post-quirk 2 dp" (`01_schema.sql` line 91).

### BR-PRC-12 — Line total = truncated unit price × quantity

- **Statement:** The quoted total is the already-truncated unit price multiplied by the quantity, with no further rounding.
- **Source anchor:** `pkg_pricing.get_quote`, `legacy/db/init/02_pkg_pricing.sql`, line 104.
- **Kind:** calculation
- **Migration notes:** Order of operations matters: truncate first, then multiply. Truncating the extended total instead would give different figures. Since unit price is exactly 2 dp and qty is an integer in practice, the total is exact — but qty is typed plain NUMBER, so a fractional qty would flow through unrounded.

---

## PKG_ORDERS — order entry

Source: `legacy/db/init/03_pkg_orders.sql` (`pkg_orders.place_order`, `place_order_json`, private `log_audit`).
File header (line 1): "Credit + stock + audit in ONE transaction."

### BR-ORD-01 — An order must have at least one line

- **Statement:** An order with no lines is rejected before any other processing.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, lines 63–65.
- **Kind:** validation
- **Migration notes:** Raises `ORA-20012 'ORDER HAS NO LINES'` → HTTP 400 (BR-API-05). Checked first, before the customer lookup, so an empty order for a nonexistent customer returns 400, not 404.

### BR-ORD-02 — Customer must be ACTIVE and have a credit limit on file

- **Statement:** Orders are accepted only for ACTIVE customers that have a credit-limit record.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, lines 67–71 (join of `credit_limits` and `customers`).
- **Kind:** validation
- **Migration notes:** Implicit rule: an ACTIVE customer with **no `credit_limits` row** cannot order at all — the join raises unhandled `NO_DATA_FOUND` → HTTP 404 via BR-API-05 (`-1403 → 404`). Nonexistent, inactive, and no-credit-limit customers are all indistinguishable 404s.

### BR-ORD-03 — Order lines are priced by the quote logic, no separate pricing path

- **Statement:** Every order line is priced by exactly the same quote calculation the pricing endpoint uses (tiers, class, promos, TRUNC quirk included).
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, lines 73–80 (comment "quote logic is THE single source, RT-2203" at line 73).
- **Kind:** calculation
- **Migration notes:** All PKG_PRICING rules (BR-PRC-01..12) apply transitively to order placement, including the unhandled NO_DATA_FOUND for inactive products (a line for an unknown/inactive product 404s the whole order). Order total = sum of per-line totals; each line was truncated individually (no order-level rounding).

### BR-ORD-04 — Credit exposure counts OPEN and SHIPPED orders only

- **Statement:** A customer's outstanding exposure is the sum of order totals in status OPEN or SHIPPED; INVOICED and CANCELLED orders do not count.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, lines 82–86 (comment at line 82: "open + shipped exposure counts, invoiced does not").
- **Kind:** calculation
- **Migration notes:** `NVL(SUM(...), 0)` — a customer with no prior orders has zero exposure. Exposure is read without locking, so two concurrent orders can each pass the check against the same snapshot (a race the legacy system tolerates; the target must not make the check stricter than legacy).

### BR-ORD-05 — Reject when exposure plus new order exceeds the credit limit

- **Statement:** The order is refused if existing exposure plus this order's total is strictly greater than the customer's credit limit; an order that lands exactly on the limit is accepted.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, lines 88–91.
- **Kind:** validation
- **Migration notes:** Raises `ORA-20001 'CREDIT LIMIT EXCEEDED FOR CUSTOMER <id>'` (named `E_CREDIT_EXCEEDED`, package spec lines 7–8) → HTTP 422 (BR-API-05). Strict `>`: equality passes. Check happens before any insert, so a credit rejection leaves no order row (and no stock touched). Seed customer 3 (limit 500) is the credit-reject specimen (`05_seed.sql` line 19).

### BR-ORD-06 — Order header is created OPEN with a sequence-assigned id — PLACE_ORDER side effect 1

- **Statement:** A successful order gets its id from the order sequence and is inserted with status OPEN, today's date, and the computed total.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, lines 93–96; sequence `seq_orders` starts at 100000 (`01_schema.sql` line 122).
- **Kind:** side-effect
- **Migration notes:** `seq_orders.NEXTVAL` burns a number even if a later line fails and everything rolls back — order ids have gaps and that is normal. Status vocabulary is OPEN/SHIPPED/INVOICED/CANCELLED (`01_schema.sql` line 80). `order_dt` is `SYSDATE` (date+time), though the API renders date-only (BR-API-06).

### BR-ORD-07 — Per-line stock availability check under a row lock

- **Statement:** For each line, available stock (on hand minus already reserved) must cover the ordered quantity, checked while holding a row lock on the stock record.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, lines 100–113 (`SELECT ... FOR UPDATE`, availability test, `ORA-20002`).
- **Kind:** validation
- **Migration notes:** Raises `ORA-20002 'INSUFFICIENT STOCK FOR PRODUCT <id>'` (named `E_INSUFFICIENT_STOCK`, spec lines 9–10) → HTTP 409 (BR-API-05). The `FOR UPDATE` serializes concurrent reservations per product; the target needs equivalent pessimistic locking or an atomic conditional update to avoid over-reservation. A product with no `stock` row raises unhandled `NO_DATA_FOUND` → 404. Lines are processed in input order; a failure on line N rolls back lines 1..N−1 (BR-ORD-12). Seed product 1003 (qty 5) is the low-stock specimen (`05_seed.sql` lines 24, 30).

### BR-ORD-08 — Reservation increments qty_reserved, never decrements qty_on_hand — PLACE_ORDER side effect 2

- **Statement:** Placing an order reserves stock by increasing the reserved quantity; on-hand stock is untouched at order time.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, lines 115–118.
- **Kind:** side-effect
- **Migration notes:** Also stamps `stock.updated_dt = SYSDATE`. Nothing in the visible codebase ever releases reservations or decrements on-hand (shipping is out of scope of these packages) — the target must reproduce the reserve-only semantics, not invent a fuller lifecycle.

### BR-ORD-09 — Every line is priced twice; the header total comes from the first pass

- **Statement:** Pricing runs once up front for the order total and again per line when writing line rows; the two passes are assumed (not guaranteed) to agree.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, first pass lines 75–80, second pass lines 121–123.
- **Kind:** data-quirk
- **Migration notes:** Accidental rule. `orders.total_amt` is the sum from the FIRST pass (line 79/96); `order_lines.unit_price`/`line_amt` come from the SECOND pass (lines 125–126). If a promotion window boundary crosses between the passes (both use `TRUNC(SYSDATE)`), header total and line sums can disagree — legacy tolerates this. The target may price once, but a parity harness replaying at midnight boundaries could observe a difference; note as an accepted deviation if pricing is done once.

### BR-ORD-10 — Line numbers are the 1-based input position — PLACE_ORDER side effect 3

- **Statement:** Order lines are stored numbered 1, 2, 3… in the order the caller sent them, with the priced unit price and line amount.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, lines 125–126 (`line_no = i`).
- **Kind:** side-effect
- **Migration notes:** Duplicate products across lines are allowed and priced/reserved independently per line (each line's tier discount uses its own qty — two lines of 10 do NOT get the qty-20 tier). PK is `(order_id, line_no)` (`01_schema.sql` line 93).

### BR-ORD-11 — Audit row on successful order — PLACE_ORDER side effect 4

- **Statement:** Every successfully placed order writes one audit record: module PKG_ORDERS, action ORDER_PLACED, the order id, and a details string with customer, total, and line count.
- **Source anchor:** `pkg_orders.place_order` lines 129–131 and private `log_audit` lines 37–45, `legacy/db/init/03_pkg_orders.sql`; `seq_audit` starts at 900000 (`01_schema.sql` line 124).
- **Kind:** side-effect
- **Migration notes:** Details format is exactly `cust=<id> total=<n> lines=<n>` (implicit number-to-string conversion, no padding). `audit_user` defaults to the Oracle `USER` (`01_schema.sql` line 118) — after migration this value will necessarily differ; flag for the parity harness to exclude. The audit insert participates in the same transaction: no audit row survives a failed order.

### BR-ORD-12 — Single transaction: commit on success, roll back everything on any failure — PLACE_ORDER side effect 5

- **Statement:** Order placement is all-or-nothing — the order header, all lines, all stock reservations, and the audit row commit together, and any error erases all of them.
- **Source anchor:** `pkg_orders.place_order`, `legacy/db/init/03_pkg_orders.sql`, line 132 (`COMMIT`) and lines 133–136 (`WHEN OTHERS THEN ROLLBACK; RAISE;` — comment "nothing survives a failed order (helpdesk #3302)").
- **Kind:** side-effect
- **Migration notes:** The procedure commits internally (transaction control inside the package, not the caller). The target must wrap the equivalent work in one transaction with the same rollback-on-any-exception semantics — a partially-reserved order must never persist. The original exception is re-raised unchanged so the ORDS layer can map it (BR-API-05). Sequence values consumed before the failure stay consumed.

### BR-ORD-13 — JSON order body: customer_id at root, lines[] of {product_id, qty}; malformed input degrades to existing errors

- **Statement:** The order API body must carry a numeric customer_id and a lines array of product/qty pairs; missing pieces fall through to the "no lines" or "not found" errors rather than a dedicated parse error.
- **Source anchor:** `pkg_orders.place_order_json`, `legacy/db/init/03_pkg_orders.sql`, lines 139–161 (JSON_TABLE extraction lines 148–158).
- **Kind:** data-quirk
- **Migration notes:** Accidental contract: a body with a missing or absent `$.lines` array yields zero lines → `ORA-20012` → 400; a missing `$.customer_id` yields NULL → customer lookup `NO_DATA_FOUND` → 404; non-numeric values raise conversion errors → 500. There is no schema validation and no distinct "bad JSON body" error code. The target's request validation must not be stricter in ways that change these status codes for the same inputs.

---

## PKG_STATEMENTS — month-end statement run

Source: `legacy/db/init/04_pkg_statements.sql` (`pkg_statements.run_monthly`).
File header (line 1): scheduled 03:00 first Sunday via cron on ORAPRD02 — the schedule itself lives outside the database and is out of catalog scope, but the target must own an equivalent trigger.

### BR-STM-01 — Period must be a real 'YYYY-MM' month

- **Statement:** The statement period must be a 7-character YYYY-MM string that denotes a real calendar month.
- **Source anchor:** `pkg_statements.run_monthly`, `legacy/db/init/04_pkg_statements.sql`, lines 35–44 (comment "added after the '2007-13' incident" at line 35).
- **Kind:** validation
- **Migration notes:** Two checks, in order: (1) `TO_DATE(p_period || '-01', 'YYYY-MM-DD')` inside a `WHEN OTHERS` catch — any parse failure becomes `ORA-20003 'BAD PERIOD: <input>'`; (2) length must be exactly 7 with '-' at position 5. Named `E_BAD_PERIOD` (spec lines 7–8) → HTTP 400 (BR-API-08). Quirk: check (1) is lenient (Oracle would accept `'2026-7'`), so check (2) does the strictness — inputs like `'2026-7'` pass (1) and fail (2), still 400. Month 13 fails (1). Both produce the identical error, so the target only needs one combined validation with the same message shape.

### BR-STM-02 — Reruns wipe and rebuild the period

- **Statement:** Running statements for a period first deletes any statements previously generated for that period, making the run repeatable.
- **Source anchor:** `pkg_statements.run_monthly`, `legacy/db/init/04_pkg_statements.sql`, line 47 (comment "rerun-safe: wipe the period first" at line 46).
- **Kind:** side-effect
- **Migration notes:** Delete-then-insert in one transaction — a mid-run failure rolls the delete back too (BR-STM-08), so a failed rerun leaves the previous run's statements intact. New `stmt_id`s are issued on every rerun (`seq_statements`); statement ids are not stable across reruns. Uniqueness is `(customer_id, period)` (`01_schema.sql` line 107).

### BR-STM-03 — Only currently-ACTIVE customers get statements

- **Statement:** Statements are generated only for customers whose status is ACTIVE at run time, processed in ascending customer-id order.
- **Source anchor:** `pkg_statements.run_monthly`, `legacy/db/init/04_pkg_statements.sql`, lines 24–28 (cursor) and 51 (loop).
- **Kind:** data-quirk
- **Migration notes:** Implicit rule: a customer deactivated after placing orders silently gets no statement for periods with real activity — status is evaluated at run time, not for the period. Legacy behavior is the contract. The `ORDER BY customer_id` fixes the stmt_id assignment order, which matters only if anything downstream depends on id ordering.

### BR-STM-04 — Statement amounts: open = OPEN+SHIPPED, invoiced = INVOICED, count excludes CANCELLED

- **Statement:** For each customer and period, the open amount sums OPEN and SHIPPED order totals, the invoiced amount sums INVOICED totals, and the order count covers all non-cancelled orders in the month.
- **Source anchor:** `pkg_statements.run_monthly`, `legacy/db/init/04_pkg_statements.sql`, lines 52–60.
- **Kind:** calculation
- **Migration notes:** Period membership is `TO_CHAR(order_dt, 'YYYY-MM') = p_period` — string match on the order's date, session-timezone-free (DATE type). CANCELLED orders are excluded from all three figures by the `status != 'CANCELLED'` predicate. Note the open/shipped bucketing mirrors the credit-exposure definition (BR-ORD-04) — keep the two consistent in the target. `DECODE(...,0)` means an unexpected status value would count in `order_cnt` but contribute 0 to both amounts.

### BR-STM-05 — No activity, no statement

- **Statement:** A customer with no non-cancelled orders in the period gets no statement row at all — never a zero statement.
- **Source anchor:** `pkg_statements.run_monthly`, `legacy/db/init/04_pkg_statements.sql`, lines 62–72 (`IF l_cnt > 0` guard; comment "no activity, no statement (customers complained about zero statements in the post, 2008)").
- **Kind:** data-quirk
- **Migration notes:** Implicit consequence: a customer whose only orders in the month are CANCELLED also gets no statement (count excludes cancelled). The returned `x_stmt_cnt` counts only inserted statements, and that count is echoed by the API (BR-API-08) and written into the audit row (BR-STM-07) — parity checks can use it.

### BR-STM-06 — Statement rows are sequence-keyed inserts

- **Statement:** Each generated statement gets its id from the statement sequence and records the period figures plus the run timestamp.
- **Source anchor:** `pkg_statements.run_monthly`, `legacy/db/init/04_pkg_statements.sql`, lines 65–71; `seq_statements` starts at 500000 (`01_schema.sql` line 123).
- **Kind:** side-effect
- **Migration notes:** `run_dt = SYSDATE` per row. Sequence gaps across failed/rolled-back runs are normal.

### BR-STM-07 — One audit row per run

- **Statement:** Every statement run writes a single audit record: module PKG_STATEMENTS, action RUN_MONTHLY, no ref id, and a details string with the period and the statement count.
- **Source anchor:** `pkg_statements.run_monthly`, `legacy/db/init/04_pkg_statements.sql`, lines 75–77.
- **Kind:** side-effect
- **Migration notes:** Details format exactly `period=<p> stmts=<n>`; `ref_id` is NULL. Written even when zero statements were produced (a valid empty run still audits). Unlike PKG_ORDERS, this package inserts into `audit_log` directly, not via a helper — same table, same sequence.

### BR-STM-08 — Single transaction: commit on success, roll back everything on failure

- **Statement:** The whole run — period wipe, all statement inserts, and the audit row — commits atomically; any failure restores the pre-run state.
- **Source anchor:** `pkg_statements.run_monthly`, `legacy/db/init/04_pkg_statements.sql`, lines 79–83 (`COMMIT`; `WHEN OTHERS THEN ROLLBACK; RAISE;`).
- **Kind:** side-effect
- **Migration notes:** Like BR-ORD-12, transaction control is inside the procedure. The period-validation failure path (BR-STM-01) raises before any DML, so nothing needs rolling back there, but the handler still executes ROLLBACK — harmless in legacy, and the target's equivalent must likewise never leave a half-rebuilt period.

---

## ORDS facade — HTTP contract

Source: `legacy/ords/modules.sql`. Module `legacy.api`, base path `/legacy/` (schema URL mapping line 22). The header comment (lines 7–13) states the error contract the target must reproduce (mapped to RFC 7807 per FS-0005 — the status codes are the contract; the legacy body shape is recorded here for parity of the strangler's proxy phase).

### BR-API-01 — GET pricing/quote returns the full quote breakdown with quirky number formatting

- **Statement:** The quote endpoint echoes the inputs and returns list price, both discount percentages, the promo flag, unit price, and total as JSON numbers rendered with at least one and at most five decimal digits.
- **Source anchor:** `legacy.api` GET `pricing/quote` handler, `legacy/ords/modules.sql`, lines 39–61 (`n2j` helper lines 43–47).
- **Kind:** data-quirk
- **Migration notes:** JSON is hand-concatenated via `HTP.p`. Numbers go through `TO_CHAR(p,'FM999999999990.09999')` with a trailing-dot `RTRIM`: the first decimal position is forced, so integers render like `5.0`, and up to 5 significant decimals survive (list prices are 4-dp). `promo_applied` is a JSON **string** `"Y"`/`"N"`. Inputs arrive as untyped bind variables converted with `TO_NUMBER` — non-numeric query params raise a conversion error → 500 via BR-API-03. Success responses carry no explicit `:status_code`, i.e. 200.

### BR-API-02 — Quote: not-found maps to HTTP 404 with a fixed ORA-01403 body

- **Statement:** When the customer or product does not exist (or is inactive), the quote endpoint returns 404 with error code ORA-01403 and the message "customer or product not found".
- **Source anchor:** `legacy.api` GET `pricing/quote` handler, `legacy/ords/modules.sql`, lines 62–66.
- **Kind:** error-contract
- **Migration notes:** The 404 body hardcodes `"ORA-01403"` (with leading zero) — unlike the generic handler, which would render SQLCODE −1403 as `ORA-1403`. Which entity was missing is not distinguishable (see BR-PRC-02/03). Target must return 404 for inactive as well as missing entities.

### BR-API-03 — Quote: validation errors map to 400, everything else to 500

- **Statement:** Quote failures with codes ORA-20010 through ORA-20012 return HTTP 400; any other unexpected error returns HTTP 500; both carry the generic error body.
- **Source anchor:** `legacy.api` GET `pricing/quote` handler, `legacy/ords/modules.sql`, lines 67–71.
- **Kind:** error-contract
- **Migration notes:** `SQLCODE BETWEEN -20012 AND -20010` — the range is shared with the orders handler even though only −20010 is raised on the quote path today. Body shape per BR-API-09.

### BR-API-04 — POST orders success returns 201 with order id, literal status OPEN, and 1–2 dp total

- **Statement:** A successful order returns HTTP 201 with the new order id, a hardcoded status of "OPEN", and the total rendered with one or two decimal digits.
- **Source anchor:** `legacy.api` POST `orders` handler, `legacy/ords/modules.sql`, lines 85–92.
- **Kind:** data-quirk
- **Migration notes:** `status` is a string literal in the handler, not read back from the row (safe today since inserts are always OPEN). Total format `FM999999999990.09` forces the first decimal: `240` renders `240.0`, not `240.00`. No Location header is set; retrieval is via GET orders/:id.

### BR-API-05 — POST orders error mapping: credit→422, stock→409, not-found→404, validation→400, else 500

- **Statement:** Order failures map ORA-20001 (credit exceeded) to 422, ORA-20002 (insufficient stock) to 409, ORA-01403 (customer/product/stock row not found) to 404, ORA-20010..20012 to 400, and anything else to 500.
- **Source anchor:** `legacy.api` POST `orders` handler, `legacy/ords/modules.sql`, lines 93–104; contract restated in file header lines 7–13.
- **Kind:** error-contract
- **Migration notes:** This is the load-bearing status mapping of the whole strangler — the target must reproduce it exactly (FS-0005 maps the bodies to RFC 7807, statuses unchanged). The message text inside the body is the raw `SQLERRM` (e.g. `ORA-20001: CREDIT LIMIT EXCEEDED FOR CUSTOMER 3`) — uppercase, includes the id; consumers may have parsed it. Body shape per BR-API-09.

### BR-API-06 — GET orders/:id returns the order with a line array ordered by line number; no lines renders null

- **Statement:** Fetching an order returns its header fields, a date-only order date, and its lines sorted by line number — with the lines property null when the order has no lines.
- **Source anchor:** `legacy.api` GET `orders/:id` handler, `legacy/ords/modules.sql`, lines 114–140.
- **Kind:** data-quirk
- **Migration notes:** Built with `JSON_OBJECT`/`JSON_ARRAYAGG` (unlike the hand-built JSON elsewhere), so numeric formatting differs from the other endpoints (no forced decimal). `order_dt` is truncated to `YYYY-MM-DD` — the stored time-of-day is not exposed. `JSON_ARRAYAGG` over zero rows yields NULL → `"lines":null` (unreachable via place_order, which requires lines, but reachable for hand-crafted data). Non-numeric `:id` raises a conversion error with no handler (see BR-API-07).

### BR-API-07 — GET orders/:id: unknown order is 404; any other error falls to the ORDS default (500)

- **Statement:** Requesting a nonexistent order returns 404 with "order not found"; the handler catches nothing else, so other failures surface as ORDS's default 500.
- **Source anchor:** `legacy.api` GET `orders/:id` handler, `legacy/ords/modules.sql`, lines 141–146.
- **Kind:** error-contract
- **Migration notes:** Only `NO_DATA_FOUND` is handled (body hardcodes `"ORA-01403"`). A non-numeric id (`TO_NUMBER(:id)` at line 138) escapes the block unhandled — the response body/format for that case is ORDS-generated, not the packages' JSON error shape. Target: 404 body must match; the 500-path body is an accepted deviation candidate since legacy's is ORDS-internal.

### BR-API-08 — POST statements/run: bad period is 400, other failures 500; success echoes period and count

- **Statement:** The statement-run endpoint reads the period from the JSON body, returns the period and the number of statements generated on success, maps ORA-20003 to 400, and everything else to 500.
- **Source anchor:** `legacy.api` POST `statements/run` handler, `legacy/ords/modules.sql`, lines 155–170.
- **Kind:** error-contract
- **Migration notes:** Period is extracted with `JSON_VALUE(:body_text, '$.period')` — a missing key yields NULL, which fails the length check in BR-STM-01 → `ORA-20003` → 400 (so "no period supplied" and "bad period" are the same error). Success is HTTP 200 (no explicit status), body `{"period":"...","statements":N}` with the count as a bare number. This endpoint exposes a batch job over unauthenticated HTTP (see BR-API-10) — an operational hazard the target must gate deliberately.

### BR-API-09 — Error body shape: error_code "ORA<sqlcode>" plus sanitized 200-char message

- **Statement:** All handler-generated error bodies are a two-field JSON object: an error code formed from the Oracle SQLCODE and the error message truncated to 200 characters with double quotes replaced by apostrophes.
- **Source anchor:** `legacy/ords/modules.sql`, lines 70–71 (quote), 103–104 (orders), 168–169 (statements) — identical construction in each handler.
- **Kind:** error-contract
- **Migration notes:** `'ORA' || SQLCODE` — the negative sign supplies the hyphen, so codes render `ORA-20001` etc., but without zero-padding (contrast the hardcoded `ORA-01403` of the NDF handlers, BR-API-02/07). Sanitization only handles `"` — backslashes and control characters in a message would produce invalid JSON (no such messages exist in the current packages; latent quirk). FS-0005 converts this shape to RFC 7807 at the strangler boundary; until then, proxy parity requires byte-level reproduction.

### BR-API-10 — The API is unauthenticated

- **Statement:** All four endpoints are exposed without any authentication or authorization.
- **Source anchor:** `ORDS.ENABLE_SCHEMA(... p_auto_rest_auth => FALSE)`, `legacy/ords/modules.sql`, line 23; module published at lines 25–30.
- **Kind:** data-quirk
- **Migration notes:** Accidental-but-real contract: existing consumers send no credentials. The strangler proxy must pass traffic through unauthenticated to preserve behavior; introducing auth is a deliberate, separately-tracked breaking change, not a silent "fix".

---

## Architect review


> Status: **pending sign-off** — this footer was drafted in the build session;
> the architect's merge of the M0 PR constitutes the human decision (ADR-0004).

- **Verified:** rule count and kind distribution reviewed; TRUNC quirk
  (BR-PRC-11), the PLACE_ORDER side-effect set, and the full HTTP error
  mapping confirmed present with correct anchors.
- **Agent judgment calls, ratified as drafted:**
  1. Response-formatting behaviors classified as `data-quirk` rather than
     `error-contract` — endorsed; they are contract, but of the success path.
  2. The unauthenticated API catalogued as an implicit rule — endorsed and
     important: the target's default local profile must match (FS-0003 §5),
     with OAuth2 as an opt-in profile, or the strangler flip breaks consumers.
  3. ORDS-internal 500 on non-numeric `orders/{id}` marked accepted-deviation
     candidate — endorsed; goes to the FS-0005 tolerance contract as MAY
     differ (body), MUST match (status class).
- **Architect overrule:** none. The catalog stands as drafted.
