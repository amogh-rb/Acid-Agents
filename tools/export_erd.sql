-- Mermaid erDiagram generated from the catalog. Usage (from the repo root):
--   .\run.ps1 erd -Schemas ref,profile,job -Out docs/erd/phase1_generated.mmd
-- psql variable :schemas is a comma list; empty means every schema.
-- Entity names are <schema>__<table>. Audit columns and actor FKs (created_by/updated_by -> app_user) are omitted
-- because every table has them. Cardinality: ||--o{ mandatory parent, |o--o{ optional parent, --o| when the FK is unique.

\pset format unaligned
\pset tuples_only on
\if :{?schemas}
\else
  \set schemas ''
\endif

WITH scope AS (
  SELECT c.oid, n.nspname, c.relname, n.nspname || '__' || c.relname AS ent
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.relkind IN ('r', 'p')
     AND NOT c.relispartition
     AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'qa')
     AND n.nspname NOT LIKE 'pg\_%'
     AND (:'schemas' = '' OR n.nspname = ANY (string_to_array(:'schemas', ',')))
),
attrs AS (
  SELECT s.ent, a.attnum,
         '    ' || CASE WHEN t.typtype = 'd' THEN t.typname ELSE t.typname END || ' ' || a.attname ||
         CASE WHEN EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = s.oid AND k.contype = 'p' AND a.attnum = ANY (k.conkey)) THEN ' PK'
              WHEN EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = s.oid AND k.contype = 'f' AND a.attnum = ANY (k.conkey)) THEN ' FK'
              WHEN EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = s.oid AND k.contype = 'u' AND a.attnum = ANY (k.conkey)) THEN ' UK'
              ELSE '' END AS line
    FROM scope s
    JOIN pg_attribute a ON a.attrelid = s.oid AND a.attnum > 0 AND NOT a.attisdropped
    JOIN pg_type t ON t.oid = a.atttypid
   WHERE a.attname NOT IN ('created_at', 'created_by', 'updated_at', 'updated_by')
),
ents AS (
  SELECT s.ent, '  ' || s.ent || ' {' || E'\n' || string_agg(at.line, E'\n' ORDER BY at.attnum) || E'\n  }' AS block
    FROM scope s JOIN attrs at ON at.ent = s.ent
   GROUP BY s.ent
),
rels AS (
  SELECT '  ' || pn.nspname || '__' || pc.relname || ' ' ||
         CASE WHEN bool_and(a.attnotnull) THEN '||' ELSE '|o' END || '--' ||
         CASE WHEN EXISTS (SELECT 1 FROM pg_constraint u
                            WHERE u.conrelid = k.conrelid AND u.contype IN ('u', 'p')
                              AND u.conkey::int2[] @> k.conkey AND u.conkey::int2[] <@ k.conkey) THEN 'o|' ELSE 'o{' END ||
         ' ' || s.ent || ' : "' || k.conname || '"' AS line
    FROM scope s
    JOIN pg_constraint k ON k.conrelid = s.oid AND k.contype = 'f'
    JOIN pg_class pc ON pc.oid = k.confrelid
    JOIN pg_namespace pn ON pn.oid = pc.relnamespace
    JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey)
   WHERE NOT (k.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = s.oid AND attname = 'created_by')]
           OR k.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = s.oid AND attname = 'updated_by')])
   GROUP BY pn.nspname, pc.relname, k.conrelid, k.conkey, s.ent, k.conname
)
SELECT 'erDiagram'
UNION ALL
SELECT * FROM (SELECT block FROM ents ORDER BY ent) e
UNION ALL
SELECT * FROM (SELECT line FROM rels ORDER BY line) r;
