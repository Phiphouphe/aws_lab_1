-- orders_clean
DROP TABLE IF EXISTS orders_clean;

CREATE TABLE orders_clean 
WITH (
    format = 'PARQUET',
    parquet_compression = 'SNAPPY',
    external_location = 's3://mon-datalake-ecommerce-7259b9/silver/orders_clean/'
) AS
SELECT DISTINCT 
  invoiceno,
  TRY_CAST(productid AS INTEGER) AS product_id,
  TRY_CAST(quantity AS INTEGER) AS quantity,
  TRY_CAST(unitprice AS DOUBLE) AS unit_price,
  TRY_CAST(quantity AS INTEGER) * TRY_CAST(unitprice AS DOUBLE) AS line_amount,
  TRY_CAST(customerid AS INTEGER) AS customer_id,
  CASE 
    WHEN UPPER(TRIM(country)) IN ('FRANCE', 'FRANCEE', 'FRNACE') THEN 'FR'
    WHEN UPPER(TRIM(country)) IN ('U.K.', 'UNITED KINGDOM') THEN 'GB'
    WHEN UPPER(TRIM(country)) IN ('U.S.A', 'UNITED STATES') THEN 'US'
    WHEN UPPER(TRIM(country)) IN ('NETHERLANDS', 'PAYS-BAS') THEN 'NL'
    WHEN UPPER(TRIM(country)) IN ('BELGIUM', 'BELGIQUE') THEN 'BE'
    WHEN UPPER(TRIM(country)) IN ('ITALY', 'ITALIE') THEN 'IT'
    WHEN UPPER(TRIM(country)) IN ('PORTUGAL') THEN 'PT'
    WHEN UPPER(TRIM(country)) IN ('GERMANY', 'ALLEMAGNE') THEN 'DE'
    WHEN UPPER(TRIM(country)) IN ('SPAIN', 'ESPAGNE') THEN 'ES'
    WHEN UPPER(TRIM(country)) IN ('SWITZERLAND', 'SUISSE') THEN 'CH'
    ELSE 'UNKNOWN'
  END AS country,
  (TRY_CAST(quantity AS INTEGER) < 0 OR invoiceno LIKE 'C%') AS is_return,
  CASE 
    WHEN invoicedate LIKE '%/%'
      THEN TRY_CAST(
        TRY(date_parse(invoicedate, '%d/%m/%Y')) AS DATE)
    ELSE TRY_CAST(
      SUBSTR(invoicedate, 1, 10) AS DATE)
  END AS invoice_date
FROM orders_raw
WHERE 
  TRY_CAST(quantity AS INTEGER) IS NOT NULL 
  AND TRY_CAST(unitprice AS DOUBLE) != 0 
  AND CASE 
    WHEN invoicedate LIKE '%/%'
      THEN TRY_CAST(
        TRY(date_parse(invoicedate, '%d/%m/%Y')) AS DATE)
    ELSE TRY_CAST(
      SUBSTR(invoicedate, 1, 10) AS DATE)
  END IS NOT NULL 
  AND NOT (TRY_CAST(unitprice AS DOUBLE) < 0 AND TRY_CAST(quantity AS INTEGER) > 0);
