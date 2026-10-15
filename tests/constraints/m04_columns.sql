-- M4 gate: Phase 1 columns exist with the agreed domains, the lookup seed rows later milestones depend on are
-- present, and the column-level rules not covered by the lint hold. The lint (m01) checks class tags, null
-- reasons, float/timestamp bans and money/currency pairing on every gate.

DO $test$
BEGIN
  -- Lookup seed rows that M6 and later depend on
  PERFORM qa.assert_equals('application_status has the 7 pipeline codes',
    (SELECT string_agg(code, ',' ORDER BY sort_order) FROM ref.application_status),
    'applied,shortlisted,interviewed,offered,joined,rejected,withdrawn');
  PERFORM qa.assert_equals('terminal statuses are joined, rejected, withdrawn',
    (SELECT string_agg(code, ',' ORDER BY sort_order) FROM ref.application_status WHERE is_terminal),
    'joined,rejected,withdrawn');
  PERFORM qa.assert('application_status_transition is seeded and has no applied -> joined shortcut',
    (SELECT count(*) FROM job.application_status_transition) >= 10
    AND NOT EXISTS (SELECT 1 FROM job.application_status_transition
                     WHERE from_application_status_code = 'applied' AND to_application_status_code = 'joined'));
  PERFORM qa.assert_equals('disclosure codes (RG5 unknown vs not applicable)',
    (SELECT string_agg(code, ',' ORDER BY sort_order) FROM ref.disclosure), 'disclosed,not_disclosed,not_applicable');
  PERFORM qa.assert('job_requirement_status: only open accepts applications',
    (SELECT array_agg(code::text) FROM ref.job_requirement_status WHERE accepts_applications) = ARRAY['open']::text[]);
  PERFORM qa.assert('publish_state seeded', (SELECT count(*) FROM ref.publish_state) = 5);
  PERFORM qa.assert('languages, currencies, countries, cities seeded',
    (SELECT count(*) FROM ref.language) >= 10 AND (SELECT count(*) FROM ref.currency) >= 5
    AND (SELECT count(*) FROM ref.country) >= 5 AND (SELECT count(*) FROM ref.city) >= 10);

  -- Every lookup value is displayable: its label has a default-language translation (keys never shown)
  PERFORM qa.assert_equals('every ui_label has a default-language translation',
    (SELECT count(*) FROM ref.ui_label l
      WHERE NOT EXISTS (SELECT 1 FROM ref.ui_translation t JOIN ref.language g ON g.id = t.language_id
                         WHERE t.ui_label_id = l.id AND g.is_default))::int, 0);
  PERFORM qa.assert_equals('ui_text resolves a lookup label in Hindi with English fallback',
    ref.ui_text('enum.application_status.shortlisted', 'hi'), 'Shortlisted'::varchar);

  -- Unbounded text only where justified (RG3): job description and resume body
  PERFORM qa.assert_equals('text columns are exactly job_requirement.description and resume_version.body',
    (SELECT string_agg(table_schema || '.' || table_name || '.' || column_name, ',' ORDER BY table_schema, table_name, column_name)
       FROM information_schema.columns
      WHERE data_type = 'text' AND table_schema IN ('ref', 'profile', 'job', 'admin', 'org')
        AND table_name NOT LIKE 'v\_%'),
    'job.job_requirement.description,profile.resume_version.body');

  -- Domains on the columns that carry them
  PERFORM qa.assert_equals('candidate_profile.full_name uses d_person_name',
    (SELECT domain_name::text FROM information_schema.columns WHERE table_schema = 'profile'
        AND table_name = 'candidate_profile' AND column_name = 'full_name'), 'd_person_name');
  PERFORM qa.assert_equals('candidate_contact email/phone use d_email/d_phone_e164',
    (SELECT string_agg(domain_name, ',' ORDER BY column_name) FROM information_schema.columns
      WHERE table_schema = 'profile' AND table_name = 'candidate_contact' AND column_name IN ('email', 'phone')),
    'd_email,d_phone_e164');
  PERFORM qa.assert_equals('salary columns use d_money',
    (SELECT count(*) FROM information_schema.columns WHERE domain_name = 'd_money'
        AND (table_name, column_name) IN (('job_requirement', 'salary_min'), ('job_requirement', 'salary_max'),
                                          ('candidate_profile', 'current_salary_amount'), ('candidate_profile', 'expected_salary_amount'),
                                          ('offer', 'ctc_amount')))::int, 5);

  -- National identifiers are never stored in clear (Section 6)
  PERFORM qa.assert('candidate_identity_document has no clear identifier column',
    NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'profile'
                   AND table_name = 'candidate_identity_document'
                   AND column_name IN ('identifier', 'identifier_value', 'document_number')));

  -- User-entered free text records its language (RG7)
  PERFORM qa.assert_equals('description/summary/body columns have a *_language_id companion',
    (SELECT count(*) FROM information_schema.columns c
      WHERE c.table_schema IN ('profile', 'job') AND c.column_name IN ('description', 'summary', 'body')
        AND c.table_name NOT LIKE 'v\_%'
        AND NOT EXISTS (SELECT 1 FROM information_schema.columns l
                         WHERE l.table_schema = c.table_schema AND l.table_name = c.table_name
                           AND l.column_name = c.column_name || '_language_id'))::int, 0);
END
$test$;
