-- =====================================================================
--  LEGACY schema -- wholesale orders & pricing
--  Period: circa 2004-2009 enterprise Oracle. Do not modernize (AGENTS.md r4).
--  Runs as SYS against XEPDB1 (gvenzl init); LEGACY user pre-created by image.
-- =====================================================================
ALTER SESSION SET CONTAINER = XEPDB1;

GRANT CREATE TABLE, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER, CREATE VIEW TO legacy;
ALTER USER legacy QUOTA UNLIMITED ON users;

ALTER SESSION SET CURRENT_SCHEMA = legacy;

CREATE TABLE customers (
    customer_id     NUMBER(10)      NOT NULL,
    cust_name       VARCHAR2(80)    NOT NULL,
    cust_class      VARCHAR2(1)     DEFAULT 'C' NOT NULL,   -- A/B/C class discount
    region          VARCHAR2(20),
    created_dt      DATE            DEFAULT SYSDATE,
    status          VARCHAR2(10)    DEFAULT 'ACTIVE',
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT ck_cust_class CHECK (cust_class IN ('A','B','C'))
);

CREATE TABLE credit_limits (
    customer_id     NUMBER(10)      NOT NULL,
    credit_limit    NUMBER(12,2)    NOT NULL,
    currency        VARCHAR2(3)     DEFAULT 'EUR',
    updated_dt      DATE            DEFAULT SYSDATE,
    CONSTRAINT pk_credit_limits PRIMARY KEY (customer_id),
    CONSTRAINT fk_crlim_cust FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

CREATE TABLE products (
    product_id      NUMBER(10)      NOT NULL,
    sku             VARCHAR2(20)    NOT NULL,
    descr           VARCHAR2(120),
    list_price      NUMBER(9,4)     NOT NULL,               -- 4 dp list, quirk source
    uom             VARCHAR2(10)    DEFAULT 'EA',
    status          VARCHAR2(10)    DEFAULT 'ACTIVE',
    CONSTRAINT pk_products PRIMARY KEY (product_id),
    CONSTRAINT uq_products_sku UNIQUE (sku)
);

CREATE TABLE stock (
    product_id      NUMBER(10)      NOT NULL,
    qty_on_hand     NUMBER(10)      DEFAULT 0 NOT NULL,
    qty_reserved    NUMBER(10)      DEFAULT 0 NOT NULL,
    reorder_level   NUMBER(10)      DEFAULT 0,
    updated_dt      DATE            DEFAULT SYSDATE,
    CONSTRAINT pk_stock PRIMARY KEY (product_id),
    CONSTRAINT fk_stock_prod FOREIGN KEY (product_id) REFERENCES products (product_id),
    CONSTRAINT ck_stock_nonneg CHECK (qty_on_hand >= 0 AND qty_reserved >= 0)
);

CREATE TABLE price_tiers (
    tier_id         NUMBER(10)      NOT NULL,
    product_id      NUMBER(10)      NOT NULL,
    min_qty         NUMBER(10)      NOT NULL,
    disc_pct        NUMBER(5,2)     NOT NULL,               -- percentage off list
    CONSTRAINT pk_price_tiers PRIMARY KEY (tier_id),
    CONSTRAINT fk_tiers_prod FOREIGN KEY (product_id) REFERENCES products (product_id),
    CONSTRAINT uq_tiers UNIQUE (product_id, min_qty)
);

CREATE TABLE promotions (
    promo_id        NUMBER(10)      NOT NULL,
    product_id      NUMBER(10)      NOT NULL,
    promo_price     NUMBER(9,4),                            -- absolute override
    promo_disc_pct  NUMBER(5,2),                            -- OR pct override
    start_dt        DATE            NOT NULL,
    end_dt          DATE            NOT NULL,
    CONSTRAINT pk_promotions PRIMARY KEY (promo_id),
    CONSTRAINT fk_promo_prod FOREIGN KEY (product_id) REFERENCES products (product_id)
);

CREATE TABLE orders (
    order_id        NUMBER(12)      NOT NULL,
    customer_id     NUMBER(10)      NOT NULL,
    order_dt        DATE            DEFAULT SYSDATE NOT NULL,
    status          VARCHAR2(12)    DEFAULT 'OPEN' NOT NULL,  -- OPEN/SHIPPED/INVOICED/CANCELLED
    total_amt       NUMBER(12,2),
    CONSTRAINT pk_orders PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_cust FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

CREATE TABLE order_lines (
    order_id        NUMBER(12)      NOT NULL,
    line_no         NUMBER(4)       NOT NULL,
    product_id      NUMBER(10)      NOT NULL,
    qty             NUMBER(10)      NOT NULL,
    unit_price      NUMBER(9,2)     NOT NULL,               -- post-quirk 2 dp
    line_amt        NUMBER(12,2)    NOT NULL,
    CONSTRAINT pk_order_lines PRIMARY KEY (order_id, line_no),
    CONSTRAINT fk_lines_order FOREIGN KEY (order_id) REFERENCES orders (order_id),
    CONSTRAINT fk_lines_prod FOREIGN KEY (product_id) REFERENCES products (product_id)
);

CREATE TABLE statements (
    stmt_id         NUMBER(12)      NOT NULL,
    customer_id     NUMBER(10)      NOT NULL,
    period          VARCHAR2(7)     NOT NULL,               -- 'YYYY-MM'
    open_amt        NUMBER(12,2)    DEFAULT 0 NOT NULL,
    invoiced_amt    NUMBER(12,2)    DEFAULT 0 NOT NULL,
    order_cnt       NUMBER(6)       DEFAULT 0 NOT NULL,
    run_dt          DATE            DEFAULT SYSDATE,
    CONSTRAINT pk_statements PRIMARY KEY (stmt_id),
    CONSTRAINT uq_statements UNIQUE (customer_id, period),
    CONSTRAINT fk_stmt_cust FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

CREATE TABLE audit_log (
    audit_id        NUMBER(14)      NOT NULL,
    module          VARCHAR2(30)    NOT NULL,
    action          VARCHAR2(30)    NOT NULL,
    ref_id          NUMBER(14),
    details         VARCHAR2(400),
    audit_dt        DATE            DEFAULT SYSDATE NOT NULL,
    audit_user      VARCHAR2(30)    DEFAULT USER,
    CONSTRAINT pk_audit_log PRIMARY KEY (audit_id)
);

CREATE SEQUENCE seq_orders     START WITH 100000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_statements START WITH 500000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_audit      START WITH 900000 INCREMENT BY 1 NOCACHE;

CREATE INDEX ix_orders_cust_dt ON orders (customer_id, order_dt);
CREATE INDEX ix_lines_prod     ON order_lines (product_id);
CREATE INDEX ix_promo_prod_dt  ON promotions (product_id, start_dt, end_dt);
CREATE INDEX ix_audit_module   ON audit_log (module, audit_dt);
