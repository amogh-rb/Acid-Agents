-- Catalog lint (rule groups 1-8). Tagged m01 so it runs in every gate from M1 onward.
DO $test$
DECLARE
  v record;
  n integer := 0;
BEGIN
  FOR v IN SELECT * FROM qa.lint_violations() LOOP
    n := n + 1;
    RAISE WARNING 'LINT  % | % | %', v.rule, v.object_name, v.detail;
  END LOOP;
  IF n > 0 THEN
    RAISE EXCEPTION 'FAIL  lint: % violation(s), listed above', n;
  END IF;
  RAISE NOTICE 'PASS  lint: 0 violations across % tables and % columns',
    (SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'qa')),
    (SELECT count(*) FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'qa'));
END
$test$;
