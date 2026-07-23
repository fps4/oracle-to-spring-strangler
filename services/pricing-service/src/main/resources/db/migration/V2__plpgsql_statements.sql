-- =====================================================================
--  V2 -- the RETAINED tier (ADR-0003 lane 3): PKG_STATEMENTS.RUN_MONTHLY
--  mechanically converted to PL/pgSQL, SCT-style.
--
--  TRANSITIONAL CODE, honestly labeled: this procedure body is kept as
--  procedural database code on purpose (highest-parity / lowest-change
--  lane). Its demolition is planned -- see assessment/wave-plan.md
--  "Burn-down note" (destination: one set-based INSERT..SELECT).
--
--  Conversion notes ([HAND-FIX n] tags) in docs/sct-notes.md:
--   - package flattening: PKG_STATEMENTS.RUN_MONTHLY -> pkg_statements$run_monthly
--     (SCT's package$subprogram naming convention)
--   - procedure with OUT param -> function returning the OUT value
--   - [HAND-FIX 5] RAISE_APPLICATION_ERROR(-20003) -> RAISE .. ERRCODE 'P0003'
--   - [HAND-FIX 6] COMMIT/ROLLBACK removed: caller owns the transaction
--   - [HAND-FIX 7] DECODE -> CASE (no aws_oracle_ext dependency)
--  Source of truth: legacy/db/init/04_pkg_statements.sql (frozen specimen).
-- =====================================================================

CREATE OR REPLACE FUNCTION legacy.pkg_statements$run_monthly(
    p_period    varchar
) RETURNS integer
LANGUAGE plpgsql
AS $body$
DECLARE
    x_stmt_cnt  integer;
    l_open      numeric;
    l_invoiced  numeric;
    l_cnt       integer;
    l_dummy     timestamp;
    r           record;
BEGIN
    -- [HAND-FIX 8] Oracle: NULL || '-01' = '-01', so a missing period
    -- fails the to_date check below. PostgreSQL: NULL || '-01' IS NULL
    -- and to_date(NULL) is silently NULL -- without this guard a null
    -- period would sail through both checks and "succeed" with 0 rows.
    IF p_period IS NULL THEN
        RAISE EXCEPTION 'BAD PERIOD: ' USING ERRCODE = 'P0003';
    END IF;

    -- period sanity check (two layers, kept bug-for-bug: BR-STM-01)
    BEGIN
        l_dummy := to_date(p_period || '-01', 'YYYY-MM-DD');
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'BAD PERIOD: %', p_period USING ERRCODE = 'P0003';
    END;
    IF length(p_period) != 7 OR substr(p_period, 5, 1) != '-' THEN
        RAISE EXCEPTION 'BAD PERIOD: %', p_period USING ERRCODE = 'P0003';
    END IF;

    -- rerun-safe: wipe the period first (BR-STM-02)
    DELETE FROM legacy.statements WHERE period = p_period;

    x_stmt_cnt := 0;

    FOR r IN SELECT customer_id
               FROM legacy.customers
              WHERE status = 'ACTIVE'
              ORDER BY customer_id
    LOOP
        SELECT coalesce(sum(CASE status WHEN 'OPEN'     THEN total_amt
                                        WHEN 'SHIPPED'  THEN total_amt
                                        ELSE 0 END), 0),
               coalesce(sum(CASE status WHEN 'INVOICED' THEN total_amt
                                        ELSE 0 END), 0),
               count(*)
          INTO l_open, l_invoiced, l_cnt
          FROM legacy.orders
         WHERE customer_id = r.customer_id
           AND to_char(order_dt, 'YYYY-MM') = p_period
           AND status != 'CANCELLED';

        -- no activity, no statement (BR-STM-05)
        IF l_cnt > 0 THEN
            INSERT INTO legacy.statements
                (stmt_id, customer_id, period, open_amt, invoiced_amt,
                 order_cnt, run_dt)
            VALUES
                (nextval('legacy.seq_statements'), r.customer_id, p_period,
                 l_open, l_invoiced, l_cnt, LOCALTIMESTAMP(0));
            x_stmt_cnt := x_stmt_cnt + 1;
        END IF;
    END LOOP;

    INSERT INTO legacy.audit_log (audit_id, module, action, ref_id, details)
    VALUES (nextval('legacy.seq_audit'), 'PKG_STATEMENTS', 'RUN_MONTHLY', NULL,
            'period=' || p_period || ' stmts=' || x_stmt_cnt);

    RETURN x_stmt_cnt;
END;
$body$;
