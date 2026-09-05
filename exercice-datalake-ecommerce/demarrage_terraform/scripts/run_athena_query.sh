#!/usr/bin/env bash
# ==========================================================
# Exécute chaque instruction SQL d'un fichier .sql sur Athena,
# après avoir remplacé le placeholder {{BUCKET}} par le nom réel
# du bucket. Toutes les requêtes sont soumises en assumant le rôle
# IAM en moindre privilège (aws_iam_role.pipeline, défini dans
# iam.tf) plutôt qu'avec les identifiants locaux de l'opérateur.
#
# Usage : ./run_athena_query.sh <fichier.sql> <database> <bucket> <role_arn> [workgroup]
# Workgroup par défaut : "primary" (aucun workgroup dédié dans ce projet)
# ==========================================================
set -euo pipefail

SQL_FILE="$1"
DATABASE="$2"
BUCKET="$3"
ROLE_ARN="$4"
WORKGROUP="${5:-primary}"

if [[ ! -f "$SQL_FILE" ]]; then
  echo "Fichier introuvable : $SQL_FILE" >&2
  exit 1
fi

# ---------------------------------------------------------
# Assume le rôle pipeline : échange les identifiants locaux contre
# des identifiants temporaires, limités aux permissions du rôle
# (accès scopé au bucket/base Glue/workgroup du projet uniquement).
# ---------------------------------------------------------
echo ">> Assume-role : ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name "athena-pipeline-run" \
  --duration-seconds 3600 \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": *"[^"]*"' | cut -d'"' -f4)
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": *"[^"]*"' | cut -d'"' -f4)
export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": *"[^"]*"' | cut -d'"' -f4)

if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
  echo "Échec de l'assume-role sur $ROLE_ARN" >&2
  exit 1
fi

# À partir d'ici, tous les appels `aws` utilisent les identifiants
# temporaires du rôle pipeline (variables d'environnement ci-dessus),
# pas les identifiants locaux de l'opérateur.

# Remplace {{BUCKET}} par le vrai nom de bucket, puis découpe en
# instructions séparées par ';' (ignore les lignes de commentaire)
RENDERED=$(sed "s/{{BUCKET}}/${BUCKET}/g" "$SQL_FILE" | grep -v '^\s*--')
STATEMENTS=$(echo "$RENDERED" | sed ':a;N;$!ba;s/\n/ /g')
IFS=';' read -ra QUERIES <<< "$STATEMENTS"

for QUERY in "${QUERIES[@]}"; do
  TRIMMED=$(echo "$QUERY" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -z "$TRIMMED" ]]; then
    continue
  fi

  echo ">> Exécution : ${TRIMMED:0:80}..."

  QUERY_ID=$(aws athena start-query-execution \
    --query-string "$TRIMMED" \
    --query-execution-context Database="$DATABASE" \
    --work-group "$WORKGROUP" \
    --result-configuration "OutputLocation=s3://${BUCKET}/athena-results/" \
    --query 'QueryExecutionId' \
    --output text)

  STATUS="RUNNING"
  while [[ "$STATUS" == "RUNNING" || "$STATUS" == "QUEUED" ]]; do
    sleep 2
    STATUS=$(aws athena get-query-execution \
      --query-execution-id "$QUERY_ID" \
      --query 'QueryExecution.Status.State' \
      --output text)
  done

  if [[ "$STATUS" != "SUCCEEDED" ]]; then
    REASON=$(aws athena get-query-execution \
      --query-execution-id "$QUERY_ID" \
      --query 'QueryExecution.Status.StateChangeReason' \
      --output text)
    echo "Échec de la requête ($STATUS) : $REASON" >&2
    exit 1
  fi

  echo "   -> OK"
done

echo "Toutes les instructions de $SQL_FILE ont été exécutées avec succès."