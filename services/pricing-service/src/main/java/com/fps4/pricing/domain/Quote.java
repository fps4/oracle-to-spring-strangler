package com.fps4.pricing.domain;

import java.math.BigDecimal;

/**
 * Result of a quote calculation -- mirrors the OUT parameters of
 * {@code pkg_pricing.get_quote} (legacy/db/init/02_pkg_pricing.sql).
 * {@code promoApplied} stays a Y/N flag, not a boolean: it is part of
 * the frozen wire contract (BR-API-01).
 */
public record Quote(
        BigDecimal listPrice,
        BigDecimal tierDiscPct,
        BigDecimal classDiscPct,
        String promoApplied,
        BigDecimal unitPrice,
        BigDecimal total) {
}
