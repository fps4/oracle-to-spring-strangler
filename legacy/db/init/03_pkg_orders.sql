-- PKG_ORDERS -- order entry. Credit + stock + audit in ONE transaction.
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = legacy;

CREATE OR REPLACE PACKAGE pkg_orders AS

    E_CREDIT_EXCEEDED       EXCEPTION;
    PRAGMA EXCEPTION_INIT(E_CREDIT_EXCEEDED, -20001);
    E_INSUFFICIENT_STOCK    EXCEPTION;
    PRAGMA EXCEPTION_INIT(E_INSUFFICIENT_STOCK, -20002);

    TYPE t_line_rec IS RECORD (
        product_id  products.product_id%TYPE,
        qty         NUMBER
    );
    TYPE t_line_tab IS TABLE OF t_line_rec INDEX BY BINARY_INTEGER;

    PROCEDURE place_order (
        p_customer_id   IN  customers.customer_id%TYPE,
        p_lines         IN  t_line_tab,
        x_order_id      OUT orders.order_id%TYPE,
        x_total         OUT orders.total_amt%TYPE
    );

    -- ORDS plumbing: parses request body, delegates to place_order
    PROCEDURE place_order_json (
        p_body          IN  CLOB,
        x_order_id      OUT orders.order_id%TYPE,
        x_total         OUT orders.total_amt%TYPE
    );

END pkg_orders;
/

CREATE OR REPLACE PACKAGE BODY pkg_orders AS

    PROCEDURE log_audit (
        p_action    IN audit_log.action%TYPE,
        p_ref_id    IN audit_log.ref_id%TYPE,
        p_details   IN audit_log.details%TYPE
    ) IS
    BEGIN
        INSERT INTO audit_log (audit_id, module, action, ref_id, details)
        VALUES (seq_audit.NEXTVAL, 'PKG_ORDERS', p_action, p_ref_id, p_details);
    END log_audit;

    PROCEDURE place_order (
        p_customer_id   IN  customers.customer_id%TYPE,
        p_lines         IN  t_line_tab,
        x_order_id      OUT orders.order_id%TYPE,
        x_total         OUT orders.total_amt%TYPE
    ) IS
        l_limit         credit_limits.credit_limit%TYPE;
        l_outstanding   NUMBER;
        l_avail         NUMBER;
        l_list          products.list_price%TYPE;
        l_tier          NUMBER;
        l_class         NUMBER;
        l_promo         VARCHAR2(1);
        l_unit          NUMBER;
        l_line_amt      NUMBER;
    BEGIN
        IF p_lines.COUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20012, 'ORDER HAS NO LINES');
        END IF;

        SELECT cl.credit_limit INTO l_limit
          FROM credit_limits cl, customers c
         WHERE cl.customer_id = c.customer_id
           AND c.customer_id  = p_customer_id
           AND c.status       = 'ACTIVE';

        -- price all lines first (quote logic is THE single source, RT-2203)
        x_total := 0;
        FOR i IN 1 .. p_lines.COUNT LOOP
            pkg_pricing.get_quote(
                p_customer_id, p_lines(i).product_id, p_lines(i).qty,
                l_list, l_tier, l_class, l_promo, l_unit, l_line_amt);
            x_total := x_total + l_line_amt;
        END LOOP;

        -- credit check: open + shipped exposure counts, invoiced does not
        SELECT NVL(SUM(total_amt), 0) INTO l_outstanding
          FROM orders
         WHERE customer_id = p_customer_id
           AND status IN ('OPEN', 'SHIPPED');

        IF l_outstanding + x_total > l_limit THEN
            RAISE_APPLICATION_ERROR(-20001,
                'CREDIT LIMIT EXCEEDED FOR CUSTOMER ' || p_customer_id);
        END IF;

        x_order_id := seq_orders.NEXTVAL;

        INSERT INTO orders (order_id, customer_id, order_dt, status, total_amt)
        VALUES (x_order_id, p_customer_id, SYSDATE, 'OPEN', x_total);

        FOR i IN 1 .. p_lines.COUNT LOOP
            -- reserve stock, row-locked
            DECLARE
                l_on_hand   stock.qty_on_hand%TYPE;
                l_reserved  stock.qty_reserved%TYPE;
            BEGIN
                SELECT qty_on_hand, qty_reserved
                  INTO l_on_hand, l_reserved
                  FROM stock
                 WHERE product_id = p_lines(i).product_id
                   FOR UPDATE;

                IF l_on_hand - l_reserved < p_lines(i).qty THEN
                    RAISE_APPLICATION_ERROR(-20002,
                        'INSUFFICIENT STOCK FOR PRODUCT ' || p_lines(i).product_id);
                END IF;

                UPDATE stock
                   SET qty_reserved = qty_reserved + p_lines(i).qty,
                       updated_dt   = SYSDATE
                 WHERE product_id = p_lines(i).product_id;
            END;

            pkg_pricing.get_quote(
                p_customer_id, p_lines(i).product_id, p_lines(i).qty,
                l_list, l_tier, l_class, l_promo, l_unit, l_line_amt);

            INSERT INTO order_lines (order_id, line_no, product_id, qty, unit_price, line_amt)
            VALUES (x_order_id, i, p_lines(i).product_id, p_lines(i).qty, l_unit, l_line_amt);
        END LOOP;

        log_audit('ORDER_PLACED', x_order_id,
                  'cust=' || p_customer_id || ' total=' || x_total
                  || ' lines=' || p_lines.COUNT);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;  -- nothing survives a failed order (helpdesk #3302)
            RAISE;
    END place_order;

    PROCEDURE place_order_json (
        p_body          IN  CLOB,
        x_order_id      OUT orders.order_id%TYPE,
        x_total         OUT orders.total_amt%TYPE
    ) IS
        l_lines     t_line_tab;
        l_cust_id   customers.customer_id%TYPE;
        i           BINARY_INTEGER := 0;
    BEGIN
        SELECT customer_id INTO l_cust_id
          FROM JSON_TABLE(p_body, '$' COLUMNS (customer_id NUMBER PATH '$.customer_id'));

        FOR r IN (SELECT product_id, qty
                    FROM JSON_TABLE(p_body, '$.lines[*]'
                         COLUMNS (product_id NUMBER PATH '$.product_id',
                                  qty        NUMBER PATH '$.qty'))) LOOP
            i := i + 1;
            l_lines(i).product_id := r.product_id;
            l_lines(i).qty        := r.qty;
        END LOOP;

        place_order(l_cust_id, l_lines, x_order_id, x_total);
    END place_order_json;

END pkg_orders;
/
SHOW ERRORS
