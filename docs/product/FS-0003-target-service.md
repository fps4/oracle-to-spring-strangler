---
title: "FS-0003 — Target service: Spring Boot 3 + PostgreSQL, three-way logic placement"
status: draft
last_updated: 2026-07-22
owners: [architect]
related:
  - docs/product/00-product-intent.md
  - docs/design/decisions/0002-one-domain-one-service.md
  - docs/design/decisions/0003-three-way-plsql-placement.md
maestro:
  feature: target-service
  kind: functional_spec
  summary: |
    One Spring Boot 3 / Java 21 service (pricing-service) on PostgreSQL, implementing the
    centerpiece decision: the three migrated PL/SQL modules land three different ways — pricing
    extracted to a tested Java service, order placement translated to set-based SQL via
    JdbcTemplate, statements retained as SCT-converted PL/pgSQL called through a thin wrapper —
    each path carrying its ADR rationale. Flyway owns the converted schema; Testcontainers, not
    H2, backs the tests.
---

# FS-0003 — Target service

- **Status:** draft
- **Raised:** 2026-07-22
- **Owner:** @farid (architect)
- **Milestone:** M1

## Why

The architect question in every one of these engagements is *where does the
PL/SQL logic go*. Implementing all three answers in one small service — with
the trade-off written down per module — demonstrates migration judgment that a
single-approach port cannot. It also converts the owner's Spring Boot claim
from design-review level to honestly-demoable (the wiki guide's §8 build,
subsumed here with a better story).

## Scope

1. **`services/pricing-service`** — Spring Boot 3.x, Java 21, Maven
   (`mvnw` wrapper), PostgreSQL 16.
2. **Flyway** migrations: `V1__converted_schema.sql` is the AWS
   SCT-converted LEGACY schema (conversion documented in
   `services/pricing-service/docs/sct-notes.md`, including what SCT got wrong
   and was hand-fixed — a genuine SCT/DMS talking point); `V2__plpgsql_statements.sql`
   carries the retained converted procedure.
3. **Three-way logic placement** (ADR-0003), one module each:
   - **Extract → Java**: `GET /api/pricing/quote` — the `PKG_PRICING` rules as
     a pure, unit-tested `PricingService` (constructor-injected, no framework
     in the domain logic); the TRUNC quirk reproduced deliberately and
     regression-pinned by a golden-master test.
   - **Translate → set-based SQL**: `POST /api/orders` — `PKG_ORDERS`
     validation + side effects as `JdbcTemplate` statements inside one
     `@Transactional` service method (transaction boundary at the service
     layer; a test proves rollback leaves no partial writes).
   - **Retain → PL/pgSQL**: `POST /api/statements/run` — the converted
     `RUN_MONTHLY` procedure called via a thin wrapper; marked in code and docs
     as a transitional tier with its burn-down noted in the wave plan.
4. **API layer per the owner's standards**: DTOs at the boundary (no entity
   leakage), Jakarta validation, `@RestControllerAdvice` with RFC 7807
   problem responses, springdoc-generated OpenAPI.
5. **Security**: OAuth2 resource-server profile validating JWTs against a dev
   tenant (issuer configurable; disabled in the default local profile so
   `compose up` needs no external account).
6. **Production-readiness surface**: Actuator health groups (liveness/
   readiness), Micrometer/Prometheus endpoint, graceful shutdown,
   container image built with `MaxRAMPercentage` (not fixed `-Xmx`).
7. **Tests**: unit (JUnit 5 + Mockito) for `PricingService`; `@WebMvcTest`
   for the API layer; **Testcontainers PostgreSQL** for repository/
   transactional tests. No H2.

## Out of scope

- A second service, Kafka, Spring Cloud components (ADR-0002; K8s + the
  strangler router provide the platform concerns).
- JPA-based rewrite of the orders module (the point of that module is the
  set-based translation path; adding JPA would blur the demo).
- Performance/load testing (would invite claims ADR-0004 forbids).

## Acceptance criteria (EARS)

- THE three endpoints SHALL be behaviorally equivalent to their ORDS
  counterparts as defined by the parity contract (FS-0005), including the
  TRUNC rounding quirk.
- WHEN order placement fails validation, THE SYSTEM SHALL roll back all
  writes (stock, audit, order) — proven by a Testcontainers test.
- THE Flyway history SHALL be the only mechanism that creates or alters
  schema, and V1 SHALL be traceable to the SCT conversion notes.
- THE default local profile SHALL run with security disabled and NO external
  dependencies; THE `oauth2` profile SHALL validate JWTs against a
  configurable issuer.
- THE API SHALL expose DTOs only (no persistence types), SHALL return RFC
  7807 problem responses on errors, and SHALL serve a generated OpenAPI
  document.
- ALL DB-touching tests SHALL run against Testcontainers PostgreSQL.

## Definition of done

- `./mvnw verify` green on a clean machine with Docker.
- Each of the three modules carries a short header comment linking its
  ADR-0003 lane and rationale.
- `sct-notes.md` documents at least two real SCT conversion issues and their
  hand-fixes.
