-- Combien de lignes de commande référencent un produit ou un client absent du catalogue applicatif (clé
-- orpheline), et quel volume/CA cela représente-t-il ?
-- Résultat exporté dans : exports_result_sql/nb_commandes_produit_client_absent.csv
SELECT 
    categorie,
    nb_lignes,
    volume,
    chiffre_affaires,
    ROUND(100.0 * chiffre_affaires / SUM(chiffre_affaires) OVER (), 1) AS pct_ca
FROM (
    SELECT 
        CASE 
            WHEN c.customer_id = -1 AND p.product_id = -1 THEN 'Client et produit absents'
            WHEN c.customer_id = -1 THEN 'Client absent'
            WHEN p.product_id = -1 THEN 'Produit absent'
            ELSE 'Ligne valide'
        END AS categorie,
        COUNT(*) AS nb_lignes,
        SUM(v.quantity) AS volume,
        SUM(v.line_amount) AS chiffre_affaires
    FROM fact_ventes v
    INNER JOIN dim_client c ON c.customer_id = v.customer_id
    INNER JOIN dim_produit p ON p.product_id = v.product_id
    GROUP BY 1
) sub
ORDER BY chiffre_affaires DESC;