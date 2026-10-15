-- M1: base functions every module builds on.
--   public.current_actor_id()          actor for audit columns, from SET app.current_user_id
--   public.set_updated_at()            BEFORE UPDATE trigger: updated_at/updated_by, created_* immutable
--   audit.forbid_update_delete()       append-only guard (RG4 audit, RG10 ledgers, history tables)
--   public.apply_table_standards(t)    applies the conventions driven by the comment contract (run by ddl/99_finalise.sql)
--   ref.create_lookup / ref.add_lookup_value   the enumeration + UI-label pattern (tables in ddl/07_ui_label.sql)

-- Actor for created_by / updated_by. The application sets it per transaction:
--   SET LOCAL app.current_user_id = '<app_user.id>';     (seed and DDL scripts use the system actor, id 1)
-- Returns NULL when unset, so a NOT NULL created_by fails loudly instead of recording a fake actor (RG5).
CREATE FUNCTION public.current_actor_id() RETURNS bigint
LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('app.current_user_id', true), '')::bigint $$;

CREATE FUNCTION public.set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  NEW.created_at := OLD.created_at;   -- creation facts are immutable
  NEW.created_by := OLD.created_by;
  NEW.updated_at := now();
  NEW.updated_by := coalesce(public.current_actor_id(), NEW.updated_by);
  RETURN NEW;
END
$$;

-- Append-only guard. Attached as BEFORE UPDATE OR DELETE (row) and BEFORE TRUNCATE (statement).
-- Grants are also revoked, so this is the second line of defence (it also stops the table owner).
CREATE FUNCTION audit.forbid_update_delete() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  RAISE EXCEPTION 'forbid_update_delete: % on %.% is not allowed; the table is append-only',
                  TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME
    USING HINT = 'Record a correction as a new row that references the original.';
END
$$;

-- Applies every convention that can be derived from the table definition and its comment.
-- Idempotent: safe to run again. The table comment must start with its delete class:
--   [soft-delete] [hard-delete] [append-only] [derived]
CREATE FUNCTION public.apply_table_standards(p_table regclass) RETURNS void
LANGUAGE plpgsql AS
$$
DECLARE
  v_schema  text;
  v_table   text;
  v_comment text;
  v_append  boolean;
  v_soft    boolean;
  v_col     record;
  v_cols    text[];
