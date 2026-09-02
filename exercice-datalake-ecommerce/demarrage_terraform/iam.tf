# ---------------------------------------------------------------------------
# IAM — rôle dédié au projet, en moindre privilège. Séparé de main.tf pour
# isoler la partie gouvernance/sécurité du reste de l'infrastructure.
# ---------------------------------------------------------------------------

# TODO — data "aws_iam_policy_document" "assume_role" : autorise sts:AssumeRole
# pour un principal de votre propre compte
# (identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"])

# 1. Document de policy qui définit QUI a le droit d'endosser ("assume") le rôle
data "aws_iam_policy_document" "assume_role" {
  statement {
    # L'action autorisée : endosser ce rôle
    actions = ["sts:AssumeRole"]

    # Qui a le droit de le faire (le "principal")
    principals {
      type        = "AWS"  # un principal de type compte/utilisateur AWS (pas un service)
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
      # "root" du compte = toi-même (n'importe quel identifiant IAM de TON compte)
    }
  }
}

# TODO — resource "aws_iam_role" "pipeline" avec cette assume_role_policy.
# C'est ce rôle que vous assumerez (via `aws sts assume-role`) pour ingérer
# et interroger les données, plutôt que d'utiliser vos identifiants admin.

# 2. Le rôle IAM lui-même, qui utilise le document ci-dessus comme "trust policy"
resource "aws_iam_role" "pipeline" {
  name               = "${var.project_name}-pipeline-role"       # nom du rôle
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  # .json convertit le bloc HCL ci-dessus en JSON, format attendu par AWS
}

# TODO — data "aws_iam_policy_document" "pipeline" : accès scopé à VOTRE
# bucket uniquement —
#   - S3 : List/Get/Put/Delete sur bronze/*, silver/*, gold/*, athena-results/*
#   - Athena : StartQueryExecution, GetQueryExecution, GetQueryResults,
#     StopQueryExecution, GetWorkGroup — sur le workgroup "primary"
#     (arn:aws:athena:<region>:<account_id>:workgroup/primary)
#   - Glue : Get/Create/Update/Delete Table — sur VOTRE base uniquement

# 3. Document de policy qui définit CE QUE le rôle a le droit de faire une fois endossé
data "aws_iam_policy_document" "pipeline" {

  # --- Permissions S3 ---
  statement {
    sid = "S3Access"  # identifiant du bloc, juste pour lisibilité
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.datalake.arn,                       # le bucket lui-même (pour ListBucket)
      "${aws_s3_bucket.datalake.arn}/bronze/*",
      "${aws_s3_bucket.datalake.arn}/silver/*",
      "${aws_s3_bucket.datalake.arn}/gold/*",
      "${aws_s3_bucket.datalake.arn}/athena-results/*",
    ]
  }

  # --- Permissions Athena ---
  statement {
    sid = "AthenaAccess"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
      "athena:GetWorkGroup",
    ]
    resources = [
      "arn:aws:athena:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workgroup/primary"
    ]
  }

  # --- Permissions Glue ---
  statement {
    sid = "GlueAccess"
    actions = [
      "glue:GetTable",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
      aws_glue_catalog_database.datalake.arn,
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.glue_database}/*",
    ]
  }
}

# TODO — resource "aws_iam_role_policy" "pipeline" pour attacher la policy
# ci-dessus au rôle.

# 4. On attache la policy (le "quoi faire") au rôle (le "qui")
resource "aws_iam_role_policy" "pipeline" {
  name   = "${var.project_name}-pipeline-policy"
  role   = aws_iam_role.pipeline.id           # à QUEL rôle on attache
  policy = data.aws_iam_policy_document.pipeline.json  # QUELLE policy (en JSON)
}
