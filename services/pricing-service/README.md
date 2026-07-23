# pricing-service

The one target service of the strangler migration (ADR-0002), Spring
Boot 3 / Java 21 / PostgreSQL 16. Its centerpiece is the **three-way
PL/SQL placement** (ADR-0003) — each legacy package lands by a
different, documented lane:

| Legacy module | Lane | Lands as |
|---|---|---|
| `PKG_PRICING` | Extract → Java | [`domain/PricingService`](src/main/java/com/fps4/pricing/domain/PricingService.java) — pure, framework-free, TRUNC quirk regression-pinned |
| `PKG_ORDERS` | Translate → SQL | [`orders/OrderService`](src/main/java/com/fps4/pricing/orders/OrderService.java) — JdbcTemplate in one `@Transactional`, loop-shaped like the original |
| `PKG_STATEMENTS` | Retain → PL/pgSQL | [`V2__plpgsql_statements.sql`](src/main/resources/db/migration/V2__plpgsql_statements.sql) + [`statements/StatementService`](src/main/java/com/fps4/pricing/statements/StatementService.java) wrapper — **transitional tier**, burn-down in `assessment/wave-plan.md` |

Schema: Flyway only (V1 = converted schema, V2 = retained procedure,
V3 = anchor reference data). Conversion receipts: [`docs/sct-notes.md`](docs/sct-notes.md).

## Build & test

```bash
./mvnw verify        # unit + web-slice + Testcontainers PostgreSQL (Docker required, no H2)
```

## Run

Normally via compose at the repo root (`make up`). Standalone:

```bash
docker compose up -d postgres
./mvnw spring-boot:run
```

Default profile: security disabled (local-first, ADR-0001; the legacy
facade is unauthenticated and the router must stay stack-transparent).
`--spring.profiles.active=oauth2` turns on JWT validation against
`OAUTH2_ISSUER_URI`.

Surfaces: `/api/pricing/quote`, `/api/orders`, `/api/statements/run`,
`/v3/api-docs` (+ swagger-ui), `/actuator/health/{liveness,readiness}`,
`/actuator/prometheus`.
