-- Runs last on every build. Applies the conventions driven by the comment contract to every table
-- (updated_at triggers, append-only guards, actor FKs, soft-delete views, grants). Idempotent.
-- Module DDL files therefore only declare tables, columns, keys, checks and comments.

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.oid::regclass AS tbl
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind IN ('r', 'p')
       AND NOT c.relispartition
       AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'qa', 'public')
       AND n.nspname NOT LIKE 'pg\_%'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
     ORDER BY n.nspname, c.relname
  LOOP
    PERFORM public.apply_table_standards(r.tbl);
  END LOOP;
END $$;

GRANT USAGE ON SCHEMA ref, admin, org, profile, job, gig, lic, src, billing, notif, dw, audit, app
  TO talentra_app, talentra_readonly, talentra_integration;
GRANT EXECUTE ON FUNCTION public.current_actor_id(), ref.ui_text(text, text) TO talentra_app, talentra_readonly;
-- identity columns draw from sequences: the writing roles need USAGE to insert
GRANT USAGE ON ALL SEQUENCES IN SCHEMA ref, admin, org, profile, job, gig, lic, src, billing, notif, audit TO talentra_app, talentra_integration;
