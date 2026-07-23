package com.fps4.pricing.statements;

/** Legacy ORA-20003: malformed period -> HTTP 400 (BR-STM-01). */
public class BadPeriodException extends RuntimeException {

    public BadPeriodException(String period) {
        super("BAD PERIOD: " + (period == null ? "" : period));
    }
}
