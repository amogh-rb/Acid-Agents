-- M10 gate, Organisation and account (B34): hierarchy, identifiers, recruiter mapping, locations, verification.

DO $test$
DECLARE
  v_recruiter bigint;
  v_a         bigint;
  v_b         bigint;
  v_c         bigint;
  v_ident     bigint;
  v_key       text := 'test-only-key-held-outside-the-database';
BEGIN
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'ravi.recruiter@example.com') RETURNING id INTO v_recruiter;
  INSERT INTO org.organisation (organisation_name, legal_name) VALUES ('Northbridge Group', 'Northbridge Workforce Systems Pvt Ltd') RETURNING id INTO v_a;
  INSERT INTO org.organisation (organisation_name, parent_organisation_id) VALUES ('Northbridge Staffing', v_a) RETURNING id INTO v_b;
  INSERT INTO org.organisation (organisation_name, parent_organisation_id) VALUES ('Northbridge Staffing South', v_b) RETURNING id INTO v_c;

  -- hierarchy
  PERFORM qa.expect_error('organisation that is its own parent',
    format('UPDATE org.organisation SET parent_organisation_id = %s WHERE id = %s', v_a, v_a), 'ck_organisation_not_own_parent');
  PERFORM qa.expect_error('3-level cycle (group placed under its own grandchild)',
    format('UPDATE org.organisation SET parent_organisation_id = %s WHERE id = %s', v_c, v_a), 'trg_organisation_hierarchy');
  PERFORM qa.expect_ok('moving a division under another branch is fine',
    format('UPDATE org.organisation SET parent_organisation_id = %s WHERE id = %s', v_a, v_c));

  -- recruiter mapping (B34)
  INSERT INTO org.recruiter_mapping (app_user_id, organisation_id, valid_period) VALUES (v_recruiter, v_a, daterange('2026-01-01', NULL));
  PERFORM qa.expect_error('recruiter mapped to two companies in overlapping periods',
    format('INSERT INTO org.recruiter_mapping (app_user_id, organisation_id, valid_period) VALUES (%s, %s, daterange(%L, NULL))',
           v_recruiter, v_b, '2026-03-01'),
    'ex_recruiter_mapping_valid_range');
  UPDATE org.recruiter_mapping SET valid_period = daterange('2026-01-01', '2026-03-01') WHERE app_user_id = v_recruiter;
  PERFORM qa.expect_ok('back-to-back mapping to the next company',
    format('INSERT INTO org.recruiter_mapping (app_user_id, organisation_id, valid_period) VALUES (%s, %s, daterange(%L, NULL))',
           v_recruiter, v_b, '2026-03-01'));
  PERFORM qa.assert_equals('current_recruiter_organisation returns the mapping in force today',
    org.current_recruiter_organisation(v_recruiter), v_b);

  -- identifiers: validated, encrypted, unique by hash
  PERFORM qa.expect_error('identifier without an encryption key in the session',
    format('SELECT org.add_identifier(%s, %L, %L)', v_a, 'gstin', '33AABCN1234F1Z5'), 'app.encryption_key is not set');
  PERFORM set_config('app.encryption_key', v_key, true);
  PERFORM qa.expect_error('GSTIN in the wrong format',
    format('SELECT org.add_identifier(%s, %L, %L)', v_a, 'gstin', '33-AABCN-1234'), 'does not match the gstin format');
  PERFORM qa.expect_error('person-only identifier type on an organisation',
    format('SELECT org.add_identifier(%s, %L, %L)', v_a, 'aadhaar', '234567890123'), 'is not an organisation identifier type');
  v_ident := org.add_identifier(v_a, 'gstin', '33aabcn1234f1z5');
  PERFORM qa.assert('identifier is stored encrypted, never in clear',
    position('33AABCN1234F1Z5'::bytea IN (SELECT value_encrypted FROM org.organisation_identifier WHERE id = v_ident)) = 0);
  PERFORM qa.assert_equals('decrypting with the session key returns the normalised value',
    (SELECT pgp_sym_decrypt(value_encrypted, v_key) FROM org.organisation_identifier WHERE id = v_ident), '33AABCN1234F1Z5');
  PERFORM qa.assert_equals('only the last 4 characters are kept for display',
    (SELECT value_last4::text FROM org.organisation_identifier WHERE id = v_ident), 'F1Z5');
  PERFORM qa.expect_error('the same GSTIN registered for a second organisation (duplicate hash)',
    format('SELECT org.add_identifier(%s, %L, %L)', v_b, 'gstin', '33AABCN1234F1Z5'), 'uq_organisation_identifier_value_hash');

  -- locations
  INSERT INTO org.organisation_location (organisation_id, location_name, address_line1, city_id, is_headquarters)
  SELECT v_a, 'Chennai HQ', '1 Anna Salai', id, true FROM ref.city WHERE city_name = 'Chennai';
  PERFORM qa.expect_error('second headquarters',
    format('INSERT INTO org.organisation_location (organisation_id, location_name, address_line1, city_id, is_headquarters) '
           || 'SELECT %s, %L, %L, id, true FROM ref.city WHERE city_name = %L', v_a, 'Pune Office', '2 FC Road', 'Pune'),
    'uq_organisation_location_one_headquarters');

  -- verification (integration boundary)
  INSERT INTO org.verification (organisation_id, verification_kind_code, organisation_identifier_id, idempotency_key)
  VALUES (v_a, 'tax_registration', v_ident, 'verif-0001');
  PERFORM qa.expect_error('retried verification with the same idempotency key',
    format('INSERT INTO org.verification (organisation_id, verification_kind_code, idempotency_key) VALUES (%s, %L, %L)',
           v_a, 'address', 'verif-0001'),
    'uq_verification_idempotency_key');
  PERFORM qa.expect_error('verification marked verified without a completion time',
    format('UPDATE org.verification SET verification_status_code = %L WHERE idempotency_key = %L', 'verified', 'verif-0001'),
    'ck_verification_completed');
END
$test$;