BEGIN
  SELECT n.nspname, c.relname, coalesce(obj_description(c.oid, 'pg_class'), '')
    INTO v_schema, v_table, v_comment
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.oid = p_table;

  v_append := v_comment LIKE '[append-only]%';
  v_soft   := v_comment LIKE '[soft-delete]%';

  SELECT array_agg(attname::text) INTO v_cols
    FROM pg_attribute WHERE attrelid = p_table AND attnum > 0 AND NOT attisdropped;

  -- 1. Standard comments for the standard columns (authors comment everything else).
  FOR v_col IN
    SELECT a.attname, a.attnum FROM pg_attribute a
     WHERE a.attrelid = p_table AND a.attnum > 0 AND NOT a.attisdropped
       AND a.attname IN ('id', 'created_at', 'created_by', 'updated_at', 'updated_by', 'deleted_at')
       AND col_description(p_table, a.attnum) IS NULL
  LOOP
    EXECUTE format('COMMENT ON COLUMN %s.%I IS %L', p_table, v_col.attname,
      CASE v_col.attname
        WHEN 'id'         THEN '[Internal] Surrogate primary key (bigint identity)'
        WHEN 'created_at' THEN '[Internal] Row creation instant (UTC)'
        WHEN 'created_by' THEN '[Internal] app_user who created the row (system actor = 1)'
        WHEN 'updated_at' THEN '[Internal] Last update instant (UTC), maintained by trigger'
        WHEN 'updated_by' THEN '[Internal] app_user who last updated the row'
        WHEN 'deleted_at' THEN '[Internal] Soft-delete instant; null: row is live (not deleted)'
      END);
  END LOOP;

  -- 2. Defaults for the audit columns.
  IF 'created_at' = ANY (v_cols) THEN EXECUTE format('ALTER TABLE %s ALTER COLUMN created_at SET DEFAULT now()', p_table); END IF;
  IF 'updated_at' = ANY (v_cols) THEN EXECUTE format('ALTER TABLE %s ALTER COLUMN updated_at SET DEFAULT now()', p_table); END IF;
  IF 'created_by' = ANY (v_cols) THEN EXECUTE format('ALTER TABLE %s ALTER COLUMN created_by SET DEFAULT public.current_actor_id()', p_table); END IF;
  IF 'updated_by' = ANY (v_cols) THEN EXECUTE format('ALTER TABLE %s ALTER COLUMN updated_by SET DEFAULT public.current_actor_id()', p_table); END IF;

  -- 3. updated_at trigger.
  IF 'updated_at' = ANY (v_cols)
     AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = p_table AND tgname = 'trg_' || v_table || '_set_updated_at') THEN
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()',
                   'trg_' || v_table || '_set_updated_at', p_table);
  END IF;

  -- 4. Append-only: guard triggers + no UPDATE/DELETE/TRUNCATE for application roles.
  IF v_append THEN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = p_table AND tgname = 'trg_' || v_table || '_forbid_update_delete') THEN
      EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION audit.forbid_update_delete()',
                     'trg_' || v_table || '_forbid_update_delete', p_table);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = p_table AND tgname = 'trg_' || v_table || '_forbid_truncate') THEN
      EXECUTE format('CREATE TRIGGER %I BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION audit.forbid_update_delete()',
                     'trg_' || v_table || '_forbid_truncate', p_table);
    END IF;
  END IF;

  -- 5. Actor FKs to admin.app_user (once the stub exists; dw is derived and exempt).
  IF to_regclass('admin.app_user') IS NOT NULL AND v_schema <> 'dw' THEN
    FOR v_col IN
      SELECT a.attname, a.attnum FROM pg_attribute a
       WHERE a.attrelid = p_table AND a.attname IN ('created_by', 'updated_by') AND NOT a.attisdropped
         AND NOT EXISTS (SELECT 1 FROM pg_constraint k
                          WHERE k.conrelid = p_table AND k.contype = 'f' AND k.conkey = ARRAY[a.attnum])
    LOOP
      EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT',
                     p_table, 'fk_' || v_table || '_' || v_col.attname, v_col.attname);
    END LOOP;
  END IF;

  -- 6. Soft-delete: default view that hides deleted rows (RG4). security_invoker keeps RLS of the caller.
  IF v_soft AND 'deleted_at' = ANY (v_cols) THEN
    EXECUTE format('CREATE OR REPLACE VIEW %I.%I WITH (security_invoker = true) AS SELECT * FROM %s WHERE deleted_at IS NULL',
                   v_schema, 'v_' || v_table, p_table);
    EXECUTE format('COMMENT ON VIEW %I.%I IS %L', v_schema, 'v_' || v_table,
                   'Default query surface for ' || v_schema || '.' || v_table || ': excludes soft-deleted rows');
    EXECUTE format('GRANT SELECT ON %I.%I TO talentra_app, talentra_readonly', v_schema, 'v_' || v_table);
  END IF;

  -- 7. Grants. A table tagged [integration-write] in its comment is written only by talentra_integration
  --    (external source of truth, docket Section 6); the application role can only read it.
  EXECUTE format('REVOKE ALL ON %s FROM PUBLIC', p_table);
  EXECUTE format('GRANT SELECT ON %s TO talentra_readonly', p_table);
  IF v_comment LIKE '%[integration-write]%' THEN
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON %s FROM talentra_app', p_table);
    EXECUTE format('GRANT SELECT ON %s TO talentra_app', p_table);
    EXECUTE format('GRANT SELECT, INSERT%s ON %s TO talentra_integration',
                   CASE WHEN v_append THEN '' ELSE ', UPDATE' END, p_table);
  ELSIF v_schema = 'dw' THEN
    EXECUTE format('GRANT SELECT ON %s TO talentra_app', p_table);
  ELSIF v_append THEN
    EXECUTE format('GRANT SELECT, INSERT ON %s TO talentra_app', p_table);
    EXECUTE format('REVOKE UPDATE, DELETE, TRUNCATE ON %s FROM talentra_app', p_table);
  ELSE
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %s TO talentra_app', p_table);
  END IF;
END
$$;

-- Enumeration pattern (RG3): every fixed value set is a lookup table with code, label_key, is_active, sort_order
-- and audit columns. Display text per UI language lives in ref.ui_translation via the label_key.
-- Extra columns (for example is_terminal) are added with ALTER TABLE after the call.
CREATE FUNCTION ref.create_lookup(p_table text, p_purpose text) RETURNS void
LANGUAGE plpgsql AS
$$
DECLARE
  v_schema text := split_part(p_table, '.', 1);
  v_name   text := split_part(p_table, '.', 2);
