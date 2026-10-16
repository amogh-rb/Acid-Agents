-- name: A company's open jobs with application counts
-- kind: functional
-- mode: select
SELECT j.id, j.job_title, count(a.id) AS applications
  FROM job.job_requirement j LEFT JOIN job.application a ON a.job_requirement_id = j.id
 WHERE j.organisation_id = :hot_org AND j.job_requirement_status_code = 'open' AND j.deleted_at IS NULL
 GROUP BY j.id, j.job_title ORDER BY applications DESC LIMIT 50;
