-- users_clean
DROP TABLE IF EXISTS users_clean;

CREATE TABLE users_clean
WITH (
    format='Parquet',
    parquet_compression='SNAPPY',
    external_location='s3://mon-datalake-ecommerce-7259b9/silver/users_clean/'
) AS 
SELECT DISTINCT 
  id AS customer_id,
  firstname,
  lastname, 
  email,
  address.city AS city,
  address.country AS country,
  company.name AS company_name
FROM users_raw;