package com.fps4.pricing.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.fps4.pricing.config.SecurityConfig;
import com.fps4.pricing.domain.InvalidQuantityException;
import com.fps4.pricing.domain.LegacyNotFoundException;
import com.fps4.pricing.domain.PricingService;
import com.fps4.pricing.domain.Quote;

/**
 * API-layer slice tests (FS-0003 scope 4/7): snake_case wire shape,
 * RFC 7807 problems carrying the legacy status contract.
 */
@WebMvcTest(PricingController.class)
@Import(SecurityConfig.class)
class PricingControllerTest {

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private PricingService pricing;

    @Test
    @DisplayName("200: legacy snake_case field names and Y/N promo flag (BR-API-01)")
    void quoteShape() throws Exception {
        when(pricing.quote(1L, 1000L, 5L)).thenReturn(new Quote(
                new BigDecimal("19.99"), BigDecimal.ZERO, BigDecimal.TEN,
                "N", new BigDecimal("17.99"), new BigDecimal("89.95")));

        mvc.perform(get("/api/pricing/quote")
                        .param("customer_id", "1")
                        .param("product_id", "1000")
                        .param("qty", "5"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.customer_id").value(1))
                .andExpect(jsonPath("$.product_id").value(1000))
                .andExpect(jsonPath("$.qty").value(5))
                .andExpect(jsonPath("$.list_price").value(19.99))
                .andExpect(jsonPath("$.tier_disc_pct").value(0))
                .andExpect(jsonPath("$.class_disc_pct").value(10))
                .andExpect(jsonPath("$.promo_applied").value("N"))
                .andExpect(jsonPath("$.unit_price").value(17.99))
                .andExpect(jsonPath("$.total").value(89.95));
    }

    @Test
    @DisplayName("404 problem: unknown customer/product, error_code ORA-01403 (BR-API-02)")
    void notFoundProblem() throws Exception {
        when(pricing.quote(any(), any(), any()))
                .thenThrow(LegacyNotFoundException.customerOrProduct());

        mvc.perform(get("/api/pricing/quote")
                        .param("customer_id", "1")
                        .param("product_id", "999999")
                        .param("qty", "1"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.status").value(404))
                .andExpect(jsonPath("$.detail").value("customer or product not found"))
                .andExpect(jsonPath("$.error_code").value("ORA-01403"));
    }

    @Test
    @DisplayName("400 problem: non-positive qty, error_code ORA-20010 (BR-API-03)")
    void invalidQtyProblem() throws Exception {
        when(pricing.quote(any(), any(), any())).thenThrow(new InvalidQuantityException());

        mvc.perform(get("/api/pricing/quote")
                        .param("customer_id", "1")
                        .param("product_id", "1000")
                        .param("qty", "0"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.detail").value("QTY MUST BE POSITIVE"))
                .andExpect(jsonPath("$.error_code").value("ORA-20010"));
    }
}
