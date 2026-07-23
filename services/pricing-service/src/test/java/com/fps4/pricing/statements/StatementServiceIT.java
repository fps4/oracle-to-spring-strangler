package com.fps4.pricing.statements;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.fps4.pricing.AbstractPostgresIT;

/**
 * Retain-lane integration tests: the converted PL/pgSQL month-end run
 * (V2) behaves like PKG_STATEMENTS on the same inputs (BR-STM-01..08).
 * Uses the historic period 2025-03 no other test writes into.
 */
class StatementServiceIT extends AbstractPostgresIT {

    private static final String PERIOD = "2025-03";

    @Autowired
    private StatementService statements;

    @BeforeEach
    void seedHistoricOrders() {
        jdbc.update("DELETE FROM legacy.statements WHERE period = ?", PERIOD);
        jdbc.update("DELETE FROM legacy.order_lines WHERE order_id IN (91, 92, 93, 94)");
        jdbc.update("DELETE FROM legacy.orders WHERE order_id IN (91, 92, 93, 94)");
        // customer 1: one OPEN, one INVOICED, one CANCELLED (excluded);
        // customer 2: one SHIPPED. Customer 3: no activity -> no statement.
        jdbc.update("""
                INSERT INTO legacy.orders (order_id, customer_id, order_dt, status, total_amt) VALUES
                (91, 1, TIMESTAMP '2025-03-05 10:00:00', 'OPEN',      100.00),
                (92, 1, TIMESTAMP '2025-03-12 11:30:00', 'INVOICED',  250.50),
                (93, 1, TIMESTAMP '2025-03-20 09:15:00', 'CANCELLED',  75.00),
                (94, 2, TIMESTAMP '2025-03-28 16:45:00', 'SHIPPED',    60.25)
                """);
    }

    @Test
    @DisplayName("aggregation per status bucket; no-activity customers get no row (BR-STM-04/05)")
    void aggregatesPerCustomer() {
        StatementRunResult result = statements.run(PERIOD);

        assertThat(result.statements()).isEqualTo(2);

        Map<String, Object> cust1 = jdbc.queryForMap("""
                SELECT open_amt, invoiced_amt, order_cnt FROM legacy.statements
                 WHERE customer_id = 1 AND period = ?
                """, PERIOD);
        assertThat(cust1.get("open_amt").toString()).startsWith("100.00");
        assertThat(cust1.get("invoiced_amt").toString()).startsWith("250.50");
        assertThat(cust1.get("order_cnt")).isEqualTo(2);   // CANCELLED excluded

        assertThat(jdbc.queryForList(
                "SELECT customer_id FROM legacy.statements WHERE period = ?", Long.class, PERIOD))
                .containsExactlyInAnyOrder(1L, 2L);        // customer 3 absent
    }

    @Test
    @DisplayName("rerun-safe: second run wipes and rebuilds the period, new stmt ids (BR-STM-02/06)")
    void rerunWipesAndRebuilds() {
        statements.run(PERIOD);
        long firstId = jdbc.queryForObject(
                "SELECT stmt_id FROM legacy.statements WHERE customer_id = 1 AND period = ?",
                Long.class, PERIOD);

        StatementRunResult rerun = statements.run(PERIOD);

        assertThat(rerun.statements()).isEqualTo(2);
        long secondId = jdbc.queryForObject(
                "SELECT stmt_id FROM legacy.statements WHERE customer_id = 1 AND period = ?",
                Long.class, PERIOD);
        assertThat(secondId).isNotEqualTo(firstId);        // ids are not stable identifiers
    }

    @Test
    @DisplayName("audit row per run, even for a zero-statement period (BR-STM-07)")
    void auditRowEvenWhenEmpty() {
        StatementRunResult result = statements.run("1999-01");

        assertThat(result.statements()).isZero();
        long auditRows = jdbc.queryForObject("""
                SELECT count(*) FROM legacy.audit_log
                 WHERE module = 'PKG_STATEMENTS' AND action = 'RUN_MONTHLY'
                   AND details = 'period=1999-01 stmts=0'
                """, Long.class);
        assertThat(auditRows).isGreaterThanOrEqualTo(1);
    }

    @Test
    @DisplayName("two-layer period validation preserved (BR-STM-01): parse fail, length fail, null")
    void badPeriods() {
        assertThatExceptionOfType(BadPeriodException.class)     // fails the to_date layer
                .isThrownBy(() -> statements.run("2007-13"))
                .withMessage("BAD PERIOD: 2007-13");

        assertThatExceptionOfType(BadPeriodException.class)     // parses, fails the length layer
                .isThrownBy(() -> statements.run("2026-7"));

        assertThatExceptionOfType(BadPeriodException.class)     // missing key ([HAND-FIX 8])
                .isThrownBy(() -> statements.run(null));
    }

    @Test
    @DisplayName("failed run leaves the previous period intact (BR-STM-02/08)")
    void failedRunPreservesPreviousResult() {
        statements.run(PERIOD);
        long rowsBefore = jdbc.queryForObject(
                "SELECT count(*) FROM legacy.statements WHERE period = ?", Long.class, PERIOD);

        assertThatExceptionOfType(BadPeriodException.class)
                .isThrownBy(() -> statements.run("bogus"));

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM legacy.statements WHERE period = ?", Long.class, PERIOD))
                .isEqualTo(rowsBefore);
    }
}
