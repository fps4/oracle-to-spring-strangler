package com.fps4.pricing.orders;

/** Legacy ORA-20002 E_INSUFFICIENT_STOCK -> HTTP 409 (BR-ORD-07). */
public class InsufficientStockException extends RuntimeException {

    public InsufficientStockException(Long productId) {
        super("INSUFFICIENT STOCK FOR PRODUCT " + productId);
    }
}
