package com.fps4.pricing.orders;

/** Legacy ORA-20001 E_CREDIT_EXCEEDED -> HTTP 422 (BR-ORD-05). */
public class CreditLimitExceededException extends RuntimeException {

    public CreditLimitExceededException(Long customerId) {
        super("CREDIT LIMIT EXCEEDED FOR CUSTOMER " + customerId);
    }
}
