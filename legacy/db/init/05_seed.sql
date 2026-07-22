-- =====================================================================
--  Seed data -- deterministic (DBMS_RANDOM.SEED fixed, FS-0001).
--  Two clean startups produce identical business data. The ONE exception:
--  the three "evergreen" promotions use TRUNC(SYSDATE) windows so the
--  promo path is demoable on any calendar day (dates differ, values don't).
--  Rows 1..N below are hand-pinned anchors used by smoke + parity corpus.
-- =====================================================================
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = legacy;

-- ---- pinned anchor rows ---------------------------------------------

INSERT INTO customers VALUES (1, 'NORDWIND WHOLESALE GMBH',  'A', 'DE-NORTH', DATE '2004-03-15', 'ACTIVE');
INSERT INTO customers VALUES (2, 'BALTIC TRADE PARTNERS OY', 'B', 'FI',       DATE '2005-11-02', 'ACTIVE');
INSERT INTO customers VALUES (3, 'KLEINHANDEL MUELLER KG',   'C', 'DE-SOUTH', DATE '2007-06-20', 'ACTIVE');

INSERT INTO credit_limits VALUES (1, 250000, 'EUR', DATE '2019-01-10');
INSERT INTO credit_limits VALUES (2,  50000, 'EUR', DATE '2019-01-10');
INSERT INTO credit_limits VALUES (3,    500, 'EUR', DATE '2012-04-01');   -- credit-reject specimen

INSERT INTO products VALUES (1000, 'SKU-1000', 'INDUSTRIAL FASTENER M8 BOX',   19.99,   'BOX', 'ACTIVE');
INSERT INTO products VALUES (1001, 'SKU-1001', 'BEARING ASSEMBLY 6204',         7.49,   'EA',  'ACTIVE');
INSERT INTO products VALUES (1002, 'SKU-1002', 'HYDRAULIC SEAL KIT 40MM',      12.3456, 'KIT', 'ACTIVE');  -- 4dp list, TRUNC specimen
INSERT INTO products VALUES (1003, 'SKU-1003', 'PRECISION SHIM SET 0.05MM',    45.90,   'SET', 'ACTIVE');  -- low stock specimen
INSERT INTO products VALUES (1004, 'SKU-1004', 'COOLANT CONCENTRATE 5L',       24.6800, 'CAN', 'ACTIVE');  -- promo specimen

INSERT INTO stock VALUES (1000, 5000, 0, 200, DATE '2026-01-01');
INSERT INTO stock VALUES (1001, 8000, 0, 500, DATE '2026-01-01');
INSERT INTO stock VALUES (1002, 3000, 0, 100, DATE '2026-01-01');
INSERT INTO stock VALUES (1003,    5, 0,  10, DATE '2026-01-01');
INSERT INTO stock VALUES (1004, 1200, 0, 100, DATE '2026-01-01');

INSERT INTO price_tiers VALUES (1, 1000,  10,  5);
INSERT INTO price_tiers VALUES (2, 1000,  50, 10);
INSERT INTO price_tiers VALUES (3, 1000, 200, 15);
INSERT INTO price_tiers VALUES (4, 1002,  25,  7.5);
INSERT INTO price_tiers VALUES (5, 1004,  20,  5);

-- evergreen promos (the documented SYSDATE exception)
INSERT INTO promotions VALUES (1, 1004, 19.9999, NULL, TRUNC(SYSDATE) - 30, TRUNC(SYSDATE) + 365);
INSERT INTO promotions VALUES (2, 1001, NULL,    12.5, TRUNC(SYSDATE) - 30, TRUNC(SYSDATE) + 365);
INSERT INTO promotions VALUES (3, 1003, 39.9900, NULL, TRUNC(SYSDATE) - 30, TRUNC(SYSDATE) + 365);

-- ---- generated bulk (fixed seed) ------------------------------------

DECLARE
    PROCEDURE seed_reset IS BEGIN DBMS_RANDOM.SEED(20260722); END;
    FUNCTION rnd_int (p_lo NUMBER, p_hi NUMBER) RETURN NUMBER IS
    BEGIN RETURN TRUNC(DBMS_RANDOM.VALUE(p_lo, p_hi + 1)); END;

    l_class     VARCHAR2(1);
    l_region    VARCHAR2(20);
    l_price     NUMBER;
    l_qty       NUMBER;
    l_status    VARCHAR2(12);
    l_disc      NUMBER;
    l_unit      NUMBER;
    l_line_amt  NUMBER;
    l_total     NUMBER;
    l_order_id  NUMBER;
    l_lines     NUMBER;
    l_prod      NUMBER;
    l_dt        DATE;
    l_tier_id   NUMBER := 100;
    l_promo_id  NUMBER := 100;
BEGIN
    seed_reset;

    -- 47 more customers (4..50)
    FOR i IN 4 .. 50 LOOP
        l_class  := CASE rnd_int(1, 10) WHEN 1 THEN 'A' WHEN 2 THEN 'A'
                         WHEN 3 THEN 'B' WHEN 4 THEN 'B' WHEN 5 THEN 'B'
                         ELSE 'C' END;
        l_region := CASE rnd_int(1, 5) WHEN 1 THEN 'DE-NORTH' WHEN 2 THEN 'DE-SOUTH'
                         WHEN 3 THEN 'NL' WHEN 4 THEN 'FI' ELSE 'PL' END;
        INSERT INTO customers VALUES
            (i, 'CUSTOMER ' || LPAD(i, 4, '0') || ' ' || l_region, l_class,
             l_region, DATE '2004-01-01' + rnd_int(0, 6000), 'ACTIVE');
        INSERT INTO credit_limits VALUES
            (i, rnd_int(5, 200) * 1000, 'EUR', DATE '2019-01-10');
    END LOOP;

    -- 195 more products (1005..1199)
    FOR i IN 1005 .. 1199 LOOP
        l_price := rnd_int(100, 19999) / 100;             -- 2dp list for bulk
        INSERT INTO products VALUES
            (i, 'SKU-' || i, 'GENERATED PART ' || i, l_price, 'EA', 'ACTIVE');
        INSERT INTO stock VALUES
            (i, rnd_int(100, 9000), 0, rnd_int(10, 200), DATE '2026-01-01');
        IF MOD(i, 3) = 0 THEN                             -- tiers on every 3rd
            l_tier_id := l_tier_id + 1;
            INSERT INTO price_tiers VALUES (l_tier_id, i, 10, 5);
            l_tier_id := l_tier_id + 1;
            INSERT INTO price_tiers VALUES (l_tier_id, i, 100, 10);
        END IF;
        IF MOD(i, 25) = 0 THEN                            -- historic promos only
            l_promo_id := l_promo_id + 1;
            INSERT INTO promotions VALUES
                (l_promo_id, i, NULL, 15,
                 DATE '2025-11-01', DATE '2025-12-31');
        END IF;
    END LOOP;

    -- ~1k historical orders over fixed window 2025-07-01 .. 2026-06-30
    FOR o IN 1 .. 1000 LOOP
        l_order_id := seq_orders.NEXTVAL;
        l_dt       := DATE '2025-07-01' + rnd_int(0, 364);
        l_status   := CASE rnd_int(1, 10)
                        WHEN 1 THEN 'OPEN' WHEN 2 THEN 'OPEN'
                        WHEN 3 THEN 'SHIPPED' WHEN 4 THEN 'SHIPPED'
                        WHEN 5 THEN 'CANCELLED'
                        ELSE 'INVOICED' END;
        l_lines    := rnd_int(1, 4);
        l_total    := 0;

        INSERT INTO orders VALUES
            (l_order_id, rnd_int(1, 50), l_dt, l_status, 0);

        FOR ln IN 1 .. l_lines LOOP
            l_prod := rnd_int(1000, 1199);
            l_qty  := rnd_int(1, 24);   -- keep open exposure well under limits
            SELECT list_price INTO l_price FROM products WHERE product_id = l_prod;
            l_disc     := CASE rnd_int(1, 3) WHEN 1 THEN 0 WHEN 2 THEN 5 ELSE 10 END;
            l_unit     := TRUNC(l_price * (1 - l_disc / 100), 2);
            l_line_amt := l_unit * l_qty;
            INSERT INTO order_lines VALUES
                (l_order_id, ln, l_prod, l_qty, l_unit, l_line_amt);
            l_total := l_total + l_line_amt;
        END LOOP;

        UPDATE orders SET total_amt = l_total WHERE order_id = l_order_id;
    END LOOP;

    COMMIT;
END;
/

-- sanity: row counts to the startup log
SELECT 'customers=' || COUNT(*) FROM customers;
SELECT 'products='  || COUNT(*) FROM products;
SELECT 'orders='    || COUNT(*) FROM orders;
