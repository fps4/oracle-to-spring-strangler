package com.fps4.pricing.api;

import java.math.BigDecimal;

/**
 * Wire shape of the 201 from POST /api/orders (BR-API-04): order id,
 * the literal "OPEN", the priced total. No Location header -- the
 * legacy response never had one.
 */
public record PlaceOrderResponse(Long orderId, String status, BigDecimal total) {
}
