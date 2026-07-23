package com.fps4.pricing.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.fps4.pricing.domain.PricingCatalog;
import com.fps4.pricing.domain.PricingService;

/**
 * Wires the framework-free domain (FS-0003 scope 3: no Spring in the
 * pricing logic -- the annotations stay out here at the edge).
 */
@Configuration
public class DomainConfig {

    @Bean
    public PricingService pricingService(PricingCatalog catalog) {
        return new PricingService(catalog);
    }
}
