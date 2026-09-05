# ==========================================================
# À placer dans demarrage_terraform/ (à côté de main.tf, iam.tf...)
#
# Orchestre l'exécution des scripts SQL du dossier sql/, dans l'ordre
# Bronze -> Silver -> Gold, via le rôle/bucket/base déjà provisionnés
# dans main.tf. S'appuie sur scripts/run_athena_query.sh.
#
# Toutes les actions (upload S3, requêtes Athena) sont exécutées en
# assumant le rôle IAM en moindre privilège aws_iam_role.pipeline
# (défini dans iam.tf), pas avec les identifiants locaux de
# l'opérateur qui lance `terraform apply`.
# ==========================================================

locals {
  sql_root    = "${path.module}/../sql"
  source_root = "${path.module}/../sources"
  runner      = "${path.module}/scripts/run_athena_query.sh"
  role_arn    = aws_iam_role.pipeline.arn
}

# Upload des fichiers bruts vers bronze/ sur S3, avant toute exécution SQL.
# Structure réelle du dossier sources/ (différente de bronze/, d'où les
# copies explicites plutôt qu'un simple `aws s3 sync` global) :
#   sources/bronze_csv/orders.csv        -> bronze/orders_raw/orders.csv
#   sources/bronze_json/products.jsonl   -> bronze/products_raw/products.jsonl
#   sources/bronze_json/users.jsonl      -> bronze/users_raw/users.jsonl
#
# L'upload assume le rôle pipeline (mêmes permissions S3 que celles
# utilisées ensuite par Athena pour lire ces fichiers).
resource "null_resource" "upload_source" {
  triggers = {
    orders_hash   = filesha1("${local.source_root}/bronze_csv/orders.csv")
    products_hash = filesha1("${local.source_root}/bronze_json/products.jsonl")
    users_hash    = filesha1("${local.source_root}/bronze_json/users.jsonl")
  }

  provisioner "local-exec" {
    command = <<-EOT
      CREDS=$(aws sts assume-role --role-arn ${local.role_arn} --role-session-name "upload-source" --duration-seconds 900 --query 'Credentials' --output json)
      export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
      export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)
      aws s3 cp ${local.source_root}/bronze_csv/orders.csv s3://${aws_s3_bucket.datalake.id}/bronze/orders_raw/orders.csv
      aws s3 cp ${local.source_root}/bronze_json/products.jsonl s3://${aws_s3_bucket.datalake.id}/bronze/products_raw/products.jsonl
      aws s3 cp ${local.source_root}/bronze_json/users.jsonl s3://${aws_s3_bucket.datalake.id}/bronze/users_raw/users.jsonl
    EOT
  }

  depends_on = [aws_s3_object.zones, aws_iam_role_policy.pipeline]
}

# ---------------- BRONZE ----------------
resource "null_resource" "bronze" {
  triggers = {
    sql_hash = filesha256("${local.sql_root}/01_bronze/create_tables.sql")
  }

  provisioner "local-exec" {
    command = "${local.runner} ${local.sql_root}/01_bronze/create_tables.sql ${aws_glue_catalog_database.datalake.name} ${aws_s3_bucket.datalake.id} ${local.role_arn}"
  }

  depends_on = [aws_glue_catalog_database.datalake, null_resource.upload_source]
}

# ---------------- SILVER ----------------
resource "null_resource" "silver_orders" {
  triggers   = { sql_hash = filesha256("${local.sql_root}/02_silver/orders_clean.sql") }
  provisioner "local-exec" {
    command = "${local.runner} ${local.sql_root}/02_silver/orders_clean.sql ${aws_glue_catalog_database.datalake.name} ${aws_s3_bucket.datalake.id} ${local.role_arn}"
  }
  depends_on = [null_resource.bronze]
}

resource "null_resource" "silver_products" {
  triggers   = { sql_hash = filesha256("${local.sql_root}/02_silver/products_clean.sql") }
  provisioner "local-exec" {
    command = "${local.runner} ${local.sql_root}/02_silver/products_clean.sql ${aws_glue_catalog_database.datalake.name} ${aws_s3_bucket.datalake.id} ${local.role_arn}"
  }
  depends_on = [null_resource.bronze]
}

resource "null_resource" "silver_users" {
  triggers   = { sql_hash = filesha256("${local.sql_root}/02_silver/users_clean.sql") }
  provisioner "local-exec" {
    command = "${local.runner} ${local.sql_root}/02_silver/users_clean.sql ${aws_glue_catalog_database.datalake.name} ${aws_s3_bucket.datalake.id} ${local.role_arn}"
  }
  depends_on = [null_resource.bronze]
}

# ---------------- GOLD ----------------
resource "null_resource" "gold_dim_date" {
  triggers   = { sql_hash = filesha256("${local.sql_root}/03_gold/dim_date.sql") }
  provisioner "local-exec" {
    command = "${local.runner} ${local.sql_root}/03_gold/dim_date.sql ${aws_glue_catalog_database.datalake.name} ${aws_s3_bucket.datalake.id} ${local.role_arn}"
  }
  depends_on = [null_resource.silver_orders]
}

resource "null_resource" "gold_dim_produit" {
  triggers   = { sql_hash = filesha256("${local.sql_root}/03_gold/dim_produit.sql") }
  provisioner "local-exec" {
    command = "${local.runner} ${local.sql_root}/03_gold/dim_produit.sql ${aws_glue_catalog_database.datalake.name} ${aws_s3_bucket.datalake.id} ${local.role_arn}"
  }
  depends_on = [null_resource.silver_products]
}

resource "null_resource" "gold_dim_client" {
  triggers   = { sql_hash = filesha256("${local.sql_root}/03_gold/dim_client.sql") }
  provisioner "local-exec" {
    command = "${local.runner} ${local.sql_root}/03_gold/dim_client.sql ${aws_glue_catalog_database.datalake.name} ${aws_s3_bucket.datalake.id} ${local.role_arn}"
  }
  depends_on = [null_resource.silver_users]
}

resource "null_resource" "gold_fact_ventes" {
  triggers   = { sql_hash = filesha256("${local.sql_root}/03_gold/fact_ventes.sql") }
  provisioner "local-exec" {
    command = "${local.runner} ${local.sql_root}/03_gold/fact_ventes.sql ${aws_glue_catalog_database.datalake.name} ${aws_s3_bucket.datalake.id} ${local.role_arn}"
  }
  depends_on = [
    null_resource.gold_dim_date,
    null_resource.gold_dim_produit,
    null_resource.gold_dim_client
  ]
}
