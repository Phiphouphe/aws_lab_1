-- Quels sont les 5 clients qui ont généré le plus de chiffre d'affaires cumulé
-- Résultat exporté dans : exports_result_sql/top_5_clients_ca.csv
SELECT 
v.customer_id,
c.firstname,
c.lastname,
SUM(v.line_amount) AS chiffre_affaires
FROM fact_ventes v
INNER JOIN dim_client c
ON c.customer_id = v.customer_id
WHERE v.customer_id != -1
GROUP BY v.customer_id, c.firstname, c.lastname
ORDER BY chiffre_affaires DESC 
LIMIT 5;