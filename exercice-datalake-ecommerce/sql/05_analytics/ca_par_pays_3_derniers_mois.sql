-- Quel est le chiffre d'affaires total, et par pays, sur les 3 derniers mois ?
-- Résultat exporté dans : export_result_sql/ca_par_pays_3_derniers_mois.csv
SELECT 
    v.country, 
    SUM(v.line_amount) AS chiffre_affaires
FROM fact_ventes v
INNER JOIN dim_date d ON v.date_id = d.date_id
WHERE d.full_date >= date_add('month', -3, current_date)
GROUP BY GROUPING SETS ((v.country), ())
ORDER BY chiffre_affaires DESC;