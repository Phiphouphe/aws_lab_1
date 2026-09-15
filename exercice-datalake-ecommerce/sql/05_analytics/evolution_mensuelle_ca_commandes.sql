-- Comment le chiffre d'affaires et le nombre de commandes évoluent-ils mois par mois ?
-- Résultat exporté dans : exports_result_sql/evol_ca_et_nb_com_par_mois.csv
WITH mensuel AS (
    SELECT 
    d.year,
    d.month,
    SUM(v.line_amount) AS chiffre_affaires,
    COUNT(DISTINCT(v.invoiceno)) AS nb_commandes
    FROM fact_ventes v
    INNER JOIN dim_date d 
    ON d.date_id = v.date_id
    GROUP BY d.year, d.month 
    ORDER BY d.year, d.month DESC
),
avec_lag AS (
    SELECT 
    *,
    LAG(chiffre_affaires) OVER (ORDER BY year, month) AS ca_mois_precedent
    FROM mensuel
)
SELECT 
year,
month,
chiffre_affaires,
nb_commandes,
chiffre_affaires - ca_mois_precedent AS variation_ca,
ROUND(100.0 * (chiffre_affaires - ca_mois_precedent) / ca_mois_precedent, 1) AS variation_ca_pct
FROM avec_lag
ORDER BY year, month;