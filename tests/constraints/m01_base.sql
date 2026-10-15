-- M1 gate: database, domains, base functions, UI-label pattern and the lint itself.
-- run.ps1 wraps this file in BEGIN ... ROLLBACK, so the probe objects below never persist.

-- 1. Database, schemas, extensions
DO $test$
BEGIN
  PERFORM qa.assert_equals('database encoding is UTF8',
    (SELECT pg_encoding_to_char(encoding)::text FROM pg_database WHERE datname = current_database()), 'UTF8');
  PERFORM qa.assert_equals('13 module schemas exist',
    (SELECT count(*) FROM pg_namespace
      WHERE nspname IN ('ref','admin','org','profile','job','gig','lic','src','billing','notif','dw','audit','app'))::int, 13);
  PERFORM qa.assert_equals('extensions btree_gist, pg_trgm, pgcrypto installed',
    (SELECT count(*) FROM pg_extension WHERE extname IN ('btree_gist','pg_trgm','pgcrypto'))::int, 3);
  PERFORM qa.assert('group roles exist',
    (SELECT count(*) FROM pg_roles WHERE rolname IN ('talentra_app','talentra_readonly')) = 2);
END
$test$;

-- 2. Domains (RG3)
DO $test$
BEGIN
  PERFORM qa.expect_error('d_email rejects uppercase Foo@X.com', $q$SELECT 'Foo@X.com'::d_email$q$, 'ck_d_email_lowercase');
  PERFORM qa.expect_error('d_email rejects a value without @',   $q$SELECT 'foo.x.com'::d_email$q$, 'ck_d_email_format');
  PERFORM qa.expect_ok   ('d_email accepts foo@x.com',           $q$SELECT 'foo@x.com'::d_email$q$);
  PERFORM qa.expect_ok   ('d_phone_e164 accepts +919840012345',  $q$SELECT '+919840012345'::d_phone_e164$q$);
  PERFORM qa.expect_error('d_phone_e164 rejects 98400 12345',    $q$SELECT '98400 12345'::d_phone_e164$q$, 'ck_d_phone_e164_format');
  PERFORM qa.expect_error('d_pct rejects -1',                    $q$SELECT (-1)::d_pct$q$, 'ck_d_pct_range');
  PERFORM qa.expect_error('d_pct rejects 100.01',                $q$SELECT 100.01::d_pct$q$, 'ck_d_pct_range');
  PERFORM qa.expect_ok   ('d_pct accepts 0 and 100',             $q$SELECT 0::d_pct, 100::d_pct$q$);
  PERFORM qa.expect_error('d_person_name rejects blank',         $q$SELECT '   '::d_person_name$q$, 'ck_d_person_name_not_blank');
  PERFORM qa.expect_ok   ('d_person_name accepts any script',    $q$SELECT 'முருகன் கார்த்திக்'::d_person_name, '李小龍'::d_person_name$q$);
  PERFORM qa.expect_error('d_lat rejects 90.5',                  $q$SELECT 90.5::d_lat$q$, 'ck_d_lat_range');
  PERFORM qa.expect_error('d_lng rejects 181',                   $q$SELECT 181::d_lng$q$, 'ck_d_lng_range');
  PERFORM qa.expect_error('d_code rejects Applied',              $q$SELECT 'Applied'::d_code$q$, 'ck_d_code_format');
  PERFORM qa.expect_error('d_currency_code rejects inr',         $q$SELECT 'inr'::d_currency_code$q$, 'ck_d_currency_code_format');
  PERFORM qa.assert_equals('d_money is fixed precision numeric(14,2)',
    (SELECT format_type(typbasetype, typtypmod) FROM pg_type WHERE typname = 'd_money'), 'numeric(14,2)');
END
$test$;

-- 3. Base functions on probe tables: actor columns, updated_at trigger, append-only guard, soft-delete view
CREATE SCHEMA lint_probe;

CREATE TABLE lint_probe.probe_event (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  note        varchar(50) NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_probe_event PRIMARY KEY (id)
);
COMMENT ON TABLE  lint_probe.probe_event IS '[append-only] Probe for the append-only guard';
COMMENT ON COLUMN lint_probe.probe_event.note IS '[Internal] Probe value';

CREATE TABLE lint_probe.probe_item (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  label       varchar(50) NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_probe_item PRIMARY KEY (id)
);
COMMENT ON TABLE  lint_probe.probe_item IS '[hard-delete] Probe for the updated_at trigger';
COMMENT ON COLUMN lint_probe.probe_item.label IS '[Internal] Probe value';

CREATE TABLE lint_probe.probe_doc (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  title       varchar(50) NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  bigint      NOT NULL DEFAULT public.current_actor_id(),
  deleted_at  timestamptz,
  CONSTRAINT pk_probe_doc PRIMARY KEY (id)
);
COMMENT ON TABLE  lint_probe.probe_doc IS '[soft-delete] Probe for the default soft-delete view';
COMMENT ON COLUMN lint_probe.probe_doc.title IS '[Internal] Probe value';

