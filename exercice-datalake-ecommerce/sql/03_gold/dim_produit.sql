--dim_produit
DROP TABLE IF EXISTS dim_produit;

CREATE TABLE dim_produit
WITH (format = 'PARQUET', external_location = 's3://{{BUCKET}}/gold/dim_produit') AS
SELECT DISTINCT
  product_id, 
  title,
  category,
  brand,
  catalog_price,
  discounted_price
FROM products_clean

UNION ALL 

SELECT -1, 'Produit inconnu', 'UNKNOWN', 'UNKNOWN', NULL, NULL;