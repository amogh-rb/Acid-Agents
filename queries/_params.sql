-- Sample parameters for the query set, chosen from the seeded data so every query has something to find.
SET app.current_user_id = '1';
SELECT job_requirement_id AS hot_job FROM job.application GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1 \gset
SELECT organisation_id AS hot_org FROM job.job_requirement WHERE id = :hot_job \gset
SELECT job_role_id AS role_id FROM job.job_requirement WHERE id = :hot_job \gset
SELECT id AS cand FROM profile.candidate_profile WHERE id >= (SELECT max(id) / 2 FROM profile.candidate_profile)
   AND EXISTS (SELECT 1 FROM profile.candidate_contact c WHERE c.candidate_profile_id = profile.candidate_profile.id AND c.phone IS NOT NULL) ORDER BY id LIMIT 1 \gset
SELECT email AS cand_email FROM profile.candidate_contact WHERE candidate_profile_id = :cand AND email IS NOT NULL \gset
SELECT j.id AS open_job FROM job.job_requirement j WHERE j.job_requirement_status_code = 'open' AND j.publish_state_code = 'published' AND j.deleted_at IS NULL
   ORDER BY j.id DESC LIMIT 1 \gset
SELECT c.id AS apply_cand FROM profile.candidate_profile c
   WHERE c.id > (SELECT max(id) / 3 FROM profile.candidate_profile) AND NOT EXISTS (SELECT 1 FROM job.application a WHERE a.candidate_profile_id = c.id AND a.job_requirement_id = :open_job)
   ORDER BY c.id LIMIT 1 \gset
SELECT app_user_id AS rec_user FROM lic.licence_seat WHERE released_at IS NULL ORDER BY id LIMIT 1 \gset
SELECT id AS wallet FROM billing.wallet ORDER BY id LIMIT 1 \gset
-- a candidate whose phone number is shared with another profile (a seeded near-duplicate), for Q04
SELECT min(c.candidate_profile_id) AS dup_cand FROM profile.candidate_contact c
 WHERE c.phone = (SELECT phone FROM profile.candidate_contact WHERE phone IS NOT NULL AND candidate_profile_id > (SELECT max(id) / 2 FROM profile.candidate_profile)
                   GROUP BY phone HAVING count(*) > 1 ORDER BY phone LIMIT 1) \gset
