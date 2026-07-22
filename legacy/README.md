# legacy/ — the specimen (FS-0001)

Oracle XE 21c + three period-style PL/SQL packages + ORDS HTTP facade.
This is the **frozen legacy estate**: after M0, business behavior here never
changes (bugs included — parity protects them, see AGENTS.md rule 4).

## Layout

```
db/init/    schema, packages, deterministic seed — run by gvenzl image on first boot
  01_schema.sql          10 tables, sequences, indexes
  02_pkg_pricing.sql     PKG_PRICING  — GET_QUOTE, the TRUNC rounding quirk
  03_pkg_orders.sql      PKG_ORDERS   — PLACE_ORDER, one-transaction side effects
  04_pkg_statements.sql  PKG_STATEMENTS — RUN_MONTHLY, row-by-row batch
ords/       ORDS install entrypoint + REST module definitions
```

## Endpoints

Base URL: `http://localhost:8081/ords/legacy` (port 8081 in compose; the
strangler router in front arrives with M1). Substitute your Docker host if
using a remote `DOCKER_HOST`.

### GET /pricing/quote

```bash
curl "http://localhost:8081/ords/legacy/pricing/quote?customer_id=1&product_id=1000&qty=50"
# {"customer_id":1,...,"tier_disc_pct":10,"class_disc_pct":10,"promo_applied":"N","unit_price":16.19,"total":809.5}
```

The quirk specimen (list price 12.3456, no discounts — TRUNC gives 12.34
where ROUND would give 12.35; finance reconciles against truncation since
2009, so parity must preserve it):

```bash
curl "http://localhost:8081/ords/legacy/pricing/quote?customer_id=3&product_id=1002&qty=1"
# {"...":"...","unit_price":12.34,"total":12.34}
```

### POST /orders

```bash
curl -X POST -H 'Content-Type: application/json' \
  -d '{"customer_id":1,"lines":[{"product_id":1000,"qty":5}]}' \
  http://localhost:8081/ords/legacy/orders
# 201 {"order_id":101001,"status":"OPEN","total":89.95}
```

Error contract (the target's RFC 7807 mapping table starts here, FS-0005):

| Case | Legacy raises | HTTP |
|---|---|---|
| credit limit exceeded | `ORA-20001` (`E_CREDIT_EXCEEDED`) | 422 |
| insufficient stock | `ORA-20002` (`E_INSUFFICIENT_STOCK`) | 409 |
| bad statement period | `ORA-20003` | 400 |
| validation (qty, empty order) | `ORA-20010..20012` | 400 |
| unknown customer/product/order | `NO_DATA_FOUND` | 404 |

### GET /orders/{id}

```bash
curl http://localhost:8081/ords/legacy/orders/101001
# {"order_id":101001,"customer_id":1,"order_dt":"2026-07-22","status":"OPEN","total_amt":89.95,"lines":[...]}
```

### POST /statements/run

```bash
curl -X POST -H 'Content-Type: application/json' \
  -d '{"period":"2026-05"}' \
  http://localhost:8081/ords/legacy/statements/run
# {"period":"2026-05","statements":47}
```

## Seed determinism

`05_seed.sql` uses `DBMS_RANDOM.SEED(20260722)` — two clean startups
(`make clean && make up`) produce identical business data. Pinned anchor rows
(customers 1–3, products 1000–1004) back the smoke tests and the parity
corpus. The only nondeterminism: three evergreen promotions use
`TRUNC(SYSDATE)` windows so the promo path works on any calendar day
(dates differ between startups; prices don't).

## Notes

- The ORDS image comes from `container-registry.oracle.com/database/ords`
  — if the pull is denied, log in once with an Oracle account and accept
  the license: `docker login container-registry.oracle.com`.
- First boot is slow: Oracle XE initialization + ORDS metadata install
  (several minutes). `make smoke-legacy` waits for it.
- Lab credentials live in `docker-compose.yml` defaults; override with
  `ORACLE_PASSWORD` / `LEGACY_PASSWORD` env vars if you care.
