package com.fps4.pricing.orders;

import java.math.BigDecimal;

/** Outcome of place_order: the new order id and its priced total. */
public record PlacedOrder(long orderId, String status, BigDecimal total) {
}
