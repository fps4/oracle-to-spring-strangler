package com.fps4.pricing.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

/**
 * Golden-master unit tests for the extracted PKG_PRICING rules
 * (BR-PRC-01..12). The expected values are the legacy anchors that
 * scripts/smoke-legacy.sh proves against real Oracle -- if these tests
 * and that script disagree, the extraction is wrong, not the tests.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class PricingServiceTest {

    private static final long CUST = 1L;
    private static final long PROD = 1000L;

    @Mock
    private PricingCatalog catalog;

    private PricingService pricing;

    @BeforeEach
    void setUp() {
        pricing = new PricingService(catalog);
        // defaults: class C, no tier, no promo -- tests override per case
        when(catalog.activeCustomerClass(anyLong())).thenReturn(Optional.of("C"));
        when(catalog.bestTierDiscount(anyLong(), anyLong())).thenReturn(BigDecimal.ZERO);
        when(catalog.currentPromo(anyLong())).thenReturn(Optional.empty());
    }

    private void listPrice(String price) {
        when(catalog.activeListPrice(anyLong())).thenReturn(Optional.of(new BigDecimal(price)));
    }

    // ----------------------------------------------------------------- quirk

    @Test
    @DisplayName("THE TRUNC QUIRK (BR-PRC-11): 12.3456 truncates to 12.34, never rounds to 12.35")
    void truncQuirkPinned() {
        listPrice("12.3456");

        Quote quote = pricing.quote(CUST, 1002L, 1L);

        // helpdesk #4711: ROUND() broke month-end and was reverted --
        // this assertion is the regression pin for that decision
        assertThat(quote.unitPrice()).isEqualByComparingTo("12.34");
        assertThat(quote.unitPrice()).isNotEqualByComparingTo("12.35");
        assertThat(quote.total()).isEqualByComparingTo("12.34");
    }

    @Test
    @DisplayName("truncate THEN multiply (BR-PRC-12): total is unit*qty of the truncated unit")
    void truncateBeforeMultiply() {
        listPrice("12.3456");

        Quote quote = pricing.quote(CUST, 1002L, 100L);

        // 12.34 * 100 = 1234.00 -- NOT trunc(12.3456*100)=1234.56
        assertThat(quote.total()).isEqualByComparingTo("1234.00");
    }

    // ------------------------------------------------------------- discounts

    @Test
    @DisplayName("class discount A=10 (BR-PRC-05): 19.99 -> 17.99 for a class-A customer")
    void classDiscount() {
        when(catalog.activeCustomerClass(CUST)).thenReturn(Optional.of("A"));
        listPrice("19.99");

        Quote quote = pricing.quote(CUST, PROD, 5L);

        assertThat(quote.classDiscPct()).isEqualByComparingTo("10");
        assertThat(quote.unitPrice()).isEqualByComparingTo("17.99");  // 17.991 truncated
        assertThat(quote.total()).isEqualByComparingTo("89.95");
    }

    @Test
    @DisplayName("tier and class compound multiplicatively (BR-PRC-06): 19.99 * 0.9 * 0.9 -> 16.19")
    void tierAndClassCompound() {
        when(catalog.activeCustomerClass(CUST)).thenReturn(Optional.of("A"));
        when(catalog.bestTierDiscount(eq(PROD), eq(50L))).thenReturn(BigDecimal.TEN);
        listPrice("19.99");

        Quote quote = pricing.quote(CUST, PROD, 50L);

        assertThat(quote.tierDiscPct()).isEqualByComparingTo("10");
        assertThat(quote.unitPrice()).isEqualByComparingTo("16.19");  // 16.1919 truncated
    }

    @Test
    @DisplayName("no tier band matches -> tier discount 0 (BR-PRC-04)")
    void noTierIsZero() {
        listPrice("7.49");

        Quote quote = pricing.quote(CUST, PROD, 1L);

        assertThat(quote.tierDiscPct()).isEqualByComparingTo("0");
        assertThat(quote.unitPrice()).isEqualByComparingTo("7.49");
    }

    // ------------------------------------------------------------ promotions

    @Test
    @DisplayName("absolute promo wins only when strictly cheaper (BR-PRC-08): 19.9999 < 24.68 -> applied, truncated to 19.99")
    void absolutePromoCheaper() {
        listPrice("24.6800");
        when(catalog.currentPromo(1004L))
                .thenReturn(Optional.of(new Promo(new BigDecimal("19.9999"), null)));

        Quote quote = pricing.quote(CUST, 1004L, 1L);

        assertThat(quote.promoApplied()).isEqualTo("Y");
        assertThat(quote.unitPrice()).isEqualByComparingTo("19.99");
    }

    @Test
    @DisplayName("absolute promo NOT cheaper than the discounted price -> silently ignored (BR-PRC-08/10)")
    void absolutePromoNotCheaper() {
        when(catalog.activeCustomerClass(CUST)).thenReturn(Optional.of("A"));
        listPrice("24.6800");
        // discounted price = 24.68*0.9 = 22.212; promo 23 is not cheaper
        when(catalog.currentPromo(1004L))
                .thenReturn(Optional.of(new Promo(new BigDecimal("23"), null)));

        Quote quote = pricing.quote(CUST, 1004L, 1L);

        assertThat(quote.promoApplied()).isEqualTo("N");
        assertThat(quote.unitPrice()).isEqualByComparingTo("22.21");
    }

    @Test
    @DisplayName("pct promo applies off LIST price, not the discounted price (BR-PRC-09)")
    void pctPromoOffListPrice() {
        when(catalog.activeCustomerClass(CUST)).thenReturn(Optional.of("C"));
        listPrice("7.49");
        when(catalog.currentPromo(1001L))
                .thenReturn(Optional.of(new Promo(null, new BigDecimal("12.5"))));

        Quote quote = pricing.quote(CUST, 1001L, 1L);

        // 7.49 * 0.875 = 6.55375 -> 6.55
        assertThat(quote.promoApplied()).isEqualTo("Y");
        assertThat(quote.unitPrice()).isEqualByComparingTo("6.55");
    }

    @Test
    @DisplayName("pct promo must be STRICTLY cheaper: equal price does not flip the flag")
    void pctPromoEqualIsNotApplied() {
        when(catalog.activeCustomerClass(CUST)).thenReturn(Optional.of("A"));
        listPrice("100");
        // class A makes the price 90; a 10% promo also lands at exactly 90
        when(catalog.currentPromo(PROD))
                .thenReturn(Optional.of(new Promo(null, BigDecimal.TEN)));

        Quote quote = pricing.quote(CUST, PROD, 1L);

        assertThat(quote.promoApplied()).isEqualTo("N");
        assertThat(quote.unitPrice()).isEqualByComparingTo("90.00");
    }

    @Test
    @DisplayName("promo row with promo_price NULL falls through to the pct branch")
    void promoPriceNullUsesPctBranch() {
        listPrice("45.90");
        when(catalog.currentPromo(1003L))
                .thenReturn(Optional.of(new Promo(null, new BigDecimal("50"))));

        Quote quote = pricing.quote(CUST, 1003L, 1L);

        assertThat(quote.promoApplied()).isEqualTo("Y");
        assertThat(quote.unitPrice()).isEqualByComparingTo("22.95");
    }

    // ------------------------------------------------------------ validation

    @Test
    @DisplayName("qty null/zero/negative -> ORA-20010 (BR-PRC-01), checked before any lookup")
    void qtyMustBePositive() {
        assertThatExceptionOfType(InvalidQuantityException.class)
                .isThrownBy(() -> pricing.quote(CUST, PROD, null));
        assertThatExceptionOfType(InvalidQuantityException.class)
                .isThrownBy(() -> pricing.quote(CUST, PROD, 0L));
        assertThatExceptionOfType(InvalidQuantityException.class)
                .isThrownBy(() -> pricing.quote(CUST, PROD, -5L));
    }

    @Test
    @DisplayName("unknown/inactive customer or product -> NO_DATA_FOUND, indistinguishable (BR-PRC-02/03)")
    void missingCustomerOrProduct() {
        when(catalog.activeCustomerClass(anyLong())).thenReturn(Optional.empty());

        assertThatExceptionOfType(LegacyNotFoundException.class)
                .isThrownBy(() -> pricing.quote(99L, PROD, 1L))
                .withMessage("customer or product not found");

        when(catalog.activeCustomerClass(anyLong())).thenReturn(Optional.of("C"));
        when(catalog.activeListPrice(anyLong())).thenReturn(Optional.empty());

        assertThatExceptionOfType(LegacyNotFoundException.class)
                .isThrownBy(() -> pricing.quote(CUST, 999999L, 1L))
                .withMessage("customer or product not found");
    }
}
