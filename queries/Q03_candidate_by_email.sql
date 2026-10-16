-- name: Candidate lookup by email (exact)
-- kind: lookup
-- mode: select
SELECT cp.id, cp.full_name, cp.current_city_id
  FROM profile.candidate_contact c JOIN profile.candidate_profile cp ON cp.id = c.candidate_profile_id
 WHERE c.email = :'cand_email';
