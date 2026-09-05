# aws_lab_1
# Projet E-commerce — Architecture Médaillon (Bronze / Silver / Gold) sur AWS Athena

Pipeline data engineering complet : ingestion de données brutes (CSV + JSON) dans
un data lake S3, nettoyage et modélisation dimensionnelle en étoile, interrogeable
via AWS Athena.

> L'infrastructure (bucket S3, base Glue, rôle IAM, Budget/alarme) est provisionnée
> par Terraform dans `demarrage_terraform/` — voir **`demarrage_terraform/README.md`**
> pour le détail de chaque ressource. Ce README-ci couvre le projet dans son
> ensemble : pipeline de données, modèle, qualité, et comment tout exécuter de
> bout en bout.

## 1. Structure du dépôt

```
.
├── README.md                    ce fichier — vue d'ensemble du projet
├── docs/
│   └── data_quality.md          détail des contrôles qualité et preuves
├── source/                      fichiers bruts à ingérer
│   ├── orders_raw/orders.csv
│   ├── products_raw/products.jsonl
│   └── users_raw/users.jsonl
├── sql/
│   ├── 01_bronze/create_tables.sql
│   ├── 02_silver/{orders_clean,products_clean,users_clean}.sql
│   ├── 03_gold/{dim_date,dim_produit,dim_client,fact_ventes}.sql
│   └── 04_checks/data_quality_checks.sql
├── exports_results_sql/         résultats CSV des 6 requêtes analytiques finales
└── demarrage_terraform/         infrastructure AWS (voir son propre README.md)
    ├── README.md                 description du squelette Terraform
    ├── main.tf                   bucket S3, base Glue, AWS Budget, alarme CloudWatch/SNS
    ├── iam.tf                    rôle IAM en moindre privilège (pipeline)
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars          (non commité)
    ├── pipeline.tf               orchestration des scripts sql/ (Bronze -> Silver -> Gold)
    └── scripts/run_athena_query.sh 
```

## 2. Architecture des données

```
S3 (bucket créé par Terraform, nom = ${project_name}-${suffixe aléatoire})
├── bronze/                 données brutes, telles quelles
│   ├── orders_raw/          (CSV)
│   ├── products_raw/        (JSON Lines)
│   └── users_raw/           (JSON Lines)
├── silver/                 données nettoyées, typées, dédupliquées
│   ├── orders_clean/
│   ├── products_clean/
│   └── users_clean/
├── gold/                   modèle en étoile, prêt pour l'analytique
│   ├── dim_date/
│   ├── dim_produit/
│   ├── dim_client/
│   └── fact_ventes/
└── athena-results/         sortie des requêtes Athena
```

Toutes les tables sont déclarées dans la base Glue Data Catalog créée par
Terraform, interrogées via le workgroup Athena **`primary`** (pas de
workgroup dédié : chaque requête précise son propre `OutputLocation`).

### Choix d'architecture

- **Bronze** : copie fidèle des sources, aucune transformation. CSV typé
  entièrement en `STRING` (une valeur invalide ferait échouer la lecture de
  toute la table sinon) ; JSON typé nativement dès la lecture (struct/array
  compris), car le format porte déjà son typage.
- **Silver** : une table nettoyée par source (typage, dates, doublons,
  valeurs aberrantes), indépendamment les unes des autres — aucune jointure
  à ce stade.
- **Gold** : modèle en étoile, construit en croisant les tables Silver.
- **Pas de partitionnement Silver/Gold** : volume du projet trop faible
  (8000 lignes `orders`, 130 `products`/`users`) pour que ça apporte un gain
  réel — décision détaillée dans `docs/data_quality.md`.

## 3. Modèle en étoile (Gold)

**Grain de `fact_ventes`** : une ligne = un produit vendu dans une commande.

```
dim_date                    dim_produit                 dim_client
├── date_id (PK)            ├── product_id (PK)         ├── customer_id (PK)
├── full_date                ├── title                   ├── firstname
├── year                     ├── category                ├── lastname
├── month                    ├── brand                    ├── email
├── month_name               ├── catalog_price             ├── city
├── day                      └── discounted_price          ├── country
└── quarter                                                └── company_name

fact_ventes
├── invoiceno
├── date_id     (FK -> dim_date)
├── product_id  (FK -> dim_produit)
├── customer_id (FK -> dim_client)
├── country      (pays de LIVRAISON de la commande — porté directement,
│                 pas de dim_country séparée : simplification assumée)
├── quantity
├── unit_price
├── line_amount  (= quantity * unit_price)
└── is_return    (quantity < 0 OU invoiceno commence par 'C')
```

