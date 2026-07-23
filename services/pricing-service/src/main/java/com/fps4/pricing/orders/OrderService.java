package com.fps4.pricing.orders;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fps4.pricing.domain.LegacyNotFoundException;
import com.fps4.pricing.domain.PricingService;
import com.fps4.pricing.domain.Quote;

/**
 * ADR-0003 lane 2 -- TRANSLATE to SQL under {@code @Transactional}.
 *
 * PKG_ORDERS.PLACE_ORDER (legacy/db/init/03_pkg_orders.sql) translated
 * to JdbcTemplate statements inside one service-level transaction: the
 * logic is SQL-shaped with transactional side effects, and plain SQL
 * stays truer to the original behavior than ORM entities would. The
 * translation is deliberately loop-shaped, NOT one set-based statement
 * (classification caveat): per-line pessimistic locks in input order,
 * per-line failure identity.
 *
 * Nothing survives a failed order (helpdesk #3302 / BR-ORD-12): a
 * runtime exception rolls back the order header, lines, stock
 * reservations and audit row together -- pinned by a Testcontainers
 * test (FS-0003 acceptance).
 *
 * Deliberate deviation: legacy prices every line TWICE (once in the
 * credit pass, again in the insert loop). Pricing is deterministic
 * within the transaction, so the target prices once and reuses the
 * quote (BR-ORD-09, accepted deviation for the parity contract).
 */
@Service
public class OrderService {

    private final JdbcTemplate jdbc;
    private final PricingService pricing;

    public OrderService(JdbcTemplate jdbc, PricingService pricing) {
        this.jdbc = jdbc;
        this.pricing = pricing;
    }

    @Transactional
    public PlacedOrder place(Long customerId, List<OrderLine> lines) {
        if (lines.isEmpty()) {
            throw new EmptyOrderException();                              // ORA-20012
        }

        BigDecimal creditLimit = jdbc.query("""
                SELECT cl.credit_limit
                  FROM legacy.credit_limits cl
                  JOIN legacy.customers c ON c.customer_id = cl.customer_id
                 WHERE c.customer_id = ? AND c.status = 'ACTIVE'
                """, (rs, i) -> rs.getBigDecimal(1), customerId)
                .stream().findFirst()
                .orElseThrow(LegacyNotFoundException::noDataFound);       // BR-ORD-02

        // price all lines first (quote logic is THE single source, RT-2203)
        List<Quote> quotes = new ArrayList<>(lines.size());
        BigDecimal total = BigDecimal.ZERO;
        for (OrderLine line : lines) {
            Quote quote = pricing.quote(customerId, line.productId(), line.qty());
            quotes.add(quote);
            total = total.add(quote.total());
        }

        // credit check: open + shipped exposure counts, invoiced does not
        // (BR-ORD-04; unlocked read, strict > boundary per BR-ORD-05)
        BigDecimal outstanding = jdbc.queryForObject("""
                SELECT coalesce(sum(total_amt), 0) FROM legacy.orders
                 WHERE customer_id = ? AND status IN ('OPEN', 'SHIPPED')
                """, BigDecimal.class, customerId);
        if (outstanding.add(total).compareTo(creditLimit) > 0) {
            throw new CreditLimitExceededException(customerId);           // ORA-20001
        }

        long orderId = jdbc.queryForObject("SELECT nextval('legacy.seq_orders')", Long.class);
        jdbc.update("""
                INSERT INTO legacy.orders (order_id, customer_id, order_dt, status, total_amt)
                VALUES (?, ?, LOCALTIMESTAMP(0), 'OPEN', ?)
                """, orderId, customerId, total);

        for (int i = 0; i < lines.size(); i++) {
            OrderLine line = lines.get(i);

            // reserve stock, row-locked (SELECT .. FOR UPDATE as in legacy)
            StockRow stock = jdbc.query("""
                    SELECT qty_on_hand, qty_reserved FROM legacy.stock
                     WHERE product_id = ? FOR UPDATE
                    """, (rs, n) -> new StockRow(rs.getLong(1), rs.getLong(2)), line.productId())
                    .stream().findFirst()
                    .orElseThrow(LegacyNotFoundException::noDataFound);
            if (stock.onHand() - stock.reserved() < line.qty()) {
                throw new InsufficientStockException(line.productId());   // ORA-20002
            }
            jdbc.update("""
                    UPDATE legacy.stock
                       SET qty_reserved = qty_reserved + ?, updated_dt = LOCALTIMESTAMP(0)
                     WHERE product_id = ?
                    """, line.qty(), line.productId());

            Quote quote = quotes.get(i);                                  // priced once, see class doc
            jdbc.update("""
                    INSERT INTO legacy.order_lines (order_id, line_no, product_id, qty, unit_price, line_amt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, orderId, i + 1, line.productId(), line.qty(),
                    quote.unitPrice(), quote.total());                    // 1-based line_no, BR-ORD-10
        }

        jdbc.update("""
                INSERT INTO legacy.audit_log (audit_id, module, action, ref_id, details)
                VALUES (nextval('legacy.seq_audit'), 'PKG_ORDERS', 'ORDER_PLACED', ?, ?)
                """, orderId,
                // BR-ORD-11: 'cust=<id> total=<n> lines=<n>' with Oracle's
                // number-to-text rendering (no trailing zeros: 500.00 -> 500)
                "cust=" + customerId + " total=" + legacyNumber(total) + " lines=" + lines.size());

        return new PlacedOrder(orderId, "OPEN", total);
    }

    /** Oracle renders NUMBER in string concat without trailing zeros. */
    static String legacyNumber(BigDecimal value) {
        return value.stripTrailingZeros().toPlainString();
    }

    private record StockRow(long onHand, long reserved) {
    }
}
