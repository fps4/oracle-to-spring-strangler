-- PKG_PRICING -- quote calculation (maintained since 2006, do not touch rounding!)
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = legacy;

CREATE OR REPLACE PACKAGE pkg_pricing AS

    PROCEDURE get_quote (
        p_customer_id   IN  customers.customer_id%TYPE,
        p_product_id    IN  products.product_id%TYPE,
        p_qty           IN  NUMBER,
        x_list_price    OUT products.list_price%TYPE,
        x_tier_disc     OUT NUMBER,
        x_class_disc    OUT NUMBER,
        x_promo_applied OUT VARCHAR2,
        x_unit_price    OUT NUMBER,
        x_total         OUT NUMBER
    );

END pkg_pricing;
/

CREATE OR REPLACE PACKAGE BODY pkg_pricing AS

    -- class discount table, loaded once per session (see init block below)
    TYPE t_disc_tab IS TABLE OF NUMBER INDEX BY VARCHAR2(1);
    g_class_disc    t_disc_tab;

    PROCEDURE get_quote (
        p_customer_id   IN  customers.customer_id%TYPE,
        p_product_id    IN  products.product_id%TYPE,
        p_qty           IN  NUMBER,
        x_list_price    OUT products.list_price%TYPE,
        x_tier_disc     OUT NUMBER,
        x_class_disc    OUT NUMBER,
        x_promo_applied OUT VARCHAR2,
        x_unit_price    OUT NUMBER,
        x_total         OUT NUMBER
    ) IS
        l_class         customers.cust_class%TYPE;
        l_price         NUMBER;
        l_promo_price   promotions.promo_price%TYPE;
        l_promo_pct     promotions.promo_disc_pct%TYPE;
        l_promo_id      promotions.promo_id%TYPE;

        CURSOR c_tier IS
            SELECT disc_pct
              FROM price_tiers
             WHERE product_id = p_product_id
               AND min_qty   <= p_qty
             ORDER BY min_qty DESC;
    BEGIN
        IF p_qty IS NULL OR p_qty <= 0 THEN
            RAISE_APPLICATION_ERROR(-20010, 'QTY MUST BE POSITIVE');
        END IF;

        SELECT cust_class INTO l_class
          FROM customers
         WHERE customer_id = p_customer_id
           AND status = 'ACTIVE';

        SELECT list_price INTO x_list_price
          FROM products
         WHERE product_id = p_product_id
           AND status = 'ACTIVE';

        -- volume tier: best matching band (0 if none)
        x_tier_disc := 0;
        OPEN c_tier;
        FETCH c_tier INTO x_tier_disc;
        CLOSE c_tier;

        x_class_disc := g_class_disc(l_class);

        l_price := x_list_price
                     * (1 - x_tier_disc  / 100)
                     * (1 - x_class_disc / 100);

        -- promotion override: promo price wins only if cheaper (RT-1189)
        x_promo_applied := 'N';
        BEGIN
            SELECT promo_id, promo_price, promo_disc_pct
              INTO l_promo_id, l_promo_price, l_promo_pct
              FROM promotions
             WHERE product_id = p_product_id
               AND TRUNC(SYSDATE) BETWEEN start_dt AND end_dt
               AND ROWNUM = 1;

            IF l_promo_price IS NOT NULL AND l_promo_price < l_price THEN
                l_price := l_promo_price;
                x_promo_applied := 'Y';
            ELSIF l_promo_pct IS NOT NULL THEN
                IF x_list_price * (1 - l_promo_pct / 100) < l_price THEN
                    l_price := x_list_price * (1 - l_promo_pct / 100);
                    x_promo_applied := 'Y';
                END IF;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN NULL;
        END;

        -- DO NOT CHANGE: finance reconciles against truncated unit price
        -- (helpdesk #4711, Aug 2009). ROUND() broke month-end, reverted.
        x_unit_price := TRUNC(l_price, 2);
        x_total      := x_unit_price * p_qty;
    END get_quote;

BEGIN
    g_class_disc('A') := 10;
    g_class_disc('B') := 5;
    g_class_disc('C') := 0;
END pkg_pricing;
/
SHOW ERRORS
