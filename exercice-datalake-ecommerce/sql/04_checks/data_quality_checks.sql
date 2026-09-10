-- =========================================================
-- CONTRÔLES QUALITÉ : preuves que les règles détectent
-- réellement les anomalies (avant nettoyage / après nettoyage)
-- =========================================================

SELECT COUNT(*) AS total_orders_raw FROM orders_raw WHERE ingestion_date IS NOT NULL;
SELECT COUNT(*) AS total_orders_clean FROM orders_clean;

SELECT COUNT(*) AS reste_unit_price_zero FROM orders_clean WHERE unit_price = 0;
SELECT COUNT(*) AS reste_prix_negatif_incoherent FROM orders_clean WHERE unit_price < 0 AND quantity > 0;
SELECT COUNT(*) AS reste_date_nulle FROM orders_clean WHERE invoice_date IS NULL;
SELECT COUNT(*) AS reste_quantity_nulle FROM orders_clean WHERE quantity IS NULL;

SELECT COUNT(*) AS incoherence_is_return
FROM orders_clean WHERE invoiceno LIKE 'C%' AND is_return = false;

SELECT DISTINCT country FROM orders_clean ORDER BY country;

SELECT COUNT(*) AS orphelins_produit_silver
FROM orders_clean o
LEFT JOIN products_clean p ON o.product_id = p.product_id
WHERE p.product_id IS NULL;

SELECT COUNT(*) AS orphelins_client_silver
FROM orders_clean o
LEFT JOIN users_clean u ON o.customer_id = u.customer_id
WHERE u.customer_id IS NULL;

SELECT
  'product_id' AS type_orphelin,
  COUNT(*) AS nb_lignes,
  ROUND(SUM(line_amount), 2) AS ca_concerne,
  SUM(quantity) AS unites_concernees
FROM fact_ventes WHERE product_id = -1

UNION ALL

SELECT
  'customer_id',
  COUNT(*),
  ROUND(SUM(line_amount), 2),
  SUM(quantity)
FROM fact_ventes WHERE customer_id = -1;

SELECT date_id, COUNT(*) FROM dim_date GROUP BY date_id HAVING COUNT(*) > 1;
SELECT product_id, COUNT(*) FROM dim_produit GROUP BY product_id HAVING COUNT(*) > 1;
SELECT customer_id, COUNT(*) FROM dim_client GROUP BY customer_id HAVING COUNT(*) > 1;

SELECT ROUND(SUM(line_amount), 2) AS ca_total FROM fact_ventes;