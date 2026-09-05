-- dim_client
DROP TABLE IF EXISTS dim_client;

CREATE TABLE dim_client
WITH (format = 'PARQUET', external_location = 's3://mon-datalake-ecommerce-7259b9/gold/dim_client') AS
SELECT DISTINCT
  customer_id, 
  firstname,
  lastname,
  email,
  city,
  country,
  company_name
FROM users_clean

UNION ALL 

SELECT -1, 'Client', 'Inconnu', 'UNKNOWN', 'UNKNOWN', 'UNKNOWN', 'UNKNOWN';