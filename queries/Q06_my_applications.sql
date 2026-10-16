-- name: A candidate's applications with job and status
-- kind: functional
-- mode: select
SELECT a.id, a.application_status_code, j.job_title, a.applied_at
  FROM job.application a JOIN job.job_requirement j ON j.id = a.job_requirement_id
 WHERE a.candidate_profile_id = :cand
 ORDER BY a.applied_at DESC;
