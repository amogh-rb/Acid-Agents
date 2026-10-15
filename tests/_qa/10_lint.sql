-- Catalog lint: checks docket rule groups 1-8 against pg_catalog, so the rules are re-proved on every gate.
-- Scope: every non-system schema except qa; extension-owned objects are skipped.
-- Comment contract (see CLAUDE.md):
--   table:  '[soft-delete] ...' | '[hard-delete] ...' | '[append-only] ...' | '[derived] ...' (dw only)
--   column: '[Public|Internal|Personal|Sensitive] description; null: reason; unbounded: reason; nofk: reason; nolang: reason'
--           (only the markers that apply; "null:" is required on every nullable column)

CREATE FUNCTION qa.lint_violations()
RETURNS TABLE (rule text, object_name text, detail text)
LANGUAGE sql STABLE AS
$lint$
WITH
sch AS (
  SELECT n.oid, n.nspname
    FROM pg_namespace n
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'qa', 'pg_toast')
     AND n.nspname NOT LIKE 'pg\_%'
),
rel AS (
  SELECT c.oid, s.nspname, c.relname, c.relkind, c.relispartition,
         coalesce(obj_description(c.oid, 'pg_class'), '') AS tcmt
    FROM pg_class c
    JOIN sch s ON s.oid = c.relnamespace
   WHERE c.relkind IN ('r', 'p', 'v', 'm')
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
),
tbl AS (
  SELECT * FROM rel WHERE relkind IN ('r', 'p') AND NOT relispartition
),
col AS (
  SELECT r.oid AS relid, r.nspname, r.relname, r.tcmt, a.attnum, a.attname::text AS attname,
         a.attnotnull, a.atthasdef, a.attidentity,
         CASE WHEN t.typtype = 'd' THEN bt.typname ELSE t.typname END::text AS basetype,
         CASE WHEN t.typtype = 'd' THEN t.typname END::text                  AS domname,
         CASE WHEN t.typtype = 'd' THEN t.typtypmod ELSE a.atttypmod END     AS typmod,
         coalesce(col_description(r.oid, a.attnum), '')                      AS cmt,
         r.nspname || '.' || r.relname || '.' || a.attname                  AS fq
    FROM tbl r
    JOIN pg_attribute a ON a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped
    JOIN pg_type t ON t.oid = a.atttypid
    LEFT JOIN pg_type bt ON bt.oid = t.typbasetype
),
kw AS (
  SELECT word::text FROM pg_get_keywords() WHERE catcode IN ('R', 'T', 'C')
  UNION
  SELECT word FROM qa.mysql_reserved_word
),
fkcol AS (
  SELECT k.conrelid AS relid, u.attnum
    FROM pg_constraint k, unnest(k.conkey) AS u(attnum)
   WHERE k.contype = 'f'
),
has_app_user AS (
  SELECT to_regclass('admin.app_user') IS NOT NULL AS ok
)

-- ===== RG1 naming =====
SELECT 'RG1 snake_case', nspname, 'schema name is not snake_case'
  FROM sch WHERE nspname !~ '^[a-z][a-z0-9_]*$'
UNION ALL
SELECT 'RG1 snake_case', nspname || '.' || relname, 'relation name is not snake_case'
  FROM rel WHERE relname !~ '^[a-z][a-z0-9_]*$'
UNION ALL
SELECT 'RG1 snake_case', fq, 'column name is not snake_case'
  FROM col WHERE attname !~ '^[a-z][a-z0-9_]*$'
UNION ALL
SELECT 'RG1 singular', nspname || '.' || relname, 'table name looks plural; use a singular noun'
  FROM tbl WHERE relname ~ 's$' AND relname !~ '(ss|us|is)$'
UNION ALL
SELECT 'RG1 reserved word', nspname, 'schema name is reserved in PostgreSQL or MySQL'
  FROM sch WHERE nspname IN (SELECT word FROM kw)
UNION ALL
SELECT 'RG1 reserved word', nspname || '.' || relname, 'relation name is reserved in PostgreSQL or MySQL'
  FROM rel WHERE relname IN (SELECT word FROM kw)
UNION ALL
SELECT 'RG1 reserved word', fq, 'column name is reserved in PostgreSQL or MySQL'
  FROM col WHERE attname IN (SELECT word FROM kw)

