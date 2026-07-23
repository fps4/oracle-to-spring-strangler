package com.fps4.pricing.jdbc;

import java.math.BigDecimal;
import java.util.Optional;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import com.fps4.pricing.domain.PricingCatalog;
import com.fps4.pricing.domain.Promo;

/**
 * JDBC adapter for {@link PricingCatalog} against the converted schema
 * (Flyway V1). Queries are 1:1 with the cursors/selects inside
 * pkg_pricing.get_quote -- except the promo pick: legacy relies on an
 * unordered ROWNUM=1; here ORDER BY promo_id LIMIT 1 makes the choice
 * deterministic (BR-PRC-07, accepted deviation).
 */
@Repository
public class JdbcPricingCatalog implements PricingCatalog {

    private final JdbcTemplate jdbc;

    public JdbcPricingCatalog(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public Optional<String> activeCustomerClass(Long customerId) {
        return jdbc.query("""
                SELECT cust_class FROM legacy.customers
                 WHERE customer_id = ? AND status = 'ACTIVE'
                """, (rs, i) -> rs.getString(1), customerId)
                .stream().findFirst();
    }

    @Override
    public Optional<BigDecimal> activeListPrice(Long productId) {
        return jdbc.query("""
                SELECT list_price FROM legacy.products
                 WHERE product_id = ? AND status = 'ACTIVE'
                """, (rs, i) -> rs.getBigDecimal(1), productId)
                .stream().findFirst();
    }

    @Override
    public BigDecimal bestTierDiscount(Long productId, long qty) {
        return jdbc.query("""
                SELECT disc_pct FROM legacy.price_tiers
                 WHERE product_id = ? AND min_qty <= ?
                 ORDER BY min_qty DESC
                 LIMIT 1
                """, (rs, i) -> rs.getBigDecimal(1), productId, qty)
                .stream().findFirst().orElse(BigDecimal.ZERO);
    }

    @Override
    public Optional<Promo> currentPromo(Long productId) {
        // legacy window check is TRUNC(SYSDATE) BETWEEN start_dt AND end_dt
        return jdbc.query("""
                SELECT promo_price, promo_disc_pct FROM legacy.promotions
                 WHERE product_id = ?
                   AND CURRENT_DATE BETWEEN start_dt AND end_dt
                 ORDER BY promo_id
                 LIMIT 1
                """, (rs, i) -> new Promo(rs.getBigDecimal(1), rs.getBigDecimal(2)), productId)
                .stream().findFirst();
    }
}
