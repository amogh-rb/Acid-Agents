-- name: Possible duplicate profiles sharing a phone number
-- kind: lookup, data quality
-- mode: select
SELECT c2.candidate_profile_id, cp.full_name
  FROM profile.candidate_contact c
  JOIN profile.candidate_contact c2 ON c2.phone = c.phone AND c2.candidate_profile_id <> c.candidate_profile_id
  JOIN profile.candidate_profile cp ON cp.id = c2.candidate_profile_id
 WHERE c.candidate_profile_id = :dup_cand AND c.phone IS NOT NULL;
