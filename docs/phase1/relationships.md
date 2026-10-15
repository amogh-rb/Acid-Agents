# Phase 1 relationships (M3: B8-B11)

**Conventions**
- `child.column` names the FK column (the schema is given in `entities.md`).
- Cardinality is child:parent. `N:1` means many children per parent; `1:1` means the child FK is also unique.
- **Optional?**
  - yes = the FK column is nullable, and the reason column says why NULL is meaningful.
  - no = NOT NULL.
- **ON DELETE:** RESTRICT by default. CASCADE only for owned children, and the reason column justifies it. SET NULL only where the child must outlive the parent.
- **ON UPDATE** is NO ACTION everywhere: ids are identity values, and lookup codes are stable and never renamed.
- **Actor FKs:** every table's `created_by`/`updated_by` → `admin.app_user` (N:1, mandatory, RESTRICT). These are added to every table by `ddl/99_finalise.sql` and are not repeated below.
- **Soft-deleted parents** (candidate_profile, job_requirement, organisation, app_user, application, resume_version) are never physically deleted in normal operation. The CASCADE rules below therefore only fire in the retention purge (M22), where removing owned children with the parent is the intent.

## Stubs and master data

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| app_user.user_status_code | ref.user_status | N:1 | no | RESTRICT | Every account has a status |
| organisation.organisation_status_code | ref.organisation_status | N:1 | no | RESTRICT | Every organisation has a status |
| state.country_id | ref.country | N:1 | no | RESTRICT | A subdivision belongs to one country |
| city.country_id | ref.country | N:1 | no | RESTRICT | Kept even when a state exists, so cities in countries without states (Singapore) are valid |
| city.state_id | ref.state | N:1 | yes | RESTRICT | NULL: the country has no first-level subdivision. Composite FK (country_id, state_id) → state (country_id, id) stops a city pointing at another country's state |
| city.timezone_id | ref.timezone | N:1 | yes | RESTRICT | NULL: zone not mapped yet; display falls back to the country default |
| skill_category.parent_skill_category_id | ref.skill_category | N:1 | yes | RESTRICT | NULL: top-level category |
| skill.skill_category_id | ref.skill_category | N:1 | no | RESTRICT | Every skill is classified |
| qualification.qualification_level_code | ref.qualification_level | N:1 | no | RESTRICT | Level drives search filters and eligibility |
| institution.country_id | ref.country | N:1 | no | RESTRICT | Institution location |
| institution.city_id | ref.city | N:1 | yes | RESTRICT | NULL: open or distance university without a campus city |
| industry.parent_industry_id | ref.industry | N:1 | yes | RESTRICT | NULL: top-level industry |
| job_role.job_function_id | ref.job_function | N:1 | no | RESTRICT | A role belongs to one function |
| identifier_type.country_id | ref.country | N:1 | yes | RESTRICT | NULL: identifier is not country-specific (passport) |
| (each lookup).label_key | ref.ui_label | N:1 | no | RESTRICT | Display text per language (built by `ref.create_lookup`) |

