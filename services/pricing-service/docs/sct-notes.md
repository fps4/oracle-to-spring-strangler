---
title: Schema & PL/SQL conversion notes (Oracle 21c -> PostgreSQL 16)
status: draft
last_updated: 2026-07-23
owners: [architect]
related:
  - docs/product/FS-0003-target-service.md
  - services/pricing-service/src/main/resources/db/migration/V1__converted_schema.sql
  - services/pricing-service/src/main/resources/db/migration/V2__plpgsql_statements.sql
---

# Conversion notes: LEGACY schema -> Flyway V1/V2

## How this conversion was actually performed (ADR-0004 honesty note)

FS-0003 calls V1 "the AWS SCT-converted LEGACY schema". **AWS SCT was
not executed in this lab** (it needs a live Oracle endpoint plus AWS
tooling that adds nothing reviewable to a GitHub repo). The conversion
was performed AI-assisted in this build session by applying SCT's
*documented* conversion rules, then hand-fixing the places where the
mechanical rule produces wrong or unusable output. Every fix below is a
real, documented SCT/DMS behavior — they are the talking points the
spec asks for — but the receipts are the rule citations and the diffs,
not an SCT report. Proposed spec amendment: FS-0003 wording
"SCT-converted" -> "SCT-style conversion (rules applied and documented,
tool not run)".

## Type mapping (V1)

| Oracle | Mechanical SCT output | Kept / hand-fixed |
|---|---|---|
| `NUMBER(10)` / `NUMBER(12)` ids | `numeric(10,0)` / `numeric(12,0)` | **[HAND-FIX 1]** ids to `bigint` (`NUMBER(4)` line_no -> `smallint`): decimal ids waste storage, defeat index-friendly int ops, and leak `.0` into JDBC `getObject` reads |
| `NUMBER(p,s)` money/pcts | `numeric(p,s)` | kept — exact decimal is the point; `list_price numeric(9,4)` preserves the 4-dp TRUNC-quirk source |
| `VARCHAR2(n)` | `varchar(n)` | kept (byte-vs-char length semantics differ, but the seed data is ASCII by CI rule) |
| `DATE` | `timestamp(0)` | **[HAND-FIX 2]** kept `timestamp(0)`, resisted the "obvious" `date`: Oracle `DATE` carries time-of-day; `order_dt` month-bucketing and audit ordering depend on it. Classic DMS data-loss trap. |
| `DEFAULT SYSDATE` | `aws_oracle_ext.sysdate()` | **[HAND-FIX 3]** `LOCALTIMESTAMP` — the aws_oracle_ext emulation extension is an RDS-ism; a vanilla PG 16 must boot this schema. (`now()` would be transaction-start time; SYSDATE is statement time; for defaults the difference is immaterial and noted.) |
| `DEFAULT USER` | `aws_oracle_ext` user emulation | **[HAND-FIX 4]** `current_user` |
| `SEQUENCE ... NOCACHE` | sequence + cache clause | `NOCACHE` dropped: PG default is `CACHE 1`, same semantics |

## PKG_STATEMENTS conversion (V2, the retained tier)

- **Package flattening:** SCT's `package$subprogram` convention kept:
  `pkg_statements$run_monthly`. `$` is legal in unquoted PG identifiers.
- **Procedure -> function:** OUT parameter `x_stmt_cnt` becomes the
  return value (SCT's classic pre-PG11 conversion; also lets the thin
  wrapper call it as one `SELECT`).
- **[HAND-FIX 5] RAISE_APPLICATION_ERROR(-20003):** the mechanical
  conversion loses the -20003 error number. Re-encoded as SQLSTATE
  `P0003`; the Java wrapper maps `P0003` back onto the legacy HTTP
  contract (400). Same message text (`BAD PERIOD: <p>`).
- **[HAND-FIX 6] COMMIT/ROLLBACK removed:** PG functions cannot commit;
  the transaction belongs to the caller (here: the single-statement
  wrapper call — atomicity preserved, BR-STM-08).
- **[HAND-FIX 7] DECODE -> CASE:** avoids the `aws_oracle_ext.decode`
  dependency SCT would emit.
- **[HAND-FIX 8] NULL-concat semantics — a genuine cross-DB bug:**
  Oracle `NULL || '-01'` = `'-01'`, so a missing period fails
  `TO_DATE` and raises BAD PERIOD. PostgreSQL `NULL || '-01'` IS NULL,
  and `to_date(NULL)` is silently NULL — the mechanically-converted
  guard would *pass* a null period and "succeed" with 0 statements.
  An explicit `IS NULL` guard restores the legacy behavior. This is
  the kind of silent behavior change parity testing (FS-0005) exists
  to catch.

## Reference data (V3)

Not an SCT concern, but part of the schema story: V3 carries the
hand-pinned anchor rows only, honestly labeled as the stand-in for a
DMS full load. The Oracle-side DBMS_RANDOM bulk history is not
reproducible in PG and is deferred to the M2 parity / M3 data-sync
narrative. Evergreen promo windows anchor on `CURRENT_DATE` at
migration time, mirroring the seed's `TRUNC(SYSDATE)` exception.
