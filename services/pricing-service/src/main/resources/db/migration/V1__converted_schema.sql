-- =====================================================================
--  V1 -- LEGACY schema converted Oracle 21c -> PostgreSQL 16.
--  Conversion follows AWS SCT's documented mapping rules; every place
--  the mechanical conversion was wrong or unusable is tagged
--  [HAND-FIX n] and explained in docs/sct-notes.md (FS-0003 scope 2).
--  Source of truth for the original DDL: legacy/db/init/01_schema.sql.
--
--  Flyway owns all schema changes (FS-0003 acceptance criterion).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS legacy;

CREATE TABLE legacy.customers (
    customer_id     bigint          NOT NULL,                    -- [HAND-FIX 1] NUMBER(10) id -> bigint, not numeric(10,0)
    cust_name       varchar(80)     NOT NULL,
    cust_class      varchar(1)      DEFAULT 'C' NOT NULL,
    region          varchar(20),
    created_dt      timestamp(0)    DEFAULT LOCALTIMESTAMP,      -- [HAND-FIX 2] Oracle DATE -> timestamp(0); [HAND-FIX 3] SYSDATE -> LOCALTIMESTAMP
    status          varchar(10)     DEFAULT 'ACTIVE',
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT ck_cust_class CHECK (cust_class IN ('A','B','C'))
);

CREATE TABLE legacy.credit_limits (
    customer_id     bigint          NOT NULL,
    credit_limit    numeric(12,2)   NOT NULL,
    currency        varchar(3)      DEFAULT 'EUR',
    updated_dt      timestamp(0)    DEFAULT LOCALTIMESTAMP,
    CONSTRAINT pk_credit_limits PRIMARY KEY (customer_id),
    CONSTRAINT fk_crlim_cust FOREIGN KEY (customer_id) REFERENCES legacy.customers (customer_id)
);

CREATE TABLE legacy.products (
    product_id      bigint          NOT NULL,
    sku             varchar(20)     NOT NULL,
    descr           varchar(120),
    list_price      numeric(9,4)    NOT NULL,                    -- 4 dp list preserved: the TRUNC-quirk source
    uom             varchar(10)     DEFAULT 'EA',
    status          varchar(10)     DEFAULT 'ACTIVE',
    CONSTRAINT pk_products PRIMARY KEY (product_id),
    CONSTRAINT uq_products_sku UNIQUE (sku)
);

CREATE TABLE legacy.stock (
    product_id      bigint          NOT NULL,
    qty_on_hand     bigint          DEFAULT 0 NOT NULL,
    qty_reserved    bigint          DEFAULT 0 NOT NULL,
    reorder_level   bigint          DEFAULT 0,
    updated_dt      timestamp(0)    DEFAULT LOCALTIMESTAMP,
    CONSTRAINT pk_stock PRIMARY KEY (product_id),
    CONSTRAINT fk_stock_prod FOREIGN KEY (product_id) REFERENCES legacy.products (product_id),
    CONSTRAINT ck_stock_nonneg CHECK (qty_on_hand >= 0 AND qty_reserved >= 0)
);

CREATE TABLE legacy.price_tiers (
    tier_id         bigint          NOT NULL,
    product_id      bigint          NOT NULL,
    min_qty         bigint          NOT NULL,
    disc_pct        numeric(5,2)    NOT NULL,
    CONSTRAINT pk_price_tiers PRIMARY KEY (tier_id),
    CONSTRAINT fk_tiers_prod FOREIGN KEY (product_id) REFERENCES legacy.products (product_id),
    CONSTRAINT uq_tiers UNIQUE (product_id, min_qty)
);

CREATE TABLE legacy.promotions (
    promo_id        bigint          NOT NULL,
    product_id      bigint          NOT NULL,
    promo_price     numeric(9,4),
    promo_disc_pct  numeric(5,2),
    start_dt        timestamp(0)    NOT NULL,
    end_dt          timestamp(0)    NOT NULL,
    CONSTRAINT pk_promotions PRIMARY KEY (promo_id),
    CONSTRAINT fk_promo_prod FOREIGN KEY (product_id) REFERENCES legacy.products (product_id)
);

CREATE TABLE legacy.orders (
    order_id        bigint          NOT NULL,
    customer_id     bigint          NOT NULL,
    order_dt        timestamp(0)    DEFAULT LOCALTIMESTAMP NOT NULL,
    status          varchar(12)     DEFAULT 'OPEN' NOT NULL,
    total_amt       numeric(12,2),
    CONSTRAINT pk_orders PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_cust FOREIGN KEY (customer_id) REFERENCES legacy.customers (customer_id)
);

CREATE TABLE legacy.order_lines (
    order_id        bigint          NOT NULL,
    line_no         smallint        NOT NULL,                    -- [HAND-FIX 1] NUMBER(4) -> smallint
    product_id      bigint          NOT NULL,
    qty             bigint          NOT NULL,
    unit_price      numeric(9,2)    NOT NULL,
    line_amt        numeric(12,2)   NOT NULL,
    CONSTRAINT pk_order_lines PRIMARY KEY (order_id, line_no),
    CONSTRAINT fk_lines_order FOREIGN KEY (order_id) REFERENCES legacy.orders (order_id),
    CONSTRAINT fk_lines_prod FOREIGN KEY (product_id) REFERENCES legacy.products (product_id)
);

CREATE TABLE legacy.statements (
    stmt_id         bigint          NOT NULL,
    customer_id     bigint          NOT NULL,
    period          varchar(7)      NOT NULL,
    open_amt        numeric(12,2)   DEFAULT 0 NOT NULL,
    invoiced_amt    numeric(12,2)   DEFAULT 0 NOT NULL,
    order_cnt       integer         DEFAULT 0 NOT NULL,
    run_dt          timestamp(0)    DEFAULT LOCALTIMESTAMP,
    CONSTRAINT pk_statements PRIMARY KEY (stmt_id),
    CONSTRAINT uq_statements UNIQUE (customer_id, period),
    CONSTRAINT fk_stmt_cust FOREIGN KEY (customer_id) REFERENCES legacy.customers (customer_id)
);

CREATE TABLE legacy.audit_log (
    audit_id        bigint          NOT NULL,
    module          varchar(30)     NOT NULL,
    action          varchar(30)     NOT NULL,
    ref_id          bigint,
    details         varchar(400),
    audit_dt        timestamp(0)    DEFAULT LOCALTIMESTAMP NOT NULL,
    audit_user      varchar(30)     DEFAULT current_user,        -- [HAND-FIX 4] Oracle USER -> current_user
    CONSTRAINT pk_audit_log PRIMARY KEY (audit_id)
);

-- NOCACHE dropped: PG sequences default CACHE 1, which is what NOCACHE meant
CREATE SEQUENCE legacy.seq_orders     START WITH 100000 INCREMENT BY 1;
CREATE SEQUENCE legacy.seq_statements START WITH 500000 INCREMENT BY 1;
CREATE SEQUENCE legacy.seq_audit      START WITH 900000 INCREMENT BY 1;

CREATE INDEX ix_orders_cust_dt ON legacy.orders (customer_id, order_dt);
CREATE INDEX ix_lines_prod     ON legacy.order_lines (product_id);
CREATE INDEX ix_promo_prod_dt  ON legacy.promotions (product_id, start_dt, end_dt);
CREATE INDEX ix_audit_module   ON legacy.audit_log (module, audit_dt);
