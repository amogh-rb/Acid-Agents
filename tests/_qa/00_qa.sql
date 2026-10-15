-- Test harness (loaded by run.ps1 before tests; never part of the production DDL).
-- Test files call these from DO blocks. run.ps1 wraps every .sql test file in BEGIN ... ROLLBACK,
-- so tests can create rows and scratch objects freely.

CREATE SCHEMA qa;
COMMENT ON SCHEMA qa IS 'Test harness: assertions, catalog lint. Excluded from lint and finalise.';

-- Negative test: p_sql must fail, and the error must name p_expected
-- (matched against the constraint name, else searched in the message, e.g. a trigger or function name).
CREATE FUNCTION qa.expect_error(p_label text, p_sql text, p_expected text) RETURNS void
LANGUAGE plpgsql AS
$$
DECLARE
  v_constraint text;
  v_schema     text;
  v_message    text;
  v_state      text;
  v_index      regclass;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME, v_schema = SCHEMA_NAME,
                            v_message = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    IF coalesce(v_constraint, '') = p_expected OR position(p_expected IN v_message) > 0 THEN
      RAISE NOTICE 'PASS  %: rejected by %', p_label, p_expected;
      RETURN;
    END IF;
    -- On a partitioned table PostgreSQL reports the partition's own index (application_h24_..._key);
    -- accept it when that index is a partition of the expected constraint's index.
    IF v_constraint <> '' AND v_schema <> '' THEN
      v_index := to_regclass(quote_ident(v_schema) || '.' || quote_ident(v_constraint));
      IF v_index IS NOT NULL AND EXISTS (
           SELECT 1 FROM pg_partition_ancestors(v_index) a
             JOIN pg_constraint c ON c.conindid = a.relid
            WHERE c.conname = p_expected) THEN
        RAISE NOTICE 'PASS  %: rejected by % (partition index %)', p_label, p_expected, v_constraint;
        RETURN;
      END IF;
    END IF;
    RAISE EXCEPTION 'FAIL  %: expected % but got [%] % (constraint: %)',
                    p_label, p_expected, v_state, v_message, coalesce(v_constraint, 'none');
  END;
  RAISE EXCEPTION 'FAIL  %: statement succeeded but should have been rejected by %', p_label, p_expected;
END
$$;

-- Positive test: p_sql must succeed.
CREATE FUNCTION qa.expect_ok(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS
$$
DECLARE
  v_message text;
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE 'PASS  %', p_label;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
  RAISE EXCEPTION 'FAIL  %: % ', p_label, v_message;
END
$$;

CREATE FUNCTION qa.assert(p_label text, p_condition boolean, p_detail text DEFAULT '') RETURNS void
LANGUAGE plpgsql AS
$$
BEGIN
  IF p_condition IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL  %: %', p_label, p_detail;
  END IF;
  RAISE NOTICE 'PASS  %', p_label;
END
$$;

CREATE FUNCTION qa.assert_equals(p_label text, p_actual anyelement, p_expected anyelement) RETURNS void
LANGUAGE plpgsql AS
$$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'FAIL  %: expected %, got %', p_label, p_expected, p_actual;
  END IF;
  RAISE NOTICE 'PASS  % (= %)', p_label, p_actual;
END
$$;

-- Plan lines of a statement (EXPLAIN, no execution), for pruning and index-usage assertions.
CREATE FUNCTION qa.explain_lines(p_sql text) RETURNS SETOF text
LANGUAGE plpgsql AS
$$
DECLARE
  r record;
BEGIN
  FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) ' || p_sql LOOP
    RETURN NEXT r."QUERY PLAN";
  END LOOP;
END
$$;

CREATE TABLE qa.mysql_reserved_word (word text PRIMARY KEY);