-- constraint names: pk_<table>, fk_/uq_/ck_/ex_<table>_<...>
UNION ALL
SELECT 'RG1 constraint name', t.nspname || '.' || t.relname || ' ' || k.conname,
       'expected prefix ' || p.prefix
  FROM pg_constraint k
  JOIN tbl t ON t.oid = k.conrelid
  CROSS JOIN LATERAL (
    SELECT CASE k.contype WHEN 'p' THEN 'pk_' WHEN 'f' THEN 'fk_' WHEN 'u' THEN 'uq_'
                          WHEN 'c' THEN 'ck_' WHEN 'x' THEN 'ex_' END || t.relname AS prefix
  ) p
 WHERE k.contype IN ('p', 'f', 'u', 'c', 'x')
   AND NOT (k.conname = p.prefix AND k.contype = 'p')
   AND NOT (k.contype <> 'p' AND left(k.conname, length(p.prefix) + 1) = p.prefix || '_')
   AND length(p.prefix) < 62

-- index names not backing a constraint: idx_<table>_..., or uq_<table>_... for unique indexes
UNION ALL
SELECT 'RG1 index name', t.nspname || '.' || ic.relname, 'expected prefix idx_' || t.relname || '_'
  FROM pg_index i
  JOIN pg_class ic ON ic.oid = i.indexrelid
  JOIN tbl t ON t.oid = i.indrelid
 WHERE NOT EXISTS (SELECT 1 FROM pg_constraint k
                    WHERE k.conindid = i.indexrelid AND k.conrelid = t.oid AND k.contype IN ('p', 'u', 'x'))
   AND left(ic.relname, length(t.relname) + 5) <> 'idx_' || t.relname || '_'
   AND NOT (i.indisunique AND left(ic.relname, length(t.relname) + 4) = 'uq_' || t.relname || '_')

-- trigger names: trg_<table>_...
UNION ALL
SELECT 'RG1 trigger name', t.nspname || '.' || t.relname || ' ' || tg.tgname, 'expected prefix trg_' || t.relname || '_'
  FROM pg_trigger tg
  JOIN tbl t ON t.oid = tg.tgrelid
 WHERE NOT tg.tgisinternal AND tg.tgparentid = 0
   AND left(tg.tgname, length(t.relname) + 5) <> 'trg_' || t.relname || '_'

-- ===== RG2 keys =====
UNION ALL
SELECT 'RG2 primary key', nspname || '.' || relname, 'table has no primary key'
  FROM tbl t WHERE NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = t.oid AND k.contype = 'p')
UNION ALL
SELECT 'RG2 primary key', t.nspname || '.' || t.relname, 'primary key does not include the surrogate column id'
  FROM tbl t
  JOIN pg_constraint k ON k.conrelid = t.oid AND k.contype = 'p'
 WHERE NOT EXISTS (SELECT 1 FROM pg_attribute a
                    WHERE a.attrelid = t.oid AND a.attnum = ANY (k.conkey) AND a.attname = 'id')
UNION ALL
SELECT 'RG2 surrogate key', fq, 'id must be bigint GENERATED ALWAYS AS IDENTITY'
  FROM col WHERE attname = 'id' AND (basetype <> 'int8' OR attidentity <> 'a')
UNION ALL
SELECT 'RG2 foreign key', fq, 'reference column has no FK constraint (add one, or justify with "nofk:")'
  FROM col c, has_app_user h
 WHERE (c.attname ~ '_(id|code)$' OR (h.ok AND c.attname IN ('created_by', 'updated_by')))
   AND c.attname <> 'id'
   AND NOT EXISTS (SELECT 1 FROM fkcol f WHERE f.relid = c.relid AND f.attnum = c.attnum)
   AND c.cmt !~* 'nofk:\s*\S'

-- ===== RG3 standard domains =====
UNION ALL
SELECT 'RG3 float', fq, 'floating point is banned; use numeric, d_money or d_pct'
  FROM col WHERE basetype IN ('float4', 'float8')
UNION ALL
SELECT 'RG3 timestamp', fq, 'use timestamptz (UTC); timestamp without time zone and timetz are banned'
  FROM col WHERE basetype IN ('timestamp', 'timetz')
UNION ALL
SELECT 'RG3 money domain', fq, 'money column must use d_money'
  FROM col
 WHERE basetype = 'numeric' AND coalesce(domname, '') <> 'd_money'
   AND attname ~ '(^|_)(amount|price|salary|balance|fee|cost|ctc|earning|earnings)(_|$)'
   AND attname !~ '_(pct|percent|percentage)$'
