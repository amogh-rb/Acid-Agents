-- name: Candidates holding every mandatory skill of a job
-- kind: performance (skill join; expected to degrade first at full scale)
-- mode: select
SELECT cs.candidate_profile_id, count(*) AS matched
  FROM job.job_requirement_skill jr JOIN profile.candidate_skill cs ON cs.skill_id = jr.skill_id
 WHERE jr.job_requirement_id = :hot_job AND jr.is_mandatory
 GROUP BY cs.candidate_profile_id
HAVING count(*) = (SELECT count(*) FROM job.job_requirement_skill WHERE job_requirement_id = :hot_job AND is_mandatory)
 ORDER BY cs.candidate_profile_id LIMIT 50;
