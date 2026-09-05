# Qualité des données — profiling, règles et preuves

Ce document détaille, pour chaque anomalie identifiée lors du profiling des
tables Bronze, la règle de détection appliquée, le volume concerné, le
traitement retenu et la requête permettant de prouver que le contrôle
fonctionne réellement (résultat attendu après nettoyage).

## Méthodologie

1. Exploration systématique de chaque table Bronze (nulls, valeurs
   aberrantes, doublons, cardinalité/graphies) avant toute décision de
   nettoyage.
2. Utilisation de `TRY_CAST` / `TRY(...)` pour ne jamais faire échouer une
   requête sur une valeur invalide isolée.
3. Chaque règle d'exclusion est vérifiée après coup (section "Preuve") pour
   confirmer qu'elle a bien produit l'effet attendu.

## orders_raw → orders_clean (8000 lignes en entrée)

### unit_price = 0
- **Détection** : `TRY_CAST(unitprice AS DOUBLE) = 0`
- **Volume** : 45 lignes / 44 invoiceno distincts (dispersé, pas de
  concentration)
- **Analyse** : quantités associées variées et réalistes (-14 à 20) — ce
  sont probablement de vraies transactions avec un prix mal renseigné, pas
  des lignes fantômes.
- **Traitement** : exclues (impact CA nul de toute façon, `line_amount = 0`,
  mais fausserait les comptages de quantités vendues si conservées).
- **Preuve** : `SELECT COUNT(*) FROM orders_clean WHERE unit_price = 0;` → 0

### unit_price < 0 ET quantity > 0 (incohérence)
- **Détection** : combinaison des deux conditions
- **Volume** : 29 lignes / 29 invoiceno distincts (dispersé)
- **Analyse** : incohérence métier — un prix négatif avec une quantité
  positive ne correspond ni à une vente, ni à un retour standard (qui aurait
  une quantité négative).
- **Traitement** : exclues.
- **Preuve** : `SELECT COUNT(*) FROM orders_clean WHERE unit_price < 0 AND quantity > 0;` → 0

### quantity NULL
- **Détection** : `TRY_CAST(quantity AS INTEGER) IS NULL`
- **Volume** : 116 lignes
- **Traitement** : exclues (non exploitable pour `line_amount` ni pour les
  comptages de quantité).
- **Preuve** : `SELECT COUNT(*) FROM orders_clean WHERE quantity IS NULL;` → 0
- *(Note : `quantity = 0` a également été vérifié séparément → 0 ligne,
  cas non applicable dans ce dataset.)*

### invoice_date manquante ou illisible
- **Détection** : `COALESCE(TRY_CAST(invoice_date AS DATE), TRY(date_parse(...)))
  IS NULL`
- **Volume observé** :
  - 36 lignes avec date vide
  - 29 lignes au format `dd/mm/yyyy` (reformatées, pas exclues)
  - le reste au format ISO (`yyyy-mm-dd HH:MM:SS`), lu nativement
- **Traitement** : les 29 lignes `dd/mm/yyyy` sont reformatées et
  conservées (donnée valide, juste un format différent — perdre ces lignes
  aurait supprimé du CA réel sans raison). Les 36 lignes vides sont
  exclues (aucune donnée à récupérer).
- **Preuve** : `SELECT COUNT(*) FROM orders_clean WHERE invoice_date IS NULL;` → 0

### Doublons
- **Détection** : lignes strictement identiques sur toutes les colonnes vs.
  lignes partageant seulement `invoiceno` + `product_id` mais différant sur
  `quantity`/`unit_price` (ex. vente + retour partiel sur la même facture).
- **Traitement** : `SELECT DISTINCT` sur l'ensemble des colonnes du
  `SELECT` — élimine uniquement les doublons stricts, préserve les lignes
  représentant des événements réels distincts (même clé métier, valeurs
  différentes).

### Graphies multiples de country
- **Détection** : `SELECT DISTINCT country` sur `orders_raw` — casse
  variable, fautes d'orthographe, mélange anglais/français.
