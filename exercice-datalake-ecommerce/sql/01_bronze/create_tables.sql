-- =========================================================
-- BRONZE : déclaration des tables externes sur les données brutes
-- Aucune transformation : reflet fidèle des fichiers sources
--
-- NB : la base Glue (aws_glue_catalog_database.datalake) est déjà
-- créée par Terraform (main.tf) — pas de CREATE DATABASE ici.
--
-- {{BUCKET}} est remplacé automatiquement par le nom réel du bucket
-- (sortie Terraform `bucket_name`) au moment de l'exécution — voir
-- demarrage_terraform/scripts/run_athena_query.sh
-- =========================================================

-- ---------------------------------------------------------
-- orders_raw (CSV) : tout typé en STRING (évite l'échec de
-- lecture de toute la table sur une seule valeur invalide).
--
-- Partitionnée par date d'ingestion (traçabilité et rejouabilité
-- du pipeline). Convention de nommage Hive-style attendue sur S3 :
--   bronze/orders_raw/ingestion_date=YYYY-MM-DD/orders.csv
-- MSCK REPAIR TABLE (ci-dessous) découvre automatiquement toutes
-- les partitions présentes sous ce préfixe, sans avoir besoin de
-- connaître la date à l'avance.
-- ---------------------------------------------------------
-- Supprime la définition existante (si elle date d'un schéma antérieur,
-- ex. sans PARTITIONED BY) pour garantir qu'elle est recréée à jour.
-- Ne supprime que la métadonnée Glue, jamais les fichiers S3.
DROP TABLE IF EXISTS orders_raw;

CREATE EXTERNAL TABLE IF NOT EXISTS orders_raw (
  invoiceno    string,
  productid    string,
  quantity     string,
  invoicedate  string,
  unitprice    string,
  customerid   string,
  country      string
)
PARTITIONED BY (ingestion_date string)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
LOCATION 's3://{{BUCKET}}/bronze/orders_raw/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- Découvre et enregistre les partitions ingestion_date=... déjà
-- présentes sur S3 (doit s'exécuter APRÈS l'upload des données et
-- APRÈS la création de la table ci-dessus).
MSCK REPAIR TABLE orders_raw;

-- ---------------------------------------------------------
-- products_raw (JSON Lines) : struct/array typés dès la lecture,
-- champs scalaires typés nativement (JSON porte son typage).
-- Non partitionnée (pas de besoin identifié pour cette dimension).
-- ---------------------------------------------------------
DROP TABLE IF EXISTS products_raw;

CREATE EXTERNAL TABLE IF NOT EXISTS products_raw (
  id                    int,
  title                 string,
  description           string,
  category              string,
  price                 double,
  discountPercentage    double,
  rating                double,
  stock                 int,
  tags                  array<string>,
  brand                 string,
  sku                   string,
  weight                double,
  dimensions            struct<width:double, height:double, depth:double>,
  warrantyInformation    string,
  shippingInformation    string,
  availabilityStatus     string,
  minimumOrderQuantity   int
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://{{BUCKET}}/bronze/products_raw/';

-- ---------------------------------------------------------
-- users_raw (JSON Lines) : structure imbriquée conservée telle
-- quelle (address, company). Non partitionnée.
-- ---------------------------------------------------------
DROP TABLE IF EXISTS users_raw;

CREATE EXTERNAL TABLE IF NOT EXISTS users_raw (
  id          int,
  firstname   string,
  lastname    string,
  age         int,
  gender      string,
  email       string,
  phone       string,
  username    string,
  address     struct<
    address:string,
    city:string,
    state:string,
    stateCode:string,
    postalCode:string,
    coordinates:struct<lat:double, lng:double>,
    country:string
  >,
  university  string,
  company     struct<
    department:string,
    name:string,
    title:string,
    address:struct<
      address:string,
      city:string,
      state:string,
      stateCode:string,
      postalCode:string,
      coordinates:struct<lat:double, lng:double>,
      country:string
    >
  >,
  role        string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://{{BUCKET}}/bronze/users_raw/';