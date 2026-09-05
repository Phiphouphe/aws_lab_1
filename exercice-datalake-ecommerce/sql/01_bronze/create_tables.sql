CREATE EXTERNAL TABLE IF NOT EXISTS orders_raw (
  InvoiceNo string,
  ProductID string,
  Quantity string,
  InvoiceDate string,
  UnitPrice string,
  CustomerID string,
  Country string
  -- tout en string pour le CSV brut, comme vu (évite l'échec de lecture sur valeur invalide)
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
LOCATION 's3://mon-datalake-ecommerce-7259b9/bronze/orders_raw/ingestion_date=2026-08-23/'
TBLPROPERTIES ('skip.header.line.count'='1');

CREATE EXTERNAL TABLE IF NOT EXISTS products_raw (
  id int,
  title string,
  description string,
  category string,
  price double,
  discountPercentage double,
  rating double,
  stock int,
  tags array<string>,
  brand string,
  sku string,
  weight int,
  dimensions struct<width:double, height:double, depth:double>,
  warrantyInformation string,
  shippingInformation string,
  availabilityStatus string,
  minimumOrderQuantity int
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://mon-datalake-ecommerce-7259b9/bronze/products_raw/ingestion_date=2026-08-23/';

CREATE EXTERNAL TABLE IF NOT EXISTS users_raw (
  id int,
  firstName string,
  lastName string,
  age int,
  gender string,
  email string,
  phone string,
  username string,
  address struct<address:string, city:string, state:string, stateCode:string, postalCode:string, coordinates:struct<lat:double, lng:double>, country:string>,
  university string,
  company struct<department:string, name:string, title:string, address:struct<address:string, city:string, state:string, stateCode:string, postalCode:string, coordinates:struct<lat:double, lng:double>, country:string>>,
  role string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://mon-datalake-ecommerce-7259b9/bronze/users_raw/ingestion_date=2026-08-23/';