UNION ALL
SELECT 'RG3 money currency', fq, 'd_money column needs ' || attname || '_currency_code, <prefix>_currency_code or currency_code in the same table'
  FROM col c
 WHERE c.domname = 'd_money'
   AND NOT EXISTS (SELECT 1 FROM col c2 WHERE c2.relid = c.relid
                      AND (c2.attname IN (c.attname || '_currency_code', 'currency_code')
                           OR (c2.attname ~ '_currency_code$'
                               AND left(c.attname, length(c2.attname) - 13) = left(c2.attname, length(c2.attname) - 13))))
UNION ALL
SELECT 'RG3 unbounded text', fq, 'unbounded text needs a stated reason ("unbounded:") or a max length'
  FROM col
 WHERE (basetype = 'text' OR (basetype IN ('varchar', 'bpchar') AND typmod = -1))
   AND cmt !~* 'unbounded:\s*\S'
UNION ALL
SELECT 'RG3 email', fq, 'email column must use d_email'
  FROM col WHERE attname ~ '(^|_)email$' AND coalesce(domname, '') <> 'd_email'
UNION ALL
SELECT 'RG3 phone', fq, 'phone column must use d_phone_e164'
  FROM col WHERE attname ~ '(^|_)phone(_number)?$' AND coalesce(domname, '') <> 'd_phone_e164'
UNION ALL
SELECT 'RG3 phone', fq, 'phone column needs a separate ' || attname || '_country_id column'
  FROM col c
 WHERE c.attname ~ '(^|_)phone(_number)?$'
   AND NOT EXISTS (SELECT 1 FROM col c2 WHERE c2.relid = c.relid AND c2.attname = c.attname || '_country_id')
UNION ALL
SELECT 'RG3 person name', fq, 'person name column must use d_person_name'
  FROM col
 WHERE attname ~ '(^|_)(full|given|family|middle|first|last|display|person)_name$'
   AND coalesce(domname, '') <> 'd_person_name'
UNION ALL
SELECT 'RG3 coordinates', fq, 'latitude/longitude must use d_lat/d_lng'
  FROM col
 WHERE (attname ~ '(^|_)latitude$'  AND coalesce(domname, '') <> 'd_lat')
    OR (attname ~ '(^|_)longitude$' AND coalesce(domname, '') <> 'd_lng')
UNION ALL
SELECT 'RG3 percentage', fq, 'percentage column must use d_pct'
  FROM col WHERE attname ~ '_(pct|percent|percentage)$' AND coalesce(domname, '') <> 'd_pct'
UNION ALL
SELECT 'RG3 boolean', fq, 'boolean must be NOT NULL with a DEFAULT'
  FROM col WHERE basetype = 'bool' AND NOT (attnotnull AND atthasdef)

-- ===== RG4 audit and lifecycle =====
UNION ALL
SELECT 'RG4 delete class', nspname || '.' || relname,
       'table comment must start with [soft-delete], [hard-delete], [append-only] or [derived]'
  FROM tbl WHERE tcmt !~ '^\[(soft-delete|hard-delete|append-only|derived)\]'
UNION ALL
SELECT 'RG4 delete class', nspname || '.' || relname, '[derived] is reserved for the dw schema'
  FROM tbl WHERE tcmt ~ '^\[derived\]' AND nspname <> 'dw'
UNION ALL
SELECT 'RG4 audit columns', t.nspname || '.' || t.relname || '.' || req.c, 'missing or wrong type/nullability'
  FROM tbl t
  CROSS JOIN LATERAL (
    SELECT * FROM (VALUES ('created_at', 'timestamptz'), ('created_by', 'int8'),
                          ('updated_at', 'timestamptz'), ('updated_by', 'int8')) v(c, typ)
     WHERE NOT (t.tcmt ~ '^\[append-only\]' AND v.c IN ('updated_at', 'updated_by'))
  ) req
 WHERE t.nspname <> 'dw'
   AND NOT EXISTS (SELECT 1 FROM col c WHERE c.relid = t.oid AND c.attname = req.c
                      AND c.basetype = req.typ AND c.attnotnull)
UNION ALL
SELECT 'RG4 soft delete', nspname || '.' || relname, '[soft-delete] table needs a nullable deleted_at timestamptz'
  FROM tbl t
 WHERE t.tcmt ~ '^\[soft-delete\]'
   AND NOT EXISTS (SELECT 1 FROM col c WHERE c.relid = t.oid AND c.attname = 'deleted_at'
                      AND c.basetype = 'timestamptz' AND NOT c.attnotnull)
