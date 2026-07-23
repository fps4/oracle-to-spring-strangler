package com.fps4.pricing.domain;

import java.math.BigDecimal;
import java.util.Optional;

/**
 * Read-only port for the reference data get_quote consumed directly
 * from tables (customers, products, price_tiers, promotions). Keeps
 * {@link PricingService} framework- and JDBC-free (FS-0003 scope 3).
 * Ids are boxed on purpose: a null id must degrade like the legacy
 * NO_DATA_FOUND path (404), not throw an NPE.
 */
public interface PricingCatalog {

    /** cust_class of an ACTIVE customer. */
    Optional<String> activeCustomerClass(Long customerId);

    /** list_price of an ACTIVE product. */
    Optional<BigDecimal> activeListPrice(Long productId);

    /** Best matching volume tier (max min_qty &lt;= qty); ZERO if none. */
    BigDecimal bestTierDiscount(Long productId, long qty);

    /** The one promotion in whose window today falls, if any. */
    Optional<Promo> currentPromo(Long productId);
}
