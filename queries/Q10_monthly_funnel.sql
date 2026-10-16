-- name: Monthly hiring funnel by category (warehouse view)
-- kind: analytics
-- mode: select
SELECT year_number, month_number, job_category, applied, shortlisted, interviewed, offered, joined, join_rate_pct
  FROM dw.v_funnel_by_category WHERE year_number >= 2025 ORDER BY year_number, month_number, job_category;
