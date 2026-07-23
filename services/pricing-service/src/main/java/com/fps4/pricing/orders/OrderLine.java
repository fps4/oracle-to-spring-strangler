package com.fps4.pricing.orders;

/**
 * One requested order line -- mirrors pkg_orders.t_line_rec. Boxed ids
 * on purpose: null degrades like the legacy JSON paths (BR-ORD-13),
 * not as bean-validation rejections.
 */
public record OrderLine(Long productId, Long qty) {
}
