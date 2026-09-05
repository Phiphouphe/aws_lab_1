-- products_clean
DROP TABLE IF EXISTS products_clean;

CREATE TABLE products_clean
WITH (
    format='Parquet',
    parquet_compression='SNAPPY',
    external_location='s3://mon-datalake-ecommerce-7259b9/silver/products_clean/'
) AS 
SELECT DISTINCT 
  id AS product_id,
  title,
  category, 
  COALESCE(brand, 'UNKNOWN') AS brand,
  price AS catalog_price,
  ROUND(price * (1 - discountpercentage / 100), 2) AS discounted_price,
  stock,
  dimensions.width AS largeur,
  dimensions.height AS hauteur,
  dimensions.depth AS profondeur
FROM products_raw;