BEGIN
  IF v_name = '' THEN
    RAISE EXCEPTION 'create_lookup: pass a schema-qualified name, got %', p_table;
  END IF;
  EXECUTE format($f$
    CREATE TABLE %1$I.%2$I (
      id          bigint GENERATED ALWAYS AS IDENTITY,
      code        d_code       NOT NULL,
      label_key   varchar(150) NOT NULL,
      is_active   boolean      NOT NULL DEFAULT true,
      sort_order  integer      NOT NULL DEFAULT 0,
      created_at  timestamptz  NOT NULL DEFAULT now(),
      created_by  bigint       NOT NULL DEFAULT public.current_actor_id(),
      updated_at  timestamptz  NOT NULL DEFAULT now(),
      updated_by  bigint       NOT NULL DEFAULT public.current_actor_id(),
      CONSTRAINT %3$I PRIMARY KEY (id),
      CONSTRAINT %4$I UNIQUE (code),
      CONSTRAINT %5$I FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT,
      CONSTRAINT %6$I CHECK (sort_order >= 0)
    )$f$,
    v_schema, v_name, 'pk_' || v_name, 'uq_' || v_name || '_code',
    'fk_' || v_name || '_label_key', 'ck_' || v_name || '_sort_order');

  EXECUTE format('COMMENT ON TABLE %I.%I IS %L', v_schema, v_name,
                 '[hard-delete] Lookup: ' || p_purpose || '. Rows are deactivated (is_active), not deleted, once referenced.');
  EXECUTE format('COMMENT ON COLUMN %I.%I.code IS %L',       v_schema, v_name, '[Public] Stable machine code, lowercase snake_case; FK target for referencing columns');
  EXECUTE format('COMMENT ON COLUMN %I.%I.label_key IS %L',  v_schema, v_name, '[Public] UI label key; display text per language in ref.ui_translation');
  EXECUTE format('COMMENT ON COLUMN %I.%I.is_active IS %L',  v_schema, v_name, '[Public] false hides the value from new use; default true');
  EXECUTE format('COMMENT ON COLUMN %I.%I.sort_order IS %L', v_schema, v_name, '[Public] Display order, ascending; default 0');
END
$$;

-- Ensures a UI label '<prefix>.<slug of english>' exists with its default-language text; returns the key.
-- Used for translatable master data (industry, job_role ...) and lookups with extra columns.
CREATE FUNCTION ref.label_for(p_prefix text, p_english text) RETURNS varchar
LANGUAGE plpgsql AS
$$
DECLARE
  v_key text := p_prefix || '.' || trim(BOTH '_' FROM regexp_replace(lower(p_english), '[^a-z0-9]+', '_', 'g'));
BEGIN
  INSERT INTO ref.ui_label (label_key, translator_note)
  VALUES (v_key, 'Name: ' || p_english)
  ON CONFLICT (label_key) DO NOTHING;

  INSERT INTO ref.ui_translation (ui_label_id, language_id, translated_text)
  SELECT l.id, lang.id, p_english
    FROM ref.ui_label l, ref.language lang
   WHERE l.label_key = v_key AND lang.is_default
  ON CONFLICT (ui_label_id, language_id) DO NOTHING;

  RETURN v_key;
END
$$;

-- Adds one enumeration value with its UI label and default-language text (requires ddl/07_ui_label.sql).
CREATE FUNCTION ref.add_lookup_value(p_table regclass, p_code text, p_label text, p_sort_order integer DEFAULT 0)
RETURNS void
LANGUAGE plpgsql AS
$$
DECLARE
  v_name text := (SELECT relname FROM pg_class WHERE oid = p_table);
  v_key  text := 'enum.' || v_name || '.' || p_code;
BEGIN
  INSERT INTO ref.ui_label (label_key, translator_note)
  VALUES (v_key, 'Value ' || p_code || ' of lookup ' || v_name)
  ON CONFLICT (label_key) DO NOTHING;

  INSERT INTO ref.ui_translation (ui_label_id, language_id, translated_text)
  SELECT l.id, lang.id, p_label
    FROM ref.ui_label l, ref.language lang
   WHERE l.label_key = v_key AND lang.is_default
  ON CONFLICT (ui_label_id, language_id) DO NOTHING;

  EXECUTE format('INSERT INTO %s (code, label_key, sort_order) VALUES ($1, $2, $3)', p_table)
    USING p_code, v_key, p_sort_order;
END
$$;
