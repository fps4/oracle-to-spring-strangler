-- =====================================================================
--  V3 -- pinned anchor reference data, migrated Oracle -> PostgreSQL.
--
--  HONESTY NOTE (ADR-0004): this migration is the stand-in for a DMS
--  full load. It carries ONLY the hand-pinned anchor rows from
--  legacy/db/init/05_seed.sql (values copied verbatim) so the target
--  answers the same demo/parity questions as the specimen. The
--  DBMS_RANDOM bulk history (1000 orders etc.) is NOT reproducible
--  outside Oracle and is deliberately absent here; migrating live data
--  is the M2 parity / M3 data-sync story, not a Flyway script.
--
--  The evergreen-promotion exception carries over: windows anchor on
--  CURRENT_DATE (migration day) exactly as the Oracle seed anchors on
--  TRUNC(SYSDATE) (first boot) -- dates differ, values don't.
-- =====================================================================

INSERT INTO legacy.customers VALUES (1, 'NORDWIND WHOLESALE GMBH',  'A', 'DE-NORTH', DATE '2004-03-15', 'ACTIVE');
INSERT INTO legacy.customers VALUES (2, 'BALTIC TRADE PARTNERS OY', 'B', 'FI',       DATE '2005-11-02', 'ACTIVE');
INSERT INTO legacy.customers VALUES (3, 'KLEINHANDEL MUELLER KG',   'C', 'DE-SOUTH', DATE '2007-06-20', 'ACTIVE');

-- customer 3 = the credit-reject specimen (limit 500)
INSERT INTO legacy.credit_limits VALUES (1, 250000, 'EUR', DATE '2019-01-10');
INSERT INTO legacy.credit_limits VALUES (2,  50000, 'EUR', DATE '2019-01-10');
INSERT INTO legacy.credit_limits VALUES (3,    500, 'EUR', DATE '2012-04-01');

-- 1002 = 4dp list price, the TRUNC specimen; 1003 = low-stock specimen;
-- 1004 = promo specimen
INSERT INTO legacy.products VALUES (1000, 'SKU-1000', 'INDUSTRIAL FASTENER M8 BOX', 19.99,   'BOX', 'ACTIVE');
INSERT INTO legacy.products VALUES (1001, 'SKU-1001', 'BEARING ASSEMBLY 6204',       7.49,   'EA',  'ACTIVE');
INSERT INTO legacy.products VALUES (1002, 'SKU-1002', 'HYDRAULIC SEAL KIT 40MM',    12.3456, 'KIT', 'ACTIVE');
INSERT INTO legacy.products VALUES (1003, 'SKU-1003', 'PRECISION SHIM SET 0.05MM',  45.90,   'SET', 'ACTIVE');
INSERT INTO legacy.products VALUES (1004, 'SKU-1004', 'COOLANT CONCENTRATE 5L',     24.6800, 'CAN', 'ACTIVE');

INSERT INTO legacy.stock VALUES (1000, 5000, 0, 200, DATE '2026-01-01');
INSERT INTO legacy.stock VALUES (1001, 8000, 0, 500, DATE '2026-01-01');
INSERT INTO legacy.stock VALUES (1002, 3000, 0, 100, DATE '2026-01-01');
INSERT INTO legacy.stock VALUES (1003,    5, 0,  10, DATE '2026-01-01');
INSERT INTO legacy.stock VALUES (1004, 1200, 0, 100, DATE '2026-01-01');

INSERT INTO legacy.price_tiers VALUES (1, 1000,  10,  5);
INSERT INTO legacy.price_tiers VALUES (2, 1000,  50, 10);
INSERT INTO legacy.price_tiers VALUES (3, 1000, 200, 15);
INSERT INTO legacy.price_tiers VALUES (4, 1002,  25,  7.5);
INSERT INTO legacy.price_tiers VALUES (5, 1004,  20,  5);

-- evergreen promos (the documented date exception)
INSERT INTO legacy.promotions VALUES (1, 1004, 19.9999, NULL, CURRENT_DATE - 30, CURRENT_DATE + 365);
INSERT INTO legacy.promotions VALUES (2, 1001, NULL,    12.5, CURRENT_DATE - 30, CURRENT_DATE + 365);
INSERT INTO legacy.promotions VALUES (3, 1003, 39.9900, NULL, CURRENT_DATE - 30, CURRENT_DATE + 365);