Pas de contrainte `PRIMARY KEY`/`FOREIGN KEY` déclarée en base (Athena ne
les supporte pas nativement) : l'unicité de chaque PK est garantie par
construction (`SELECT DISTINCT`) et vérifiée explicitement (voir
`sql/04_checks/data_quality_checks.sql`).

### Gestion des clés orphelines / manquantes (question 6)

Une valeur de `product_id`/`customer_id` référencée dans les commandes mais
absente du catalogue applicatif (produit retiré, compte client supprimé)
n'est **jamais éliminée silencieusement** par une jointure classique.

**Mécanisme retenu** :
1. Chaque dimension (`dim_produit`, `dim_client`) contient une ligne
   sentinelle `-1` ("Produit inconnu" / "Client Inconnu"), ajoutée par
   `UNION ALL` directement dans son CTAS.
2. Dans `fact_ventes`, un `CASE WHEN ... NOT IN (SELECT ... FROM dim_...)
   THEN -1 ELSE ... END` rattache toute clé orpheline ou nulle à cette
   valeur `-1`.

Le chiffre d'affaires total (`SUM(line_amount)`) reste donc exact, et la
part liée à des références manquantes est isolable et quantifiable — détail
chiffré dans `docs/data_quality.md`.

## 4. Qualité des données

Détail complet (règle, volume détecté, traitement, requête de preuve
avant/après) dans **`docs/data_quality.md`**.

## 5. Exécuter le projet de bout en bout

### Prérequis

