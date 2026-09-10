# ==========================================================
# ORCHESTRATION DATALAKE
# Upload -> Bronze -> Silver -> Gold
# ==========================================================

locals {
  sql_root    = "${path.module}/../sql"
  source_root = "${path.module}/../sources"
  runner      = "${path.module}/scripts/run_athena_query.sh"
  role_arn    = aws_iam_role.pipeline.arn
  bucket      = aws_s3_bucket.datalake.id
}

# ==========================================================
# UPLOAD SOURCE -> S3 BRONZE
# ==========================================================

resource "null_resource" "upload_source" {

  triggers = {
    orders_hash   = filesha1("${local.source_root}/bronze_csv/orders.csv")
    products_hash = filesha1("${local.source_root}/bronze_json/products.jsonl")
    users_hash    = filesha1("${local.source_root}/bronze_json/users.jsonl")
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      CREDS=$(aws sts assume-role \
        --role-arn ${local.role_arn} \
        --role-session-name "upload-source" \
        --duration-seconds 900 \
        --query 'Credentials' \
        --output json)

      export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)

      INGESTION_DATE=$(date +%F)

      aws s3 cp \
        ${local.source_root}/bronze_csv/orders.csv \
        s3://${local.bucket}/bronze/orders_raw/ingestion_date=$INGESTION_DATE/orders.csv

      aws s3 cp \
        ${local.source_root}/bronze_json/products.jsonl \
        s3://${local.bucket}/bronze/products_raw/products.jsonl

      aws s3 cp \
        ${local.source_root}/bronze_json/users.jsonl \
        s3://${local.bucket}/bronze/users_raw/users.jsonl
    EOT
  }

  depends_on = [
    aws_s3_object.zones,
    aws_iam_role_policy.pipeline
  ]
}


# ==========================================================
# BRONZE
# ==========================================================

resource "null_resource" "bronze" {

  triggers = {
    sql_hash  = filesha256("${local.sql_root}/01_bronze/create_tables.sql")
    upload_id = null_resource.upload_source.id
  }

  provisioner "local-exec" {
    command = "${local.runner} ${local.sql_root}/01_bronze/create_tables.sql ${aws_glue_catalog_database.datalake.name} ${local.bucket} ${local.role_arn}"
  }

  depends_on = [
    aws_glue_catalog_database.datalake,
    null_resource.upload_source
  ]
}


# ==========================================================
# SILVER ORDERS
# ==========================================================

resource "null_resource" "silver_orders" {

  triggers = {
    sql_hash  = filesha256("${local.sql_root}/02_silver/orders_clean.sql")
    bronze_id = null_resource.bronze.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      CREDS=$(aws sts assume-role \
        --role-arn ${local.role_arn} \
        --role-session-name "cleanup-silver-orders" \
        --duration-seconds 900 \
        --query 'Credentials' \
        --output json)

      export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)

      aws s3 rm s3://${local.bucket}/silver/orders_clean/ --recursive || true

      ${local.runner} ${local.sql_root}/02_silver/orders_clean.sql ${aws_glue_catalog_database.datalake.name} ${local.bucket} ${local.role_arn}
    EOT
  }

  depends_on = [
    null_resource.bronze
  ]
}


# ==========================================================
# SILVER PRODUCTS
# ==========================================================

resource "null_resource" "silver_products" {

  triggers = {
    sql_hash  = filesha256("${local.sql_root}/02_silver/products_clean.sql")
    bronze_id = null_resource.bronze.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      CREDS=$(aws sts assume-role \
        --role-arn ${local.role_arn} \
        --role-session-name "cleanup-silver-products" \
        --duration-seconds 900 \
        --query 'Credentials' \
        --output json)

      export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)

      aws s3 rm s3://${local.bucket}/silver/products_clean/ --recursive || true

      ${local.runner} ${local.sql_root}/02_silver/products_clean.sql ${aws_glue_catalog_database.datalake.name} ${local.bucket} ${local.role_arn}
    EOT
  }

  depends_on = [
    null_resource.bronze
  ]
}


# ==========================================================
# SILVER USERS
# ==========================================================

