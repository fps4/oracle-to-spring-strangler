package com.fps4.pricing.orders;

/** Legacy ORA-20012: order without lines -> HTTP 400 (BR-ORD-01). */
public class EmptyOrderException extends RuntimeException {

    public EmptyOrderException() {
        super("ORDER HAS NO LINES");
    }
}