- Un compte AWS avec les droits suffisants (S3, Glue, Athena, IAM,
  Budgets, CloudWatch, SNS)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [AWS CLI](https://aws.amazon.com/cli/) configuré (`aws configure`)
- Les 3 fichiers sources placés dans `source/`, avec cette arborescence
  exacte (reprise par `aws s3 sync` vers `bronze/`) :
  ```
  source/orders_raw/orders.csv
  source/products_raw/products.jsonl
  source/users_raw/users.jsonl
  ```

### Étapes

```bash
cd demarrage_terraform
cp terraform.tfvars.example terraform.tfvars
# éditer terraform.tfvars : au moins budget_alert_email

terraform init
terraform plan
terraform apply
```

`terraform apply` exécute, dans cet ordre :
1. **Infrastructure** (`main.tf`, `iam.tf`) — voir
   `demarrage_terraform/README.md` pour le détail.
2. **Upload des données sources** (`pipeline.tf`, ressource
   `upload_source`) : synchronise `source/` vers `s3://<bucket>/bronze/`.
3. **Pipeline SQL** (`pipeline.tf`), via `scripts/run_athena_query.sh`, qui
   soumet chaque requête à Athena (workgroup `primary`) et attend sa fin
   avant de passer à la suivante :
   - `sql/01_bronze/create_tables.sql`
   - `sql/02_silver/orders_clean.sql`, `products_clean.sql`, `users_clean.sql`
   - `sql/03_gold/dim_date.sql`, `dim_produit.sql`, `dim_client.sql`,
     `fact_ventes.sql`

Les placeholders `{{BUCKET}}` dans les fichiers `.sql` sont remplacés à la
volée par `run_athena_query.sh` avec le nom réel du bucket généré par
Terraform (aucun nom en dur dans le SQL).

### Relancer proprement (idempotence)

Chaque script Silver/Gold commence par `DROP TABLE IF EXISTS`, qui
supprime la métadonnée Glue mais **pas les fichiers Parquet déjà écrits
sur S3**. Avant de relancer `terraform apply` après une première
exécution réussie, vider les dossiers concernés :

```bash
aws s3 rm s3://<bucket>/silver/ --recursive
aws s3 rm s3://<bucket>/gold/ --recursive
```

sinon Athena renverra `HIVE_PATH_ALREADY_EXISTS`.

## 5. Exécuter le projet de bout en bout

### Prérequis

- Un compte AWS avec les droits suffisants (S3, Glue, Athena, IAM,
  Budgets, CloudWatch, SNS)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [AWS CLI](https://aws.amazon.com/cli/) configuré (`aws configure`)
- Les 3 fichiers sources placés dans `source/`, avec cette arborescence
  exacte (reprise par `aws s3 sync` vers `bronze/`) :
  ```
  source/orders_raw/orders.csv
  source/products_raw/products.jsonl
  source/users_raw/users.jsonl
  ```

### Étapes

```bash
cd demarrage_terraform
cp terraform.tfvars.example terraform.tfvars
# éditer terraform.tfvars : au moins budget_alert_email

terraform init
terraform plan
terraform apply
```

`terraform apply` exécute, dans cet ordre :
1. **Infrastructure** (`main.tf`, `iam.tf`) — voir
   `demarrage_terraform/README.md` pour le détail.
2. **Upload des données sources** (`pipeline.tf`, ressource
   `upload_source`) : synchronise `source/` vers `s3://<bucket>/bronze/`.
3. **Pipeline SQL** (`pipeline.tf`), via `scripts/run_athena_query.sh`, qui
   soumet chaque requête à Athena (workgroup `primary`) et attend sa fin
   avant de passer à la suivante :
   - `sql/01_bronze/create_tables.sql`
   - `sql/02_silver/orders_clean.sql`, `products_clean.sql`, `users_clean.sql`
   - `sql/03_gold/dim_date.sql`, `dim_produit.sql`, `dim_client.sql`,
     `fact_ventes.sql`

Les placeholders `{{BUCKET}}` dans les fichiers `.sql` sont remplacés à la
volée par `run_athena_query.sh` avec le nom réel du bucket généré par
Terraform (aucun nom en dur dans le SQL).

### Relancer proprement (idempotence)

Chaque script Silver/Gold commence par `DROP TABLE IF EXISTS`, qui
supprime la métadonnée Glue mais **pas les fichiers Parquet déjà écrits
sur S3**. Avant de relancer `terraform apply` après une première
exécution réussie, vider les dossiers concernés :

```bash
aws s3 rm s3://<bucket>/silver/ --recursive
aws s3 rm s3://<bucket>/gold/ --recursive
```

sinon Athena renverra `HIVE_PATH_ALREADY_EXISTS`.

### Détruire les ressources

```bash
cd demarrage_terraform
terraform destroy
```

(`force_destroy = true` sur le bucket permet sa suppression même non vide.)

### Test de destruction propre (`terraform destroy`)

Pour valider que l'infrastructure peut être détruite proprement sans
ressource orpheline ni erreur de dépendance, un `terraform plan -destroy`
a été exécuté (simulation, sans suppression réelle) :

```bash
cd demarrage_terraform
terraform plan -destroy
```

**Résultat** : `Plan: 0 to add, 0 to change, 13 to destroy` — aucune erreur,
aucune ressource bloquée par une dépendance non résolue.

Les 13 ressources concernées :
- `aws_s3_bucket.datalake` (+ 4 `aws_s3_object.zones`)
- `aws_glue_catalog_database.datalake`
- `aws_iam_role.pipeline` + `aws_iam_role_policy.pipeline`
- `aws_budgets_budget.notification`
- `aws_cloudwatch_metric_alarm.s3_bucket_size`
- `aws_sns_topic.alerts` + `aws_sns_topic_subscription.alerts_email`
- `random_id.suffix`

**Point d'attention documenté** : les tables Athena (`orders_raw`,
`orders_clean`, `dim_date`, `fact_ventes`...) ne sont pas gérées par l'état
Terraform (créées via SQL/CTAS, pas via des ressources `.tf`). Leur
suppression effective dépend de la suppression en cascade appliquée par
l'API Glue lors de la destruction de `aws_glue_catalog_database.datalake`
— comportement standard, non testé en conditions réelles dans le cadre de
cet exercice (choix : conserver l'infrastructure pour la restitution).

### Détruire les ressources

```bash
cd demarrage_terraform
terraform destroy
```

(`force_destroy = true` sur le bucket permet sa suppression même non vide.)


## 6. Vérifier les résultats

Une fois le pipeline exécuté, lancer `sql/04_checks/data_quality_checks.sql`
dans Athena pour confirmer que chaque contrôle qualité fonctionne
réellement (volumes avant/après, absence d'anomalie résiduelle,
préservation du CA orphelin, unicité des clés primaires).

Les 6 requêtes analytiques finales (CA par pays, top produits, évolution
mensuelle, panier moyen, top clients, clés orphelines) s'exécutent sur
`fact_ventes` jointe aux 3 dimensions ; leurs résultats exportés en CSV
sont dans `exports_results_sql/`.

## 7. Limites connues / pistes d'amélioration

- L'upload des sources suppose la structure exacte `source/<table>_raw/`
  — toute déviation casse la synchronisation vers `bronze/`.
- Le mapping de standardisation des pays (`CASE WHEN`) est codé en dur
  dans le SQL ; une table de référence (pays → ISO alpha-2) serait plus
  maintenable à plus grande échelle.
- `run_athena_query.sh` exécute les requêtes avec les identifiants locaux
  de la machine (`aws cli`), pas en assumant explicitement le rôle
  `aws_iam_role.pipeline` — à faire évoluer si l'on veut valider le
  moindre privilège de bout en bout dès le provisioning.
- Pas de partitionnement Silver/Gold, volontairement, vu le volume actuel
  — à réévaluer si le dataset grossit significativement.
