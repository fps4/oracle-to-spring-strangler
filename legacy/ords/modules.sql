-- =====================================================================
--  ORDS REST modules for the LEGACY schema (FS-0001 scope item 4).
--  Runs as LEGACY *after* the ORDS container has installed ORDS into
--  XEPDB1 (see configure-ords.sh wait loop). Idempotent: ORDS.DEFINE_*
--  calls replace existing definitions.
--
--  Legacy HTTP error contract (mapped to RFC 7807 by the target, FS-0005):
--    ORA-20001 E_CREDIT_EXCEEDED    -> 422
--    ORA-20002 E_INSUFFICIENT_STOCK -> 409
--    ORA-20003 bad period           -> 400
--    ORA-20010..-20012 validation   -> 400
--    NO_DATA_FOUND                  -> 404
--    anything else                  -> 500
-- =====================================================================
WHENEVER SQLERROR EXIT FAILURE

BEGIN
    ORDS.ENABLE_SCHEMA(
        p_enabled             => TRUE,
        p_schema              => 'LEGACY',
        p_url_mapping_type    => 'BASE_PATH',
        p_url_mapping_pattern => 'legacy',
        p_auto_rest_auth      => FALSE);

    ORDS.DEFINE_MODULE(
        p_module_name    => 'legacy.api',
        p_base_path      => '/',
        p_items_per_page => 25,
        p_status         => 'PUBLISHED',
        p_comments       => 'Legacy wholesale API (frozen specimen, FS-0001)');

    -- ------------------------------------------------ pricing/quote (GET)
    ORDS.DEFINE_TEMPLATE(p_module_name => 'legacy.api', p_pattern => 'pricing/quote');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'legacy.api',
        p_pattern     => 'pricing/quote',
        p_method      => 'GET',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'~
DECLARE
    l_list  NUMBER; l_tier NUMBER; l_class NUMBER;
    l_promo VARCHAR2(1); l_unit NUMBER; l_total NUMBER;
    FUNCTION n2j (p NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN RTRIM(TO_CHAR(p, 'FM999999999990.09999',
                     'NLS_NUMERIC_CHARACTERS=''. '''), '.');
    END;
BEGIN
    pkg_pricing.get_quote(TO_NUMBER(:customer_id), TO_NUMBER(:product_id),
                          TO_NUMBER(:qty),
                          l_list, l_tier, l_class, l_promo, l_unit, l_total);
    OWA_UTIL.mime_header('application/json', TRUE);
    HTP.p('{"customer_id":' || :customer_id
       || ',"product_id":'  || :product_id
       || ',"qty":'         || :qty
       || ',"list_price":'  || n2j(l_list)
       || ',"tier_disc_pct":'  || n2j(l_tier)
       || ',"class_disc_pct":' || n2j(l_class)
       || ',"promo_applied":"' || l_promo || '"'
       || ',"unit_price":'  || n2j(l_unit)
       || ',"total":'       || n2j(l_total) || '}');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        :status_code := 404;
        OWA_UTIL.mime_header('application/json', TRUE);
        HTP.p('{"error_code":"ORA-01403","message":"customer or product not found"}');
    WHEN OTHERS THEN
        :status_code := CASE WHEN SQLCODE BETWEEN -20012 AND -20010 THEN 400 ELSE 500 END;
        OWA_UTIL.mime_header('application/json', TRUE);
        HTP.p('{"error_code":"ORA' || SQLCODE || '","message":"'
              || REPLACE(SUBSTR(SQLERRM, 1, 200), '"', '''') || '"}');
END;~');

    -- ------------------------------------------------ orders (POST)
    ORDS.DEFINE_TEMPLATE(p_module_name => 'legacy.api', p_pattern => 'orders');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'legacy.api',
        p_pattern     => 'orders',
        p_method      => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'~
DECLARE
    l_order_id  NUMBER;
    l_total     NUMBER;
BEGIN
    pkg_orders.place_order_json(:body_text, l_order_id, l_total);
    :status_code := 201;
    OWA_UTIL.mime_header('application/json', TRUE);
    HTP.p('{"order_id":' || l_order_id
       || ',"status":"OPEN"'
       || ',"total":' || RTRIM(TO_CHAR(l_total, 'FM999999999990.09',
                          'NLS_NUMERIC_CHARACTERS=''. '''), '.') || '}');
EXCEPTION
    WHEN OTHERS THEN
        :status_code := CASE SQLCODE
                          WHEN -20001 THEN 422
                          WHEN -20002 THEN 409
                          WHEN -1403  THEN 404
                          ELSE CASE WHEN SQLCODE BETWEEN -20012 AND -20010
                                    THEN 400 ELSE 500 END
                        END;
        OWA_UTIL.mime_header('application/json', TRUE);
        HTP.p('{"error_code":"ORA' || SQLCODE || '","message":"'
              || REPLACE(SUBSTR(SQLERRM, 1, 200), '"', '''') || '"}');
END;~');

    -- ------------------------------------------------ orders/:id (GET)
    ORDS.DEFINE_TEMPLATE(p_module_name => 'legacy.api', p_pattern => 'orders/:id');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'legacy.api',
        p_pattern     => 'orders/:id',
        p_method      => 'GET',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'~
DECLARE
    l_body CLOB;
BEGIN
    SELECT JSON_OBJECT(
             'order_id'    VALUE o.order_id,
             'customer_id' VALUE o.customer_id,
             'order_dt'    VALUE TO_CHAR(o.order_dt, 'YYYY-MM-DD'),
             'status'      VALUE o.status,
             'total_amt'   VALUE o.total_amt,
             'lines'       VALUE (SELECT JSON_ARRAYAGG(
                                           JSON_OBJECT(
                                             'line_no'    VALUE l.line_no,
                                             'product_id' VALUE l.product_id,
                                             'qty'        VALUE l.qty,
                                             'unit_price' VALUE l.unit_price,
                                             'line_amt'   VALUE l.line_amt)
                                           ORDER BY l.line_no RETURNING CLOB)
                                    FROM order_lines l
                                   WHERE l.order_id = o.order_id)
             FORMAT JSON
             RETURNING CLOB)
      INTO l_body
      FROM orders o
     WHERE o.order_id = TO_NUMBER(:id);
    OWA_UTIL.mime_header('application/json', TRUE);
    HTP.p(l_body);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        :status_code := 404;
        OWA_UTIL.mime_header('application/json', TRUE);
        HTP.p('{"error_code":"ORA-01403","message":"order not found"}');
END;~');

    -- ------------------------------------------------ statements/run (POST)
    ORDS.DEFINE_TEMPLATE(p_module_name => 'legacy.api', p_pattern => 'statements/run');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'legacy.api',
        p_pattern     => 'statements/run',
        p_method      => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'~
DECLARE
    l_period VARCHAR2(7);
    l_cnt    NUMBER;
BEGIN
    l_period := JSON_VALUE(:body_text, '$.period');
    pkg_statements.run_monthly(l_period, l_cnt);
    OWA_UTIL.mime_header('application/json', TRUE);
    HTP.p('{"period":"' || l_period || '","statements":' || l_cnt || '}');
EXCEPTION
    WHEN OTHERS THEN
        :status_code := CASE WHEN SQLCODE = -20003 THEN 400 ELSE 500 END;
        OWA_UTIL.mime_header('application/json', TRUE);
        HTP.p('{"error_code":"ORA' || SQLCODE || '","message":"'
              || REPLACE(SUBSTR(SQLERRM, 1, 200), '"', '''') || '"}');
END;~');

    COMMIT;
END;
/

SELECT 'ORDS modules defined for LEGACY' FROM dual;
EXIT
