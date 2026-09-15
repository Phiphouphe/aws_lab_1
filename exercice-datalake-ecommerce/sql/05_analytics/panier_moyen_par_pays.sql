-- Quel est le panier moyen (montant moyen par commande) par pays ?
-- Résultat exporté dans : exports_result_sql/panier_moyen_par_pays.csv
WITH commandes AS (
    SELECT 
    v.country,
    v.invoiceno,
    SUM(v.line_amount) AS montant_commandes
    FROM fact_ventes v 
    GROUP BY v.country, v.invoiceno
)
SELECT 
country,
AVG(montant_commandes) AS panier_moyen
FROM commandes 
GROUP BY country
ORDER BY panier_moyen DESC;