package com.fps4.pricing;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * pricing-service -- the one target service of the strangler migration
 * (ADR-0002: one domain, one service). Three legacy PL/SQL modules land
 * here by three different lanes (ADR-0003):
 *
 *   PKG_PRICING    -> extracted  -> {@link com.fps4.pricing.domain.PricingService}
 *   PKG_ORDERS     -> translated -> {@link com.fps4.pricing.orders.OrderService}
 *   PKG_STATEMENTS -> retained   -> {@link com.fps4.pricing.statements.StatementService}
 */
@SpringBootApplication
public class PricingApplication {

    public static void main(String[] args) {
        SpringApplication.run(PricingApplication.class, args);
    }
}