- **Traitement** : `UPPER(TRIM(country))` puis `CASE WHEN ... IN (...)`
  vers les codes ISO 3166-1 alpha-2 (`FR`, `GB`, `US`, `NL`, `BE`, `IT`,
  `PT`, `DE`, `ES`, `CH`). Toute valeur non couverte → `'UNKNOWN'`.
- **Preuve** : `SELECT DISTINCT country FROM orders_clean;` doit ne
  renvoyer que des codes ISO valides + éventuellement `UNKNOWN`.

### customer_id manquant
- **Détection** : `TRY_CAST(customerid AS INTEGER) IS NULL`
- **Volume** : 157 lignes
- **Traitement** : **conservées** — un client anonyme/invité est une
  situation métier normale, pas une anomalie de qualité. Rattachées à la
  clé sentinelle `-1` au niveau Gold (`fact_ventes`), pas exclues en
  Silver.

## products_raw → products_clean (130 lignes en entrée)

### brand manquante
- **Volume** : 62 lignes / 130 (~48 %)
- **Analyse de dispersion** : concentrée sur `kitchen_accessories` (30),
  `groceries` (27), `home_decoration` (5) — cohérent avec des catégories de
  produits génériques/non brandés, pas une anomalie de saisie.
- **Traitement** : conservée, `COALESCE(brand, 'UNKNOWN')`.

### Cohérence price / discountPercentage, doublons sur id
- Vérifiés (`price > 0`, unicité de `id`) — aucune anomalie bloquante
  détectée sur ce dataset.

## users_raw → users_clean (130 lignes en entrée)

### address.country
- Une seule valeur distincte (`United States`) sur l'ensemble du fichier →
  aucune standardisation multi-graphies nécessaire. Rattaché au code `US`
  pour cohérence de format avec `orders_clean.country`.
- **Important** : `users.address.country` (pays du référentiel client) et
  `orders.country` (pays de livraison de la commande) sont deux notions
  différentes, non censées être croisées directement.

## Clés orphelines (question 6)

### Détection initiale, sur les données Bronze brutes (avant tout nettoyage)

```sql
SELECT COUNT(*), SUM(quantity * unitprice)
FROM orders_raw o LEFT JOIN products_raw p ON CAST(o.productid AS INT) = p.id
WHERE p.id IS NULL;
-- 146 lignes, 192 780,69 €

SELECT COUNT(*), SUM(quantity * unitprice)
FROM orders_raw o LEFT JOIN users_raw u ON CAST(o.customerid AS INT) = u.id
WHERE u.id IS NULL;
-- 241 lignes, 286 372,33 €
```

Chevauchement vérifié avec les lignes exclues pour `unit_price = 0` /
`unit_price < 0` : **0 ligne** — ces deux traitements sont indépendants,
aucune perte d'information croisée à ce niveau.

### Volumes finaux observés dans fact_ventes (après nettoyage Silver complet)

- `product_id = -1` : 139 lignes
- `customer_id = -1` : 237 lignes
- Total combiné : 376 lignes, ~464 548 € (~5 % du CA total), 3616 unités

### Explication de l'écart entre Bronze (146/241) et Gold (139/237)

L'écart s'explique par le fait qu'une partie des lignes orphelines
détectées sur `orders_raw` étaient également concernées par d'autres règles
de qualité appliquées en Silver (`quantity` NULL, `invoice_date` vide), et
ont donc été exclues **avant** d'atteindre `fact_ventes` — indépendamment de
leur statut d'orpheline. La comparaison rigoureuse à faire n'est donc pas
Bronze vs Gold, mais **Silver (`orders_clean`) vs Gold**, qui, elle, doit
correspondre exactement (le mécanisme `-1` ne fait que rattacher, il ne
retire ni n'ajoute de lignes par rapport à `orders_clean`) :

```sql
SELECT COUNT(*)
FROM orders_clean o
LEFT JOIN products_clean p ON o.product_id = p.product_id
WHERE p.product_id IS NULL;
-- attendu : 139, identique au COUNT(*) WHERE product_id = -1 dans fact_ventes
```

### Traitement retenu

Rattachement à une clé sentinelle `-1` ("Produit inconnu" / "Client
Inconnu") dans `dim_produit`/`dim_client`, plutôt qu'exclusion ou
quarantaine séparée — choix documenté dans le README, section 2.
