-- name: Pipeline counts of the most applied-to job
-- kind: functional, performance (crosses every application partition)
-- mode: select
SELECT application_status_code, count(*) FROM job.application WHERE job_requirement_id = :hot_job GROUP BY 1 ORDER BY 2 DESC;
