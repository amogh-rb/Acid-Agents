-- name: Job search by role (newest open, published, live jobs)
-- kind: functional, lookup
-- mode: select
SELECT j.id, j.job_title, j.published_at, o.organisation_name
  FROM job.job_requirement j JOIN org.organisation o ON o.id = j.organisation_id
 WHERE j.job_requirement_status_code = 'open' AND j.publish_state_code = 'published' AND j.deleted_at IS NULL
   AND j.job_role_id = :role_id
 ORDER BY j.published_at DESC LIMIT 20;
