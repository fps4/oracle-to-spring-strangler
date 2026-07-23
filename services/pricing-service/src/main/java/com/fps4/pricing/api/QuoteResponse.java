package com.fps4.pricing.api;

import java.math.BigDecimal;

/**
 * Wire shape of GET /api/pricing/quote -- field-for-field the legacy
 * ORDS response (legacy/ords/modules.sql, BR-API-01). Snake_case comes
 * from the global Jackson naming strategy. DTO only, no persistence
 * types (FS-0003 scope 4).
 */
public record QuoteResponse(
        Long customerId,
        Long productId,
        Long qty,
        BigDecimal listPrice,
        BigDecimal tierDiscPct,
        BigDecimal classDiscPct,
        String promoApplied,
        BigDecimal unitPrice,
        BigDecimal total) {
}
