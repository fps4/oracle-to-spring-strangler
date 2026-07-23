package com.fps4.pricing.domain;

import java.math.BigDecimal;

/**
 * An active promotion row: either an absolute price override or a
 * percentage off list (legacy allows both columns; get_quote checks
 * promo_price first -- preserved in {@link PricingService}).
 */
public record Promo(BigDecimal promoPrice, BigDecimal promoDiscPct) {
}