## Profile

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| candidate_profile.app_user_id | admin.app_user | 1:1 | no | RESTRICT | One candidate profile per login identity; user removal is soft and goes through anonymisation |
| candidate_profile.gender_code | ref.gender | N:1 | yes | RESTRICT | NULL: never asked or not yet entered; an explicit refusal is the code prefer_not_to_say |
| candidate_profile.nationality_country_id | ref.country | N:1 | yes | RESTRICT | NULL: not provided |
| candidate_profile.current_city_id | ref.city | N:1 | yes | RESTRICT | NULL: not provided |
| candidate_profile.notice_period_code | ref.notice_period | N:1 | yes | RESTRICT | NULL: not currently employed (not applicable) |
| candidate_profile.current_salary_disclosure_code | ref.disclosure | N:1 | no | RESTRICT | Unknown vs not applicable for current salary (RG5) |
| candidate_profile.expected_salary_disclosure_code | ref.disclosure | N:1 | no | RESTRICT | Same for expected salary |
| candidate_profile.salary_currency_code | ref.currency | N:1 | yes | RESTRICT | NULL only when neither salary is disclosed (CHECK) |
| candidate_profile.salary_pay_period_code | ref.pay_period | N:1 | yes | RESTRICT | NULL only when neither salary is disclosed (CHECK) |
| candidate_profile.summary_language_id | ref.language | N:1 | yes | RESTRICT | NULL: language of the summary not detected (RG7) |
| candidate_contact.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child: contact points die with the profile on purge |
| candidate_contact.contact_type_code | ref.contact_type | N:1 | no | RESTRICT | Selects which value column (email or phone) is filled (CHECK) |
| candidate_contact.phone_country_id | ref.country | N:1 | yes | RESTRICT | NULL: contact is an email (RG3 phone has a separate country field) |
| candidate_address.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child |
| candidate_address.address_type_code | ref.address_type | N:1 | no | RESTRICT | Type of address |
| candidate_address.city_id | ref.city | N:1 | no | RESTRICT | Address city (implies state and country) |
| candidate_identity_document.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child; Sensitive data must go with the profile on purge |
| candidate_identity_document.identifier_type_code | ref.identifier_type | N:1 | no | RESTRICT | Which national identifier the token represents |
| candidate_identity_document.verification_status_code | ref.verification_status | N:1 | no | RESTRICT | Outcome from the verification service |
| candidate_language.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned junction row |
| candidate_language.language_id | ref.language | N:1 | no | RESTRICT | Master data must not vanish under profiles |
| candidate_language.proficiency_level_code | ref.proficiency_level | N:1 | no | RESTRICT | Level of the language |
| candidate_education.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child |
| candidate_education.qualification_id | ref.qualification | N:1 | no | RESTRICT | What was studied |
| candidate_education.field_of_study_id | ref.field_of_study | N:1 | yes | RESTRICT | NULL: qualification has no specialisation (secondary school) |
| candidate_education.institution_id | ref.institution | N:1 | yes | RESTRICT | NULL: institution not in the master list; the free-text institution_name is used instead (CHECK: one of the two) |
| candidate_education.study_mode_code | ref.study_mode | N:1 | yes | RESTRICT | NULL: not provided |
| candidate_work_experience.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child |
| candidate_work_experience.organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: employer not registered on the platform; employer_name text is used instead (CHECK: one of the two) |
| candidate_work_experience.job_role_id | ref.job_role | N:1 | yes | RESTRICT | NULL: role not mapped to the master list; the designation text is kept |
| candidate_work_experience.industry_id | ref.industry | N:1 | yes | RESTRICT | NULL: not provided |
| candidate_work_experience.employment_type_code | ref.employment_type | N:1 | no | RESTRICT | Permanent, contract, internship ... |
| candidate_work_experience.city_id | ref.city | N:1 | yes | RESTRICT | NULL: remote role or not provided |
| candidate_skill.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned junction row |
| candidate_skill.skill_id | ref.skill | N:1 | no | RESTRICT | Master data |
| candidate_skill.proficiency_level_code | ref.proficiency_level | N:1 | yes | RESTRICT | NULL: candidate did not self-rate |
| candidate_certification.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child |
| candidate_certification.skill_id | ref.skill | N:1 | yes | RESTRICT | NULL: certification not tied to one skill |
| candidate_project.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child |
| candidate_project.project_kind_code | ref.project_kind | N:1 | no | RESTRICT | employment, academic, personal, gig |
| candidate_project.candidate_work_experience_id | profile.candidate_work_experience | N:1 | yes | SET NULL | NULL: project not done in a listed job. SET NULL keeps the project if the job entry is removed |
| candidate_preferred_location.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned junction row |
| candidate_preferred_location.city_id | ref.city | N:1 | no | RESTRICT | Master data |
| candidate_preferred_role.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned junction row |
| candidate_preferred_role.job_role_id | ref.job_role | N:1 | no | RESTRICT | Master data |
| candidate_web_link.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child |
| candidate_web_link.web_link_type_code | ref.web_link_type | N:1 | no | RESTRICT | Link type |
| resume_template.language_id | ref.language | N:1 | no | RESTRICT | Language the template's fixed headings are in |
| resume_version.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child (soft-deleted itself; physical delete only in the purge) |
| resume_version.resume_template_id | profile.resume_template | N:1 | yes | RESTRICT | NULL: uploaded file, not built from a template |
| resume_version.body_language_id | ref.language | N:1 | yes | RESTRICT | NULL: language not detected (RG7) |
| assessment.assessment_type_code | ref.assessment_type | N:1 | no | RESTRICT | Kind of assessment |
| assessment.skill_id | ref.skill | N:1 | yes | RESTRICT | NULL: general aptitude, not skill-specific |
| assessment_attempt.assessment_id | profile.assessment | N:1 | no | RESTRICT | Attempts are append-only history |
| assessment_attempt.candidate_profile_id | profile.candidate_profile | N:1 | no | RESTRICT | Append-only history; purge anonymises instead of deleting |
| course.skill_id | ref.skill | N:1 | yes | RESTRICT | NULL: course spans several skills |
| course_enrolment.course_id | profile.course | N:1 | no | RESTRICT | Catalogue entry |
| course_enrolment.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned by the candidate |
| course_enrolment.enrolment_status_code | ref.enrolment_status | N:1 | no | RESTRICT | Enrolment state |
| profile_completion_score.candidate_profile_id | profile.candidate_profile | 1:1 | no | CASCADE | Derived row owned by the profile |
| profile_view_event.candidate_profile_id | profile.candidate_profile | N:1 | no | RESTRICT | Append-only history (RG10); purge anonymises |
| profile_view_event.viewer_app_user_id | admin.app_user | N:1 | no | RESTRICT | Who viewed (actor) |
| profile_view_event.viewer_organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: viewer is an independent consultant with no organisation |
| candidate_activity_event.candidate_profile_id | profile.candidate_profile | N:1 | no | RESTRICT | Append-only activity log |
| candidate_activity_event.activity_event_type_code | ref.activity_event_type | N:1 | no | RESTRICT | Event type |
| candidate_bookmark_event.candidate_profile_id | profile.candidate_profile | N:1 | no | RESTRICT | Append-only bookmark history |
| candidate_bookmark_event.actor_app_user_id | admin.app_user | N:1 | no | RESTRICT | Recruiter or employer user who bookmarked |
| candidate_bookmark_event.actor_organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: independent consultant |
| candidate_bookmark_event.job_requirement_id | job.job_requirement | N:1 | yes | RESTRICT | NULL: general talent-pool bookmark, not for a specific job |
| candidate_bookmark_event.bookmark_action_code | ref.bookmark_action | N:1 | no | RESTRICT | added or removed |
| referral.referrer_app_user_id | admin.app_user | N:1 | no | RESTRICT | Who referred |
| referral.referred_candidate_profile_id | profile.candidate_profile | N:1 | yes | RESTRICT | NULL: invitee has not registered yet; referred_email is set (CHECK: one of the two) |
| referral.job_requirement_id | job.job_requirement | N:1 | yes | RESTRICT | NULL: platform referral, not for a specific job |
| referral.referral_status_code | ref.referral_status | N:1 | no | RESTRICT | Progress of the referral |

