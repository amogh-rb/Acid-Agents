-- name: Apply to a job (transactional; transition and history triggers fire)
-- kind: transactional
-- mode: dml
INSERT INTO job.application (job_requirement_id, candidate_profile_id) VALUES (:open_job, :apply_cand);
