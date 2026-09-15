# Résultats des analyses

Ce dossier contient les exports CSV des requêtes analytiques du datalake.
Chaque export correspond à une requête SQL du dossier `sql/05_analytics/`, avec le même nom de fichier (seule l'extension change).

| Export | Requête source | Description |
|---|---|---|
| ca_par_pays_3_derniers_mois.csv | [sql/05_analytics/ca_par_pays_3_derniers_mois.sql](../sql/05_analytics/ca_par_pays_3_derniers_mois.sql) | Chiffre d'affaires par pays sur les 3 derniers mois glissants (fenêtre recalculée à chaque exécution) |
| top_produits_ca_vs_quantite.csv | [sql/05_analytics/top_produits_ca_vs_quantite.sql](../sql/05_analytics/top_produits_ca_vs_quantite.sql) | Top 10 produits par chiffre d'affaires et top 10 par quantité vendue, comparés côte à côte |
| evolution_mensuelle_ca_commandes.csv | [sql/05_analytics/evolution_mensuelle_ca_commandes.sql](../sql/05_analytics/evolution_mensuelle_ca_commandes.sql) | Chiffre d'affaires et nombre de commandes par mois, avec variation en valeur et en % vs mois précédent |
| panier_moyen_par_pays.csv | [sql/05_analytics/panier_moyen_par_pays.sql](../sql/05_analytics/panier_moyen_par_pays.sql) | Montant moyen par commande, par pays |
| top_5_clients_ca.csv | [sql/05_analytics/top_5_clients_ca.sql](../sql/05_analytics/top_5_clients_ca.sql) | Top 5 clients par chiffre d'affaires cumulé |
| nb_commandes_produit_client_absent.csv | [sql/05_analytics/nb_commandes_produit_client_absent.sql](../sql/05_analytics/nb_commandes_produit_client_absent.sql) | Nombre de lignes, volume et CA associés à des clés orphelines (client ou produit absent du catalogue applicatif) |

## Comment ajouter une nouvelle analyse

1. Créer la requête dans `sql/05_analytics/nom_analyse.sql`, avec un commentaire en en-tête décrivant l'objectif et les particularités de la requête.
2. Exécuter la requête et exporter le résultat dans `exports_result_sql/nom_analyse.csv` (même radical de nom que le fichier `.sql`).
3. Ajouter une ligne dans le tableau ci-dessus.