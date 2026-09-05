-- dim_date
DROP TABLE IF EXISTS dim_date;

CREATE TABLE dim_date
WITH (format = 'PARQUET', external_location = 's3://mon-datalake-ecommerce-7259b9/gold/dim_date') AS
SELECT DISTINCT
  CAST(date_format(invoice_date, '%Y%m%d') AS INTEGER) AS date_id, 
  invoice_date AS full_date,
  YEAR(invoice_date) AS year,
  MONTH(invoice_date) AS month,
  date_format(invoice_date, '%M') AS month_name,
  DAY(invoice_date) AS day,
  QUARTER(invoice_date) AS quarter
FROM orders_clean
WHERE invoice_date IS NOT NULL;