UNION ALL
SELECT 'RG4 soft delete', nspname || '.' || relname, 'deleted_at present but table is not tagged [soft-delete]'
  FROM tbl t
 WHERE t.tcmt !~ '^\[soft-delete\]'
   AND EXISTS (SELECT 1 FROM col c WHERE c.relid = t.oid AND c.attname = 'deleted_at')
UNION ALL
SELECT 'RG4 soft delete', nspname || '.' || relname, 'missing default view v_' || relname
  FROM tbl t
 WHERE t.tcmt ~ '^\[soft-delete\]'
   AND NOT EXISTS (SELECT 1 FROM rel v WHERE v.nspname = t.nspname AND v.relname = 'v_' || t.relname AND v.relkind = 'v')
UNION ALL
SELECT 'RG4 append-only', nspname || '.' || relname, 'missing trg_' || relname || '_forbid_update_delete'
  FROM tbl t
 WHERE t.tcmt ~ '^\[append-only\]'
   AND NOT EXISTS (SELECT 1 FROM pg_trigger tg WHERE tg.tgrelid = t.oid AND tg.tgname = 'trg_' || t.relname || '_forbid_update_delete')
UNION ALL
SELECT 'RG4 updated_at trigger', nspname || '.' || relname, 'missing trg_' || relname || '_set_updated_at'
  FROM tbl t
 WHERE EXISTS (SELECT 1 FROM col c WHERE c.relid = t.oid AND c.attname = 'updated_at')
   AND NOT EXISTS (SELECT 1 FROM pg_trigger tg WHERE tg.tgrelid = t.oid AND tg.tgname = 'trg_' || t.relname || '_set_updated_at')

-- ===== RG5 nullability, RG6 classification =====
UNION ALL
SELECT 'RG6 class tag', fq, 'column comment must start with [Public], [Internal], [Personal] or [Sensitive]'
  FROM col WHERE cmt !~ '^\[(Public|Internal|Personal|Sensitive)\]'
UNION ALL
SELECT 'RG5 null reason', fq, 'nullable column needs "null: <reason>" in its comment'
  FROM col WHERE NOT attnotnull AND cmt !~* 'null:\s*\S'
UNION ALL
SELECT 'RG6 sensitive form', fq, 'Sensitive column must be encrypted (bytea) or a hash/token/masked value'
  FROM col
 WHERE cmt ~ '^\[Sensitive\]' AND basetype <> 'bytea' AND attname !~ '_(hash|token|masked|last4)$'

-- ===== RG7 multilingual =====
UNION ALL
SELECT 'RG7 encoding', current_database(), 'database encoding is not UTF8'
 WHERE (SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = current_database()) <> 'UTF8'
UNION ALL
SELECT 'RG7 language', fq, 'user-entered text needs ' || attname || '_language_id (or "nolang:")'
  FROM col c
 WHERE c.basetype = 'text'
   AND c.cmt !~* 'nolang:\s*\S'
   AND NOT EXISTS (SELECT 1 FROM col c2 WHERE c2.relid = c.relid AND c2.attname = c.attname || '_language_id')

-- ===== RG8 physical objects =====
UNION ALL
SELECT 'RG8 physical name', nspname || '.' || relname, 'views must start with v_'
  FROM rel WHERE relkind = 'v' AND relname !~ '^v_'
UNION ALL
SELECT 'RG8 physical name', nspname || '.' || relname, 'materialized views must start with mv_'
  FROM rel WHERE relkind = 'm' AND relname !~ '^mv_'
UNION ALL
SELECT 'RG8 physical name', nspname || '.' || relname, 'dw tables must start with dim_, fact_, agg_ or etl_'
  FROM tbl WHERE nspname = 'dw' AND relname !~ '^(dim|fact|agg|etl)_'
UNION ALL
SELECT 'RG8 physical name', nspname || '.' || relname, 'dim_/fact_/agg_ prefixes are reserved for the dw schema'
  FROM tbl WHERE nspname <> 'dw' AND relname ~ '^(dim|fact|agg)_'
UNION ALL
SELECT 'RG8 physical name', r.nspname || '.' || r.relname, 'partition must be named <parent>_pYYYY, <parent>_pYYYYMM or <parent>_default'
  FROM rel r
  JOIN pg_inherits i ON i.inhrelid = r.oid
  JOIN pg_class p ON p.oid = i.inhparent
 WHERE r.relispartition
   AND r.relname !~ ('^' || p.relname || '_(p[0-9]{4}([0-9]{2})?|default)$')

ORDER BY 1, 2
$lint$;
