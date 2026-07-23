package com.fps4.pricing.api;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.fps4.pricing.domain.PricingService;
import com.fps4.pricing.domain.Quote;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

/**
 * GET /api/pricing/quote -- the wave-1 endpoint (extract lane). Query
 * parameter names are the legacy snake_case ones: the router must be
 * able to swap backends without consumers noticing (FS-0004).
 */
@RestController
@RequestMapping("/api/pricing")
@Tag(name = "pricing", description = "Quote calculation (extracted PKG_PRICING)")
public class PricingController {

    private final PricingService pricing;

    public PricingController(PricingService pricing) {
        this.pricing = pricing;
    }

    @GetMapping("/quote")
    @Operation(summary = "Price one product for one customer at a quantity")
    public QuoteResponse quote(
            @RequestParam("customer_id") Long customerId,
            @RequestParam("product_id") Long productId,
            @RequestParam("qty") Long qty) {
        Quote quote = pricing.quote(customerId, productId, qty);
        return new QuoteResponse(customerId, productId, qty,
                quote.listPrice(), quote.tierDiscPct(), quote.classDiscPct(),
                quote.promoApplied(), quote.unitPrice(), quote.total());
    }
}