DO $$ BEGIN
  PERFORM public.apply_table_standards('lint_probe.probe_event');
  PERFORM public.apply_table_standards('lint_probe.probe_item');
  PERFORM public.apply_table_standards('lint_probe.probe_doc');
END $$;

DO $test$
DECLARE
  v_item lint_probe.probe_item;
  v_a    bigint := 7;   -- two distinct actors; real app_user rows once the stub exists (M3+)
  v_b    bigint := 8;
BEGIN
  IF to_regclass('admin.app_user') IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', '1', true);
    EXECUTE 'INSERT INTO admin.app_user (user_status_code) VALUES (''pending_verification'') RETURNING id' INTO v_a;
    EXECUTE 'INSERT INTO admin.app_user (user_status_code) VALUES (''pending_verification'') RETURNING id' INTO v_b;
  END IF;
  PERFORM set_config('app.current_user_id', v_a::text, true);
  PERFORM qa.assert_equals('current_actor_id reads app.current_user_id', public.current_actor_id(), v_a);

  INSERT INTO lint_probe.probe_event (note) VALUES ('first');
  PERFORM qa.assert_equals('created_by defaults to the current actor',
    (SELECT created_by FROM lint_probe.probe_event), v_a);
  PERFORM qa.expect_error('append-only table rejects UPDATE',   $q$UPDATE lint_probe.probe_event SET note = 'changed'$q$, 'forbid_update_delete');
  PERFORM qa.expect_error('append-only table rejects DELETE',   $q$DELETE FROM lint_probe.probe_event$q$, 'forbid_update_delete');
  PERFORM qa.expect_error('append-only table rejects TRUNCATE', $q$TRUNCATE lint_probe.probe_event$q$, 'forbid_update_delete');
  PERFORM qa.assert('talentra_app has no UPDATE on the append-only table',
    NOT has_table_privilege('talentra_app', 'lint_probe.probe_event', 'UPDATE'));

  INSERT INTO lint_probe.probe_item (label) VALUES ('a');
  PERFORM set_config('app.current_user_id', v_b::text, true);
  UPDATE lint_probe.probe_item SET label = 'b', updated_at = '2000-01-01', created_by = 99, created_at = '2000-01-01';
  SELECT * INTO v_item FROM lint_probe.probe_item;
  PERFORM qa.assert('set_updated_at overrides a stale updated_at', v_item.updated_at > '2001-01-01');
  PERFORM qa.assert_equals('set_updated_at records the updating actor', v_item.updated_by, v_b);
  PERFORM qa.assert_equals('created_by is immutable', v_item.created_by, v_a);
  PERFORM qa.assert('created_at is immutable', v_item.created_at > '2001-01-01');

  PERFORM set_config('app.current_user_id', '', true);
  PERFORM qa.assert('current_actor_id is NULL when unset', public.current_actor_id() IS NULL);
  PERFORM qa.expect_error('insert without an actor fails (no fake actor)',
    $q$INSERT INTO lint_probe.probe_item (label) VALUES ('c')$q$, 'created_by');
  PERFORM set_config('app.current_user_id', v_a::text, true);

  INSERT INTO lint_probe.probe_doc (title) VALUES ('kept'), ('removed');
  UPDATE lint_probe.probe_doc SET deleted_at = now() WHERE title = 'removed';
  PERFORM qa.assert_equals('soft-delete view v_probe_doc hides deleted rows',
    (SELECT count(*) FROM lint_probe.v_probe_doc)::int, 1);

  PERFORM qa.assert_equals('compliant probe tables produce no lint violations',
    (SELECT count(*) FROM qa.lint_violations() WHERE object_name LIKE 'lint_probe.%')::int, 0);
END
$test$;

-- 4. UI-label pattern: create a lookup, add a value, translate it, resolve with fallback
DO $$ BEGIN
  PERFORM ref.create_lookup('lint_probe.probe_status', 'probe status values');
  PERFORM public.apply_table_standards('lint_probe.probe_status');
END $$;

