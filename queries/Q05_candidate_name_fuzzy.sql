-- name: Candidate name search (substring, trigram index)
-- kind: performance
-- mode: select
SELECT count(*) FROM profile.candidate_profile WHERE full_name ILIKE '%Iyer%' AND deleted_at IS NULL;
