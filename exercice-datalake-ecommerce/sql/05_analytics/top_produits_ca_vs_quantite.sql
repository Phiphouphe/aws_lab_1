-- Quels sont les 10 produits qui génèrent le plus de chiffre d'affaires, et les 10 produits les plus vendus en
-- quantité ? Est-ce les mêmes ?
-- Résultat exporté dans : export_result_sql/10_produits_meilleur_ca_et_qty.csv
WITH top_ca AS (
    SELECT 
    p.product_id, 
    p.title, 
    SUM(v.line_amount) AS chiffre_affaires,
    RANK() OVER (ORDER BY SUM(v.line_amount) DESC) AS rang_ca
    FROM fact_ventes v 
    INNER JOIN dim_produit p 
    ON v.product_id = p.product_id
    WHERE p.product_id != -1
    GROUP BY p.product_id, p.title
    ORDER BY chiffre_affaires DESC
    LIMIT 10
),
top_qty AS (
    SELECT 
    p.product_id, 
    p.title, 
    SUM(v.quantity) AS quantite,
    RANK () OVER (ORDER BY SUM(v.quantity) DESC) AS rang_qty
    FROM fact_ventes v
    INNER JOIN dim_produit p ON v.product_id = p.product_id
    WHERE p.product_id != -1
    GROUP BY p.product_id, p.title
    ORDER BY quantite DESC
    LIMIT 10
)
SELECT 
COALESCE(c.product_id, q.product_id) AS product_id,
COALESCE(c.title, q.title) AS title,
c.rang_ca,
c.chiffre_affaires,
q.rang_qty,
q.quantite 
FROM top_ca c
FULL OUTER JOIN top_qty q 
ON c.product_id = q.product_id
ORDER BY COALESCE(c.rang_ca, 999), COALESCE(q.rang_qty, 999);