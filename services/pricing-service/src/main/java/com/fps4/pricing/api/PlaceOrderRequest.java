package com.fps4.pricing.api;

import java.util.List;

/**
 * Body of POST /api/orders. Deliberately NOT bean-validated with
 * NotNull/NotEmpty: the legacy JSON degradation paths are part of the
 * frozen contract (BR-ORD-13 -- missing lines -> 400 "ORDER HAS NO
 * LINES", missing customer_id -> 404) and the service layer reproduces
 * them; stricter validation here would change observable behavior.
 */
public record PlaceOrderRequest(Long customerId, List<OrderLineRequest> lines) {

    public record OrderLineRequest(Long productId, Long qty) {
    }
}
