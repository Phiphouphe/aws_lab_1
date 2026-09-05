-- fact_ventes
DROP TABLE IF EXISTS fact_ventes;

CREATE TABLE fact_ventes
WITH (format = 'PARQUET', external_location = 's3://mon-datalake-ecommerce-7259b9/gold/fact_ventes') AS
SELECT DISTINCT
  o.invoiceno, 
  CAST(date_format(o.invoice_date, '%Y%m%d') AS INTEGER) AS date_id,
  CASE 
    WHEN o.product_id IS NULL 
      OR o.product_id NOT IN (SELECT product_id FROM dim_produit WHERE product_id != -1)
    THEN -1
    ELSE o.product_id
  END AS product_id,
  CASE 
    WHEN o.customer_id IS NULL 
      OR o.customer_id NOT IN (SELECT customer_id FROM dim_client WHERE customer_id != -1)
    THEN -1
    ELSE o.customer_id
  END AS customer_id,
  o.country,
  o.quantity,
  o.unit_price,
  o.line_amount,
  o.is_return
FROM orders_clean o;