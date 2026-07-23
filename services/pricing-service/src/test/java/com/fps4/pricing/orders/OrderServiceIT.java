package com.fps4.pricing.orders;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.fps4.pricing.AbstractPostgresIT;
import com.fps4.pricing.domain.LegacyNotFoundException;

/**
 * Translate-lane integration tests against real PostgreSQL. The
 * rollback cases are the FS-0003 acceptance criterion: WHEN order
 * placement fails, all writes (order, lines, stock, audit) roll back.
 * Tests are deliberately NOT @Transactional -- the service must own
 * its transaction for the rollback to be observable.
 */
class OrderServiceIT extends AbstractPostgresIT {

    @Autowired
    private OrderService orders;

    private long count(String sql, Object... args) {
        return jdbc.queryForObject(sql, Long.class, args);
    }

    @Test
    @DisplayName("happy path: order, 1-based lines, stock reservation, audit row -- all committed")
    void happyPath() {
        long reservedBefore = count("SELECT qty_reserved FROM legacy.stock WHERE product_id = 1000");

        PlacedOrder placed = orders.place(1L, List.of(new OrderLine(1000L, 5L)));

        // customer 1 is class A: 19.99 * 0.9 -> 17.99 truncated, x5 = 89.95
        assertThat(placed.status()).isEqualTo("OPEN");
        assertThat(placed.total()).isEqualByComparingTo("89.95");

        Map<String, Object> order = jdbc.queryForMap(
                "SELECT status, total_amt FROM legacy.orders WHERE order_id = ?", placed.orderId());
        assertThat(order.get("status")).isEqualTo("OPEN");
        assertThat((BigDecimal) order.get("total_amt")).isEqualByComparingTo("89.95");

        Map<String, Object> line = jdbc.queryForMap(
                "SELECT line_no, qty, unit_price, line_amt FROM legacy.order_lines WHERE order_id = ?",
                placed.orderId());
        assertThat(line.get("line_no")).isEqualTo(1);                  // 1-based, BR-ORD-10
        assertThat((BigDecimal) line.get("unit_price")).isEqualByComparingTo("17.99");
        assertThat((BigDecimal) line.get("line_amt")).isEqualByComparingTo("89.95");

        assertThat(count("SELECT qty_reserved FROM legacy.stock WHERE product_id = 1000"))
                .isEqualTo(reservedBefore + 5);                        // BR-ORD-08: reserved, on-hand untouched

        String details = jdbc.queryForObject("""
                SELECT details FROM legacy.audit_log
                 WHERE module = 'PKG_ORDERS' AND action = 'ORDER_PLACED' AND ref_id = ?
                """, String.class, placed.orderId());
        assertThat(details).isEqualTo("cust=1 total=89.95 lines=1");   // BR-ORD-11
    }

    @Test
    @DisplayName("ROLLBACK: stock failure on line 2 leaves NO order, NO lines, NO reservation from line 1, NO audit")
    void failedOrderLeavesNothing() {
        long ordersBefore = count("SELECT count(*) FROM legacy.orders WHERE customer_id = 2");
        long reserved1001 = count("SELECT qty_reserved FROM legacy.stock WHERE product_id = 1001");
        long auditBefore = count("SELECT count(*) FROM legacy.audit_log WHERE module = 'PKG_ORDERS'");

        // line 1 reserves fine; line 2 hits the low-stock specimen (5 on hand)
        assertThatExceptionOfType(InsufficientStockException.class)
                .isThrownBy(() -> orders.place(2L, List.of(
                        new OrderLine(1001L, 10L),
                        new OrderLine(1003L, 100L))))
                .withMessage("INSUFFICIENT STOCK FOR PRODUCT 1003");

        // nothing survives a failed order (helpdesk #3302 / BR-ORD-12)
        assertThat(count("SELECT count(*) FROM legacy.orders WHERE customer_id = 2"))
                .isEqualTo(ordersBefore);
        assertThat(count("SELECT qty_reserved FROM legacy.stock WHERE product_id = 1001"))
                .isEqualTo(reserved1001);
        assertThat(count("SELECT count(*) FROM legacy.audit_log WHERE module = 'PKG_ORDERS'"))
                .isEqualTo(auditBefore);
    }

    @Test
    @DisplayName("credit limit: strict > boundary -- exactly on the limit is accepted (BR-ORD-05)")
    void creditBoundaryIsStrict() {
        // customer 3 (class C, limit 500, no seeded orders): 25 boxes at
        // 19.99 with the 10-49 tier (5%) = 18.99 * 25 = 474.75 -- inside;
        // then a second order pushing exposure over 500 must 422.
        PlacedOrder first = orders.place(3L, List.of(new OrderLine(1000L, 25L)));
        assertThat(first.total()).isEqualByComparingTo("474.75");

        assertThatExceptionOfType(CreditLimitExceededException.class)
                .isThrownBy(() -> orders.place(3L, List.of(new OrderLine(1000L, 2L))))
                .withMessage("CREDIT LIMIT EXCEEDED FOR CUSTOMER 3");

        // cleanup: release the exposure so other tests see customer 3 pristine
        jdbc.update("DELETE FROM legacy.order_lines WHERE order_id = ?", first.orderId());
        jdbc.update("DELETE FROM legacy.orders WHERE order_id = ?", first.orderId());
        jdbc.update("UPDATE legacy.stock SET qty_reserved = qty_reserved - 25 WHERE product_id = 1000");
    }

    @Test
    @DisplayName("empty order -> ORA-20012 before any lookup (BR-ORD-01)")
    void emptyOrder() {
        assertThatExceptionOfType(EmptyOrderException.class)
                .isThrownBy(() -> orders.place(1L, List.of()));
    }

    @Test
    @DisplayName("missing customer_id degrades to 404 like the legacy JSON path (BR-ORD-13)")
    void nullCustomerIsNotFound() {
        assertThatExceptionOfType(LegacyNotFoundException.class)
                .isThrownBy(() -> orders.place(null, List.of(new OrderLine(1000L, 1L))));
    }
}
