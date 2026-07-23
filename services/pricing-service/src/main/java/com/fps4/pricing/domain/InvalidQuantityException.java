package com.fps4.pricing.domain;

/** Legacy ORA-20010: qty missing or not positive -> HTTP 400 (BR-PRC-01). */
public class InvalidQuantityException extends RuntimeException {

    public InvalidQuantityException() {
        super("QTY MUST BE POSITIVE");
    }
}
