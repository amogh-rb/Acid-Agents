-- Data dictionary exported from the catalog, so it cannot drift from the schema.
-- Run through .\run.ps1 dict (psql runs from the repo root). Parses the comment contract:
--   column: '[Class] description; null: reason; unbounded: reason; nofk: reason; nolang: reason'
--   table:  '[delete-class] description'

\pset format csv
\pset tuples_only off

\o dictionary/columns.csv
WITH cols AS (
  SELECT n.nspname AS schema_name,
         c.relname AS table_name,
         a.attnum  AS ordinal,
         a.attname AS column_name,
         format_type(CASE WHEN t.typtype = 'd' THEN t.typbasetype ELSE a.atttypid END,
                     CASE WHEN t.typtype = 'd' THEN t.typtypmod  ELSE a.atttypmod END) AS data_type,
         CASE WHEN t.typtype = 'd' THEN t.typname END AS domain_name,
         a.attnotnull,
         pg_get_expr(ad.adbin, ad.adrelid) AS default_value,
         a.attidentity,
         coalesce(col_description(c.oid, a.attnum), '') AS cmt,
         coalesce(obj_description(c.oid, 'pg_class'), '') AS tcmt,
         c.oid AS relid
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    JOIN pg_type t ON t.oid = a.atttypid
    LEFT JOIN pg_attrdef ad ON ad.adrelid = c.oid AND ad.adnum = a.attnum
   WHERE c.relkind IN ('r', 'p')
     AND NOT c.relispartition
     AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'qa')
     AND n.nspname NOT LIKE 'pg\_%'
)
SELECT schema_name,
       table_name,
       ordinal,
       column_name,
       data_type,
       coalesce(domain_name, '') AS domain_name,
       CASE WHEN attnotnull THEN 'NOT NULL' ELSE 'NULL' END AS nullability,
       coalesce(substring(cmt FROM '^\[(\w+)\]'), '') AS sensitive_class,
       coalesce(btrim(substring(cmt FROM '(?i)null:\s*([^;]*)')), '') AS null_reason,
       coalesce(substring(tcmt FROM '^\[([a-z-]+)\]'), '') AS delete_class,
       coalesce((SELECT string_agg(rn.nspname || '.' || rc.relname || '(' || ra.attname || ') ON DELETE ' ||
                                   CASE k.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT' WHEN 'c' THEN 'CASCADE'
                                                      WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END, ', ')
                   FROM pg_constraint k
                   JOIN pg_class rc ON rc.oid = k.confrelid
                   JOIN pg_namespace rn ON rn.oid = rc.relnamespace
                   JOIN pg_attribute ra ON ra.attrelid = k.confrelid
                                       AND ra.attnum = k.confkey[array_position(k.conkey, cols.ordinal)]
                  WHERE k.conrelid = cols.relid AND k.contype = 'f' AND cols.ordinal = ANY (k.conkey)), '') AS references_to,
       CASE WHEN attidentity = 'a' THEN 'GENERATED ALWAYS AS IDENTITY' ELSE coalesce(default_value, '') END AS default_value,
       btrim(regexp_replace(regexp_replace(cmt, '^\[\w+\]\s*', ''), ';?\s*(null|unbounded|nofk|nolang):.*$', '', 'i')) AS description,
       coalesce(btrim(substring(cmt FROM '(?i)unbounded:\s*([^;]*)')), '') AS unbounded_reason,
       coalesce(btrim(substring(cmt FROM '(?i)nofk:\s*([^;]*)')), '') AS nofk_reason
  FROM cols
 ORDER BY schema_name, table_name, ordinal;

\o dictionary/tables.csv
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       CASE c.relkind WHEN 'p' THEN 'partitioned table' ELSE 'table' END AS kind,
       coalesce(substring(obj_description(c.oid, 'pg_class') FROM '^\[([a-z-]+)\]'), '') AS delete_class,
       btrim(regexp_replace(coalesce(obj_description(c.oid, 'pg_class'), ''), '^\[[a-z-]+\]\s*', '')) AS description,
       (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS column_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE c.relkind IN ('r', 'p')
   AND NOT c.relispartition
   AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'qa')
   AND n.nspname NOT LIKE 'pg\_%'
 ORDER BY 1, 2;
\o
