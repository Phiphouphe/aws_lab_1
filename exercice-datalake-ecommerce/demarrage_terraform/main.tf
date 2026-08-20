terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# S3 = espace de noms global à tout AWS : ce suffixe aléatoire évite les
# collisions de nom de bucket avec d'autres comptes.
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  bucket_name   = "${var.project_name}-${random_id.suffix.hex}"
  glue_database = replace("${var.project_name}_${random_id.suffix.hex}", "-", "_")
}

# ---------------------------------------------------------------------------
# TODO 1 — S3 : le Data Lake (bronze / silver / gold / athena-results)
# ---------------------------------------------------------------------------
# - resource "aws_s3_bucket" "datalake" { bucket = local.bucket_name, ... }
#   -> force_destroy = true (sinon `terraform destroy` échouera en fin d'exercice)
#   -> pas besoin de déclarer versioning/chiffrement/blocage d'accès public :
#      un bucket S3 créé aujourd'hui a déjà ces protections par défaut.
# - resource "aws_s3_object" "zones" pour créer les préfixes bronze/, silver/,
#   gold/, athena-results/ (astuce : for_each sur un toset(["bronze/", ...]))

resource "aws_s3_bucket" "datalake" {
  bucket = local.bucket_name
  force_destroy = true
}

resource "aws_s3_object" "zones" {
  for_each = toset(["bronze/", "silver/", "gold/", "athena-results/"])

  bucket = aws_s3_bucket.datalake.id
  key = each.value
}

# ---------------------------------------------------------------------------
# TODO 2 — Glue Data Catalog : base logique utilisée par Athena
# ---------------------------------------------------------------------------
# - resource "aws_glue_catalog_database" "datalake" { name = local.glue_database }

# Le rôle IAM en moindre privilège est un fichier à part : voir iam.tf.
# Pas de workgroup Athena dédié à créer : le workgroup "primary" (déjà présent
# par défaut) suffit — chaque requête Athena précisera son propre emplacement
# de résultat (s3://.../athena-results/) au moment de l'appel.

resource "aws_glue_catalog_database" "datalake" {
  name = local.glue_database
}


# ---------------------------------------------------------------------------
# TODO 3 — AWS Budgets : alerte de coût sur le projet
# ---------------------------------------------------------------------------
# - resource "aws_budgets_budget" avec au moins un bloc "notification"
#   (comparison_operator, threshold, threshold_type, notification_type,
#   subscriber_email_addresses = [var.budget_alert_email])

resource "aws_budgets_budget" "notification" {
  # Type de budget : "COST" = on surveille un montant dépensé en $
  # (autres valeurs possibles : "USAGE", "RI_UTILIZATION", etc. — pas utile ici)
  budget_type = "COST"

  # Le montant limite du budget. On réutilise var.budget_limit_usd (= 20 par
  # défaut) plutôt qu'écrire 20 en dur, pour rester paramétrable via tfvars.
  limit_amount = var.budget_limit_usd

  # Unité monétaire du montant ci-dessus
  limit_unit = "USD"

  # Période sur laquelle le budget est recalculé : ici mensuel.
  # (autres valeurs possibles : "QUARTERLY", "ANNUALLY")
  time_unit = "MONTHLY"

  # Bloc imbriqué : définit QUAND et À QUI envoyer une alerte.
  # On peut en mettre plusieurs (ex: un à 80%, un autre à 100%),
  # ici on en met un seul comme demandé par le TODO ("au moins un").
  notification {

    # Condition de déclenchement : "GREATER_THAN" = alerte si on DÉPASSE
    # le seuil défini ci-dessous (autres valeurs : LESS_THAN, EQUAL_TO)
    comparison_operator = "GREATER_THAN"

    # La valeur du seuil de déclenchement. Son unité dépend de
    # threshold_type juste en dessous.
    threshold = 100

    # Précise l'unité du threshold ci-dessus :
    # "PERCENTAGE" = 100 veut dire "100% du limit_amount" (donc 16$ ici)
    # (alternative : "ABSOLUTE_VALUE" → threshold serait directement en $)
    threshold_type = "PERCENTAGE"

    # Sur quelle dépense se base l'alerte :
    # "ACTUAL" = dépense déjà réellement engagée
    # (alternative : "FORECASTED" = dépense prévue/projetée sur la période)
    notification_type = "ACTUAL"

    # Liste des emails qui reçoivent l'alerte par mail.
    # On réutilise la variable définie dans variables.tf (pas de défaut,
    # donc à renseigner obligatoirement dans terraform.tfvars).
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

# ---------------------------------------------------------------------------
# TODO 4 — SNS + CloudWatch : notification de l'alarme
# ---------------------------------------------------------------------------
# - resource "aws_sns_topic" + resource "aws_sns_topic_subscription"
#   (protocol = "email", endpoint = var.budget_alert_email — nécessitera une
#   confirmation par email avant de fonctionner)
# - resource "aws_cloudwatch_metric_alarm" sur une métrique pertinente
#   (ex. AWS/S3 BucketSizeBytes) avec alarm_actions = [le topic SNS ci-dessus]

# 1. Le canal de notification (vide au départ, juste un nom)
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"  # nom du topic dans SNS
}

# 2. L'abonnement email sur ce canal
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn   # sur quel topic s'abonner
  protocol  = "email"                     # moyen de notification
  endpoint  = var.budget_alert_email      # adresse email destinataire
  # ⚠️ nécessitera de cliquer sur le lien de confirmation reçu par email
}

# 3. L'alarme qui surveille la métrique et déclenche l'envoi
resource "aws_cloudwatch_metric_alarm" "s3_bucket_size" {
  alarm_name          = "${var.project_name}-bucket-size-alarm"  # nom de l'alarme
  comparison_operator = "GreaterThanThreshold"  # se déclenche si valeur > threshold
  evaluation_periods  = 1                        # nombre de périodes consécutives à vérifier
  metric_name         = "BucketSizeBytes"        # métrique surveillée
  namespace           = "AWS/S3"                 # service AWS concerné
  period              = 86400                    # fréquence de vérification (1 jour, en secondes)
  statistic           = "Average"                # agrégation utilisée sur la période
  threshold           = 5000000000               # seuil de déclenchement (5 Go, à ajuster)

  dimensions = {
    BucketName  = aws_s3_bucket.datalake.id      # cible précisément CE bucket (nom, pas ARN)
    StorageType = "StandardStorage"               # type de stockage concerné par la métrique
  }

  alarm_actions = [aws_sns_topic.alerts.arn]      # où envoyer l'alerte si seuil dépassé (ARN requis)
}
