package com.fps4.pricing.statements;

import java.sql.SQLException;

import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * ADR-0003 lane 3 -- RETAIN as converted PL/pgSQL, thin wrapper.
 *
 * PKG_STATEMENTS.RUN_MONTHLY stays procedural database code
 * (db/migration/V2__plpgsql_statements.sql): the SCT-style conversion
 * carries the lowest change value, so the logic is replatformed, not
 * rewritten. TRANSITIONAL TIER -- its burn-down (collapse to one
 * set-based INSERT..SELECT) is planned in assessment/wave-plan.md.
 *
 * This wrapper only invokes the function and re-homes its SQLSTATE
 * P0003 (the re-encoded ORA-20003) into the service exception model.
 * The single SELECT is one implicit transaction: atomicity (BR-STM-08)
 * lives in the database, exactly as it did on Oracle.
 */
@Service
public class StatementService {

    private final JdbcTemplate jdbc;

    public StatementService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public StatementRunResult run(String period) {
        try {
            Integer count = jdbc.queryForObject(
                    "SELECT legacy.pkg_statements$run_monthly(?)", Integer.class, period);
            return new StatementRunResult(period, count);
        } catch (DataAccessException e) {
            for (Throwable t = e.getCause(); t != null; t = t.getCause()) {
                if (t instanceof SQLException sql && "P0003".equals(sql.getSQLState())) {
                    throw new BadPeriodException(period);                 // ORA-20003
                }
            }
            throw e;
        }
    }
}