## Jobs and Applications

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| job_requirement.organisation_id | org.organisation | N:1 | no | RESTRICT | Owning employer or agency; RLS keys on it (M18) |
| job_requirement.client_organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: direct employer hiring for itself; set when an agency posts for a client |
| job_requirement.posted_by_app_user_id | admin.app_user | N:1 | no | RESTRICT | Recruiter accountable for the posting |
| job_requirement.job_category_code | ref.job_category | N:1 | no | RESTRICT | Staffing, permanent, apprentice, campus ... (gig is a separate subsystem) |
| job_requirement.employment_type_code | ref.employment_type | N:1 | no | RESTRICT | Contract, permanent ... |
| job_requirement.work_type_code | ref.work_type | N:1 | no | RESTRICT | Onsite, remote, hybrid |
| job_requirement.job_role_id | ref.job_role | N:1 | no | RESTRICT | Standard role, used for search and analytics |
| job_requirement.industry_id | ref.industry | N:1 | yes | RESTRICT | NULL: inherits the organisation's industry |
| job_requirement.job_requirement_status_code | ref.job_requirement_status | N:1 | no | RESTRICT | Lifecycle |
| job_requirement.publish_state_code | ref.publish_state | N:1 | no | RESTRICT | Visibility |
| job_requirement.salary_disclosure_code | ref.disclosure | N:1 | no | RESTRICT | Unknown vs not applicable salary (RG5) |
| job_requirement.currency_code | ref.currency | N:1 | yes | RESTRICT | NULL only when salary is not disclosed (CHECK) |
| job_requirement.pay_period_code | ref.pay_period | N:1 | yes | RESTRICT | NULL only when salary is not disclosed (CHECK) |
| job_requirement.notice_period_code | ref.notice_period | N:1 | yes | RESTRICT | NULL: no notice-period requirement |
| job_requirement.description_language_id | ref.language | N:1 | yes | RESTRICT | NULL: language not detected (RG7) |
| job_position.job_requirement_id | job.job_requirement | N:1 | no | CASCADE | Owned child: openings exist only within the requirement |
| job_position.filled_by_application_id | job.application | 1:1 | yes | RESTRICT | NULL: opening not yet filled; unique, so one hire fills one opening |
| job_requirement_location.job_requirement_id | job.job_requirement | N:1 | no | CASCADE | Owned junction row |
| job_requirement_location.city_id | ref.city | N:1 | no | RESTRICT | Master data |
| job_requirement_skill.job_requirement_id | job.job_requirement | N:1 | no | CASCADE | Owned junction row |
| job_requirement_skill.skill_id | ref.skill | N:1 | no | RESTRICT | Master data |
| job_requirement_skill.min_proficiency_level_code | ref.proficiency_level | N:1 | yes | RESTRICT | NULL: any proficiency accepted |
| job_requirement_qualification.job_requirement_id | job.job_requirement | N:1 | no | CASCADE | Owned junction row |
| job_requirement_qualification.qualification_id | ref.qualification | N:1 | no | RESTRICT | Master data |
| job_requirement_qualification.field_of_study_id | ref.field_of_study | N:1 | yes | RESTRICT | NULL: any field accepted |
| questionnaire.organisation_id | org.organisation | N:1 | no | RESTRICT | Questionnaires are reusable across the organisation's jobs |
| questionnaire_question.questionnaire_id | job.questionnaire | N:1 | no | CASCADE | Owned child |
| questionnaire_question.question_type_code | ref.question_type | N:1 | no | RESTRICT | Answer format |
| question_option.questionnaire_question_id | job.questionnaire_question | N:1 | no | CASCADE | Owned child |
| job_requirement_questionnaire.job_requirement_id | job.job_requirement | N:1 | no | CASCADE | Owned junction row |
| job_requirement_questionnaire.questionnaire_id | job.questionnaire | N:1 | no | RESTRICT | A questionnaire in use cannot be deleted |
| application.job_requirement_id | job.job_requirement | N:1 | no | RESTRICT | A job with applications cannot be deleted (M6 test 9) |
| application.candidate_profile_id | profile.candidate_profile | N:1 | no | RESTRICT | Pipeline history must survive; purge anonymises |
| application.application_status_code | ref.application_status | N:1 | no | RESTRICT | No free-text status (M6 test 7) |
| application.application_source_code | ref.application_source | N:1 | no | RESTRICT | Direct, sourced, referral, campus, consultant |
| application.rejection_reason_code | ref.rejection_reason | N:1 | yes | RESTRICT | NULL: not rejected (CHECK: set if and only if status is rejected) |
| application.resume_version_id | profile.resume_version | N:1 | yes | RESTRICT | NULL: applied with the profile only, no resume attached |
| application.referral_id | profile.referral | N:1 | yes | RESTRICT | NULL: not a referral application |
| application_answer.application_id | job.application | N:1 | no | CASCADE | Owned child |
| application_answer.questionnaire_question_id | job.questionnaire_question | N:1 | no | RESTRICT | Question answered |
| application_answer.question_option_id | job.question_option | N:1 | yes | RESTRICT | NULL: free-text or numeric answer |
| application_status_history.application_id | job.application | N:1 | no | RESTRICT | Append-only history |
| application_status_history.from_application_status_code | ref.application_status | N:1 | yes | RESTRICT | NULL: first entry (applied) has no previous status |
| application_status_history.to_application_status_code | ref.application_status | N:1 | no | RESTRICT | New status |
| application_status_transition.from_application_status_code | ref.application_status | N:1 | no | RESTRICT | Legal move source |
| application_status_transition.to_application_status_code | ref.application_status | N:1 | no | RESTRICT | Legal move target |
| shortlist.organisation_id | org.organisation | N:1 | no | RESTRICT | Owning organisation |
| shortlist.owner_app_user_id | admin.app_user | N:1 | no | RESTRICT | Recruiter who maintains it |
| shortlist.job_requirement_id | job.job_requirement | N:1 | yes | RESTRICT | NULL: talent-pool shortlist, not tied to a job |
| shortlist_entry.shortlist_id | job.shortlist | N:1 | no | CASCADE | Owned child |
| shortlist_entry.candidate_profile_id | profile.candidate_profile | N:1 | no | RESTRICT | Candidate on the list |
| interview.application_id | job.application | N:1 | no | RESTRICT | Pipeline history must survive |
| interview.interview_mode_code | ref.interview_mode | N:1 | no | RESTRICT | Mode |
| interview.interview_status_code | ref.interview_status | N:1 | no | RESTRICT | Scheduling state |
| interview.interview_outcome_code | ref.interview_outcome | N:1 | yes | RESTRICT | NULL: not yet held (CHECK: set only when completed) |
| interview.interviewer_app_user_id | admin.app_user | N:1 | yes | RESTRICT | NULL: panel not assigned yet |
| offer.application_id | job.application | N:1 | no | RESTRICT | Offer history kept (a revised offer is a new row) |
| offer.offer_status_code | ref.offer_status | N:1 | no | RESTRICT | State |
| offer.ctc_currency_code | ref.currency | N:1 | no | RESTRICT | Money companion |
| offer.ctc_pay_period_code | ref.pay_period | N:1 | no | RESTRICT | Period the CTC is quoted in |
| joining.application_id | job.application | 1:1 | no | RESTRICT | One joining per application |
| joining.offer_id | job.offer | 1:1 | no | RESTRICT | Joining against the accepted offer |
| joining.joining_status_code | ref.joining_status | N:1 | no | RESTRICT | Expected, joined, no_show, deferred |
| saved_search.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned by the candidate |
| job_search_event.candidate_profile_id | profile.candidate_profile | N:1 | yes | RESTRICT | NULL: guest search (Guest actor); session_token identifies it |

## Many-to-many: every one has a junction table

| Relationship | Junction |
|---|---|
| candidate ↔ skill | candidate_skill |
| candidate ↔ language | candidate_language |
| candidate ↔ preferred city | candidate_preferred_location |
| candidate ↔ preferred role | candidate_preferred_role |
| job requirement ↔ skill | job_requirement_skill |
| job requirement ↔ qualification | job_requirement_qualification |
| job requirement ↔ city | job_requirement_location |
| job requirement ↔ questionnaire | job_requirement_questionnaire |
| candidate ↔ job requirement | application (carries its own data, so it is an entity) |
| candidate ↔ shortlist | shortlist_entry |
| candidate ↔ course | course_enrolment |

## Validation checklist (B9, B11: reviewer C ticks)
- [ ] Every many-to-many has a junction table (above).
- [ ] RESTRICT by default. Every CASCADE is an owned child and says why. The only SET NULL is candidate_project.candidate_work_experience_id.
- [ ] Every optional relationship has a reason.
- [ ] No relationship leaves Phase 1 except to the stubs (admin.app_user, org.organisation).
- [ ] `docs/erd/phase1.mmd` matches this table.
