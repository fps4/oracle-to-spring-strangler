package com.fps4.pricing.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Map;

/**
 * ADR-0003 lane 1 -- EXTRACT to Java.
 *
 * PKG_PRICING.GET_QUOTE (legacy/db/init/02_pkg_pricing.sql) extracted
 * as a pure, constructor-injected domain service: the domain is under
 * active redesign, the rules are branchy and unit-testable, and this
 * is their best long-term home. No framework types in here.
 *
 * Behavior is preserved bug-for-bug per the business-rule catalog
 * (assessment/business-rule-catalog.md, BR-PRC-01..12) -- above all
 * the TRUNC rounding quirk (BR-PRC-11), which finance reconciles
 * against (helpdesk #4711, Aug 2009). Deliberate deviation: the legacy
 * promo pick is an unordered ROWNUM=1; the catalog port returns a
 * deterministic choice instead (BR-PRC-07, accepted deviation for the
 * parity contract).
 */
public class PricingService {

    /** Hardcoded class discounts, as in the package init block (BR-PRC-05). */
    private static final Map<String, BigDecimal> CLASS_DISC = Map.of(
            "A", BigDecimal.TEN,
            "B", new BigDecimal("5"),
            "C", BigDecimal.ZERO);

    private final PricingCatalog catalog;

    public PricingService(PricingCatalog catalog) {
        this.catalog = catalog;
    }

    public Quote quote(Long customerId, Long productId, Long qty) {
        if (qty == null || qty <= 0) {
            throw new InvalidQuantityException();                       // ORA-20010
        }

        String custClass = catalog.activeCustomerClass(customerId)
                .orElseThrow(LegacyNotFoundException::customerOrProduct); // NO_DATA_FOUND
        BigDecimal listPrice = catalog.activeListPrice(productId)
                .orElseThrow(LegacyNotFoundException::customerOrProduct);

        BigDecimal tierDisc = catalog.bestTierDiscount(productId, qty);   // BR-PRC-04
        BigDecimal classDisc = CLASS_DISC.get(custClass);
        if (classDisc == null) {
            // legacy: g_class_disc(l_class) on an unknown key raises NO_DATA_FOUND
            throw LegacyNotFoundException.noDataFound();
        }

        // multiplicative compounding, tier then class (BR-PRC-06)
        BigDecimal price = listPrice
                .multiply(BigDecimal.ONE.subtract(tierDisc.movePointLeft(2)))
                .multiply(BigDecimal.ONE.subtract(classDisc.movePointLeft(2)));

        // promotion override: promo wins only if strictly cheaper (RT-1189)
        String promoApplied = "N";
        Promo promo = catalog.currentPromo(productId).orElse(null);
        if (promo != null) {
            if (promo.promoPrice() != null && promo.promoPrice().compareTo(price) < 0) {
                price = promo.promoPrice();                               // BR-PRC-08
                promoApplied = "Y";
            } else if (promo.promoDiscPct() != null) {
                BigDecimal pctPrice = listPrice
                        .multiply(BigDecimal.ONE.subtract(promo.promoDiscPct().movePointLeft(2)));
                if (pctPrice.compareTo(price) < 0) {                      // BR-PRC-09: off LIST price
                    price = pctPrice;
                    promoApplied = "Y";
                }
            }
        }

        // DO NOT CHANGE: finance reconciles against the truncated unit
        // price (helpdesk #4711). TRUNC, not ROUND -- BR-PRC-11/12:
        // truncate first, then multiply.
        BigDecimal unitPrice = price.setScale(2, RoundingMode.DOWN);
        BigDecimal total = unitPrice.multiply(BigDecimal.valueOf(qty));

        return new Quote(listPrice, tierDisc, classDisc, promoApplied, unitPrice, total);
    }
}
