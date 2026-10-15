-- Master data (ref). Owner A.
-- M3: the status lookups the stubs need. M4 adds geography, skills, education, industry, roles and the rest
-- of the enumeration lookups (docs/phase1/entities.md).

SET app.current_user_id = '1';   -- system actor (admin.app_user id 1, created in ddl/15_stubs.sql)

SELECT ref.create_lookup('ref.user_status', 'app_user account status');
SELECT ref.add_lookup_value('ref.user_status', 'pending_verification', 'Pending verification', 1);
SELECT ref.add_lookup_value('ref.user_status', 'active',               'Active',               2);
SELECT ref.add_lookup_value('ref.user_status', 'suspended',            'Suspended',            3);
SELECT ref.add_lookup_value('ref.user_status', 'deactivated',          'Deactivated',          4);

SELECT ref.create_lookup('ref.organisation_status', 'organisation account status');
SELECT ref.add_lookup_value('ref.organisation_status', 'pending_verification', 'Pending verification', 1);
SELECT ref.add_lookup_value('ref.organisation_status', 'active',               'Active',               2);
SELECT ref.add_lookup_value('ref.organisation_status', 'suspended',            'Suspended',            3);
SELECT ref.add_lookup_value('ref.organisation_status', 'closed',               'Closed',               4);
