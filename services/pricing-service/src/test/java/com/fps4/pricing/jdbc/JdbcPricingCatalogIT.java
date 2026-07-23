package com.fps4.pricing.jdbc;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.fps4.pricing.AbstractPostgresIT;
import com.fps4.pricing.domain.PricingCatalog;
import com.fps4.pricing.domain.PricingService;
import com.fps4.pricing.domain.Promo;
import com.fps4.pricing.domain.Quote;

/**
 * Catalog adapter against the migrated anchor rows (Flyway V3): the
 * same pinned specimens scripts/smoke-legacy.sh checks on Oracle.
 */
class JdbcPricingCatalogIT extends AbstractPostgresIT {

    @Autowired
    private PricingCatalog catalog;

    @Autowired
    private PricingService pricing;

    @Test
    @DisplayName("anchor rows migrated: classes, 4dp list price, tier bands, evergreen promo")
    void anchorReferenceData() {
        assertThat(catalog.activeCustomerClass(1L)).contains("A");
        assertThat(catalog.activeCustomerClass(3L)).contains("C");
        assertThat(catalog.activeCustomerClass(999L)).isEmpty();

        assertThat(catalog.activeListPrice(1002L).orElseThrow())
                .isEqualByComparingTo("12.3456");            // the TRUNC specimen, 4dp intact

        assertThat(catalog.bestTierDiscount(1000L, 50L)).isEqualByComparingTo("10");
        assertThat(catalog.bestTierDiscount(1000L, 9L)).isEqualByComparingTo("0");
        assertThat(catalog.bestTierDiscount(1000L, 200L)).isEqualByComparingTo("15");

        Promo promo = catalog.currentPromo(1004L).orElseThrow();  // evergreen window
        assertThat(promo.promoPrice()).isEqualByComparingTo("19.9999");
        assertThat(catalog.currentPromo(1000L)).isEmpty();
    }

    @Test
    @DisplayName("end-to-end TRUNC anchor on PostgreSQL: cust 3 x product 1002 -> 12.34")
    void truncAnchorThroughRealCatalog() {
        Quote quote = pricing.quote(3L, 1002L, 1L);

        assertThat(quote.unitPrice()).isEqualByComparingTo("12.34");
        assertThat(quote.promoApplied()).isEqualTo("N");
    }

    @Test
    @DisplayName("promo anchor: product 1004, promo 19.9999 beats 24.68 -> Y, 19.99")
    void promoAnchorThroughRealCatalog() {
        Quote quote = pricing.quote(3L, 1004L, 1L);

        assertThat(quote.promoApplied()).isEqualTo("Y");
        assertThat(quote.unitPrice()).isEqualByComparingTo("19.99");
    }

    @Test
    @DisplayName("inactive product is invisible (BR-PRC-03)")
    void inactiveProductInvisible() {
        jdbc.update("""
                INSERT INTO legacy.products VALUES (7777, 'SKU-7777', 'DISCONTINUED WIDGET', 9.99, 'EA', 'INACTIVE')
                """);
        try {
            assertThat(catalog.activeListPrice(7777L)).isEmpty();
        } finally {
            jdbc.update("DELETE FROM legacy.products WHERE product_id = 7777");
        }
    }

    @Test
    @DisplayName("promo pick is deterministic by promo_id (BR-PRC-07 accepted deviation)")
    void promoPickDeterministic() {
        jdbc.update("""
                INSERT INTO legacy.promotions VALUES (900, 1002, 5.00, NULL, CURRENT_DATE - 1, CURRENT_DATE + 1)
                """);
        jdbc.update("""
                INSERT INTO legacy.promotions VALUES (901, 1002, 4.00, NULL, CURRENT_DATE - 1, CURRENT_DATE + 1)
                """);
        try {
            Promo promo = catalog.currentPromo(1002L).orElseThrow();
            assertThat(promo.promoPrice()).isEqualByComparingTo("5.00");  // lowest promo_id wins
        } finally {
            jdbc.update("DELETE FROM legacy.promotions WHERE promo_id IN (900, 901)");
        }
    }
}