resource "null_resource" "silver_users" {

  triggers = {
    sql_hash  = filesha256("${local.sql_root}/02_silver/users_clean.sql")
    bronze_id = null_resource.bronze.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      CREDS=$(aws sts assume-role \
        --role-arn ${local.role_arn} \
        --role-session-name "cleanup-silver-users" \
        --duration-seconds 900 \
        --query 'Credentials' \
        --output json)

      export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)

      aws s3 rm s3://${local.bucket}/silver/users_clean/ --recursive || true

      ${local.runner} ${local.sql_root}/02_silver/users_clean.sql ${aws_glue_catalog_database.datalake.name} ${local.bucket} ${local.role_arn}
    EOT
  }

  depends_on = [
    null_resource.bronze
  ]
}


# ==========================================================
# GOLD DIM DATE
# ==========================================================

resource "null_resource" "gold_dim_date" {

  triggers = {
    sql_hash  = filesha256("${local.sql_root}/03_gold/dim_date.sql")
    silver_id = null_resource.silver_orders.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      CREDS=$(aws sts assume-role \
        --role-arn ${local.role_arn} \
        --role-session-name "cleanup-gold-date" \
        --duration-seconds 900 \
        --query 'Credentials' \
        --output json)

      export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)

      aws s3 rm s3://${local.bucket}/gold/dim_date/ --recursive || true

      ${local.runner} ${local.sql_root}/03_gold/dim_date.sql ${aws_glue_catalog_database.datalake.name} ${local.bucket} ${local.role_arn}
    EOT
  }

  depends_on = [
    null_resource.silver_orders
  ]
}


# ==========================================================
# GOLD DIM PRODUIT
# ==========================================================

resource "null_resource" "gold_dim_produit" {

  triggers = {
    sql_hash  = filesha256("${local.sql_root}/03_gold/dim_produit.sql")
    silver_id = null_resource.silver_products.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      CREDS=$(aws sts assume-role \
        --role-arn ${local.role_arn} \
        --role-session-name "cleanup-gold-produit" \
        --duration-seconds 900 \
        --query 'Credentials' \
        --output json)

      export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)

      aws s3 rm s3://${local.bucket}/gold/dim_produit/ --recursive || true

      ${local.runner} ${local.sql_root}/03_gold/dim_produit.sql ${aws_glue_catalog_database.datalake.name} ${local.bucket} ${local.role_arn}
    EOT
  }

  depends_on = [
    null_resource.silver_products
  ]
}


# ==========================================================
# GOLD DIM CLIENT
# ==========================================================

resource "null_resource" "gold_dim_client" {

  triggers = {
    sql_hash  = filesha256("${local.sql_root}/03_gold/dim_client.sql")
    silver_id = null_resource.silver_users.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      CREDS=$(aws sts assume-role \
        --role-arn ${local.role_arn} \
        --role-session-name "cleanup-gold-client" \
        --duration-seconds 900 \
        --query 'Credentials' \
        --output json)

      export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)

      aws s3 rm s3://${local.bucket}/gold/dim_client/ --recursive || true

      ${local.runner} ${local.sql_root}/03_gold/dim_client.sql ${aws_glue_catalog_database.datalake.name} ${local.bucket} ${local.role_arn}
    EOT
  }

  depends_on = [
    null_resource.silver_users
  ]
}


# ==========================================================
# GOLD FACT VENTES
# ==========================================================

resource "null_resource" "gold_fact_ventes" {

  triggers = {
    sql_hash       = filesha256("${local.sql_root}/03_gold/fact_ventes.sql")
    dim_date_id    = null_resource.gold_dim_date.id
    dim_produit_id = null_resource.gold_dim_produit.id
    dim_client_id  = null_resource.gold_dim_client.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      CREDS=$(aws sts assume-role \
        --role-arn ${local.role_arn} \
        --role-session-name "cleanup-gold-fact" \
        --duration-seconds 900 \
        --query 'Credentials' \
        --output json)

      export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)

      aws s3 rm s3://${local.bucket}/gold/fact_ventes/ --recursive || true

      ${local.runner} ${local.sql_root}/03_gold/fact_ventes.sql ${aws_glue_catalog_database.datalake.name} ${local.bucket} ${local.role_arn}
    EOT
  }

  depends_on = [
    null_resource.gold_dim_date,
    null_resource.gold_dim_produit,
    null_resource.gold_dim_client
  ]
}