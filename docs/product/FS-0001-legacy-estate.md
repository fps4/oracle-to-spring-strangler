---
title: "FS-0001 — Legacy estate: Oracle XE + PL/SQL + ORDS"
status: draft
last_updated: 2026-07-22
owners: [architect]
related:
  - docs/product/00-product-intent.md
  - docs/design/decisions/0005-ords-facade-and-nginx-router.md
maestro:
  feature: legacy-estate
  kind: functional_spec
  summary: |
    The specimen: a containerized Oracle XE database with three authentically legacy PL/SQL
    packages (pricing, orders, statements) holding all business logic, seeded data, and an ORDS
    HTTP facade — the true shape of an APEX-era estate. Written in period style and then frozen:
    parity tests protect its behavior bug-for-bug.
---

# FS-0001 — Legacy estate

- **Status:** draft
- **Raised:** 2026-07-22
- **Owner:** @farid (architect)
- **Milestone:** M0

## Why

The migration story is only credible if the legacy is credible. A toy "SELECT *
FROM dual" backend convinces nobody; interviewers who have lived these estates
recognize the real thing: business logic buried in packages, side effects
everywhere, one quirk that production has depended on for a decade.

## Scope

1. **Oracle XE 21c in Docker** (`gvenzl/oracle-xe` image), schema user
   `LEGACY`, started by the root `docker compose up`.
2. **Domain schema** (wholesale orders & pricing):
   `CUSTOMERS`, `CREDIT_LIMITS`, `PRODUCTS`, `STOCK`, `PRICE_TIERS`,
   `PROMOTIONS`, `ORDERS`, `ORDER_LINES`, `STATEMENTS`, `AUDIT_LOG` —
   plus seed data (~50 customers, ~200 products, ~1k orders) generated
   deterministically (fixed seed) so parity corpora are reproducible.
3. **Three PL/SQL packages, period style** (cursor loops, `%TYPE`, package
   state, sparse comments, no unit tests — see AGENTS.md rule 4):
   - **`PKG_PRICING`** — `GET_QUOTE(p_customer_id, p_product_id, p_qty)`:
     tiered volume pricing, customer-class discount, promotion override,
     currency rounding via `TRUNC` (a deliberate half-down rounding quirk that
     parity must preserve — the "production depends on it" specimen).
   - **`PKG_ORDERS`** — `PLACE_ORDER(...)`: validation *with side effects* —
     credit-limit check, stock reservation `UPDATE`, `AUDIT_LOG` insert, all in
     one transaction; raises named exceptions (`E_CREDIT_EXCEEDED`,
     `E_INSUFFICIENT_STOCK`).
   - **`PKG_STATEMENTS`** — `RUN_MONTHLY(p_period)`: batch cursor-loop
     aggregation producing statement rows; the set-based-logic specimen.
4. **ORDS facade** exposing the packages as REST (the authentic APEX-estate
   HTTP shape): `GET /ords/legacy/pricing/quote`,
   `POST /ords/legacy/orders`, `GET /ords/legacy/orders/{id}`,
   `POST /ords/legacy/statements/run`.
5. **A frozen contract**: once M0 closes, `legacy/` changes only for bugs in
   *plumbing* (container/ORDS config), never in business behavior.

## Out of scope

- Any APEX UI (ORDS facade stands in for it; building APEX pages adds no
  reviewable value on GitHub).
- Mainframe/COBOL stubs (product intent: not a mainframe demo).
- Realistic data volume (seed size is demo-scale; volume claims would violate
  ADR-0004).

## Acceptance criteria (EARS)

- THE SYSTEM SHALL start Oracle XE, apply the LEGACY schema, load seed data,
  and serve all four ORDS endpoints from a single `docker compose up` on a
  clean machine.
- THE seed data SHALL be generated with a fixed random seed such that two
  clean startups produce identical data.
- WHEN `GET_QUOTE` computes a price ending in a half-cent, THE SYSTEM SHALL
  round half-down via `TRUNC` (the preserved quirk), and this behavior SHALL be
  covered by the parity corpus (FS-0005).
- WHEN `PLACE_ORDER` fails validation, THE SYSTEM SHALL leave stock,
  audit, and order tables unchanged (single-transaction semantics).
- AFTER milestone M0, THE business behavior of `legacy/` SHALL NOT change
  (frozen-specimen rule).

## Definition of done

- `make up && make smoke-legacy` passes on a clean machine.
- The three packages read as authentic period PL/SQL (review against
  AGENTS.md rule 4).
- ORDS endpoints documented in `legacy/README.md` with example curl calls.