DO $test$
BEGIN
  PERFORM set_config('app.current_user_id', '1', true);
  PERFORM ref.add_lookup_value('lint_probe.probe_status', 'open', 'Open', 1);
  INSERT INTO ref.ui_translation (ui_label_id, language_id, translated_text)
  SELECT l.id, lang.id, 'खुला' FROM ref.ui_label l, ref.language lang
   WHERE l.label_key = 'enum.probe_status.open' AND lang.code = 'hi';

  PERFORM qa.assert_equals('exactly one default language',
    (SELECT count(*) FROM ref.language WHERE is_default)::int, 1);
  PERFORM qa.assert_equals('ui_text returns the requested language', ref.ui_text('enum.probe_status.open', 'hi'), 'खुला'::varchar);
  PERFORM qa.assert_equals('ui_text falls back to the default language', ref.ui_text('enum.probe_status.open', 'ta'), 'Open'::varchar);
  PERFORM qa.assert('ui_text never returns the key for an unknown label', ref.ui_text('enum.probe_status.nope', 'en') IS NULL);
  PERFORM qa.expect_error('second default language is rejected',
    $q$UPDATE ref.language SET is_default = true WHERE code = 'hi'$q$, 'uq_language_is_default');
  PERFORM qa.expect_error('lookup code must be lowercase snake_case',
    $q$INSERT INTO lint_probe.probe_status (code, label_key) VALUES ('Closed', 'enum.probe_status.open')$q$, 'ck_d_code_format');
  PERFORM qa.expect_error('lookup label_key must exist in ref.ui_label',
    $q$INSERT INTO lint_probe.probe_status (code, label_key) VALUES ('ghost', 'enum.probe_status.ghost')$q$, 'fk_probe_status_label_key');
  PERFORM qa.assert_equals('lookup tables built by the pattern pass the lint',
    (SELECT count(*) FROM qa.lint_violations() WHERE object_name LIKE 'lint_probe.probe_status%')::int, 0);
END
$test$;

-- 5. Lint self-test: deliberately bad objects must trip every rule the lint claims to check
CREATE TABLE lint_probe.widgets (
  id             integer,
  "order"        integer,
  "BadCol"       integer,
  price          numeric(10,2),
  fee            d_money,
  score          double precision,
  seen_at        timestamp,
  is_hot         boolean,
  owner_id       bigint,
  body           text,
  contact_email  varchar(254),
  phone          varchar(16),
  full_name      varchar(150),
  latitude       numeric(9,6),
  match_pct      numeric(5,2),
  secret         varchar(50),
  CONSTRAINT price_positive CHECK (price > 0),
  CONSTRAINT ck_widgets_this_check_constraint_name_is_far_too_long_to_survive_intact CHECK (id > 0)
);
COMMENT ON COLUMN lint_probe.widgets.secret IS '[Sensitive] stored in clear; null: probe';
CREATE INDEX widgets_owner ON lint_probe.widgets (owner_id);
CREATE TRIGGER bad_trigger BEFORE UPDATE ON lint_probe.widgets FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE VIEW lint_probe.widget_view AS SELECT id FROM lint_probe.widgets;

CREATE TABLE lint_probe.dim_thing (id bigint GENERATED ALWAYS AS IDENTITY, CONSTRAINT pk_dim_thing PRIMARY KEY (id));
COMMENT ON TABLE lint_probe.dim_thing IS '[derived] dim_ outside dw';

CREATE TABLE lint_probe.raw_log (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  bigint      NOT NULL DEFAULT 1,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  bigint      NOT NULL DEFAULT 1,
  CONSTRAINT pk_raw_log PRIMARY KEY (id)
);
COMMENT ON TABLE lint_probe.raw_log IS '[append-only] guard never applied';

CREATE TABLE lint_probe.half_soft (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  bigint      NOT NULL DEFAULT 1,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  bigint      NOT NULL DEFAULT 1,
  CONSTRAINT pk_half_soft PRIMARY KEY (id)
);
COMMENT ON TABLE lint_probe.half_soft IS '[soft-delete] has no deleted_at';

DO $test$
DECLARE
  v_rule text;
BEGIN
  CREATE TEMP TABLE tmp_lint ON COMMIT DROP AS
    SELECT * FROM qa.lint_violations() WHERE object_name LIKE 'lint_probe.%';

  FOREACH v_rule IN ARRAY ARRAY[
    'RG1 snake_case', 'RG1 singular', 'RG1 reserved word', 'RG1 constraint name', 'RG1 index name', 'RG1 trigger name',
    'RG1 truncated name',
    'RG2 primary key', 'RG2 surrogate key', 'RG2 foreign key',
    'RG3 float', 'RG3 timestamp', 'RG3 money domain', 'RG3 money currency', 'RG3 unbounded text', 'RG3 email',
    'RG3 phone', 'RG3 person name', 'RG3 coordinates', 'RG3 percentage', 'RG3 boolean',
    'RG4 delete class', 'RG4 audit columns', 'RG4 soft delete', 'RG4 append-only', 'RG4 updated_at trigger',
    'RG5 null reason', 'RG6 class tag', 'RG6 sensitive form', 'RG7 language', 'RG8 physical name']
  LOOP
    PERFORM qa.assert('lint detects ' || v_rule, EXISTS (SELECT 1 FROM tmp_lint WHERE rule = v_rule),
                      'no violation reported for the bad probe objects');
  END LOOP;
END
$test$;
