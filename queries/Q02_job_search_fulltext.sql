-- name: Job search by keyword (full text over title and description)
-- kind: performance
-- mode: select
SELECT j.id, j.job_title, j.published_at
  FROM job.job_requirement j
 WHERE to_tsvector('simple'::regconfig, j.job_title || ' ' || j.description) @@ plainto_tsquery('simple', 'analyst')
   AND j.job_requirement_status_code = 'open' AND j.publish_state_code = 'published' AND j.deleted_at IS NULL
 ORDER BY j.published_at DESC LIMIT 20;
