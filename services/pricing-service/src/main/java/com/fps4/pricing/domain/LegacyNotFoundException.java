package com.fps4.pricing.domain;

/**
 * Legacy NO_DATA_FOUND (ORA-01403) -> HTTP 404. The detail strings
 * mirror the ORDS handler bodies (legacy/ords/modules.sql): the quote
 * path cannot tell a missing customer from a missing product
 * (BR-PRC-02/03) and says so.
 */
public class LegacyNotFoundException extends RuntimeException {

    public LegacyNotFoundException(String detail) {
        super(detail);
    }

    public static LegacyNotFoundException customerOrProduct() {
        return new LegacyNotFoundException("customer or product not found");
    }

    public static LegacyNotFoundException noDataFound() {
        return new LegacyNotFoundException("no data found");
    }
}
