-- PKG_STATEMENTS -- month end run. Scheduled 03:00 first Sunday (see cron on ORAPRD02).
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = legacy;

CREATE OR REPLACE PACKAGE pkg_statements AS

    E_BAD_PERIOD    EXCEPTION;
    PRAGMA EXCEPTION_INIT(E_BAD_PERIOD, -20003);

    PROCEDURE run_monthly (
        p_period    IN  VARCHAR2,           -- 'YYYY-MM'
        x_stmt_cnt  OUT NUMBER
    );

END pkg_statements;
/

CREATE OR REPLACE PACKAGE BODY pkg_statements AS

    PROCEDURE run_monthly (
        p_period    IN  VARCHAR2,
        x_stmt_cnt  OUT NUMBER
    ) IS
        CURSOR c_cust IS
            SELECT customer_id
              FROM customers
             WHERE status = 'ACTIVE'
             ORDER BY customer_id;

        l_open      NUMBER;
        l_invoiced  NUMBER;
        l_cnt       NUMBER;
        l_dummy     DATE;
    BEGIN
        -- period sanity check (added after the '2007-13' incident)
        BEGIN
            l_dummy := TO_DATE(p_period || '-01', 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(-20003, 'BAD PERIOD: ' || p_period);
        END;
        IF LENGTH(p_period) != 7 OR SUBSTR(p_period, 5, 1) != '-' THEN
            RAISE_APPLICATION_ERROR(-20003, 'BAD PERIOD: ' || p_period);
        END IF;

        -- rerun-safe: wipe the period first
        DELETE FROM statements WHERE period = p_period;

        x_stmt_cnt := 0;

        FOR r IN c_cust LOOP
            SELECT NVL(SUM(DECODE(status, 'OPEN', total_amt,
                                          'SHIPPED', total_amt, 0)), 0),
                   NVL(SUM(DECODE(status, 'INVOICED', total_amt, 0)), 0),
                   COUNT(*)
              INTO l_open, l_invoiced, l_cnt
              FROM orders
             WHERE customer_id = r.customer_id
               AND TO_CHAR(order_dt, 'YYYY-MM') = p_period
               AND status != 'CANCELLED';

            -- no activity, no statement (customers complained about
            -- zero statements in the post, 2008)
            IF l_cnt > 0 THEN
                INSERT INTO statements
                    (stmt_id, customer_id, period, open_amt, invoiced_amt,
                     order_cnt, run_dt)
                VALUES
                    (seq_statements.NEXTVAL, r.customer_id, p_period, l_open,
                     l_invoiced, l_cnt, SYSDATE);
                x_stmt_cnt := x_stmt_cnt + 1;
            END IF;
        END LOOP;

        INSERT INTO audit_log (audit_id, module, action, ref_id, details)
        VALUES (seq_audit.NEXTVAL, 'PKG_STATEMENTS', 'RUN_MONTHLY', NULL,
                'period=' || p_period || ' stmts=' || x_stmt_cnt);

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END run_monthly;

END pkg_statements;
/
SHOW ERRORS
