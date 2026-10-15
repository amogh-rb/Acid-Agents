# Data-quality issues deliberately present in the seed (M19, docket Section 6)

The generator reproduces the kind of messiness the legacy systems hold, so validation and the performance queries run on
realistic data. All of it is valid under the schema constraints; nothing here is a rule violation.

| # | Issue | Rate | How it is represented | Why it matters |
|---|---|---|---|---|
| 1 | Near-duplicate candidates | 3.5% of profiles (about 2.5% detectable by a shared phone) | Same phone number, Latin transliteration of a native-script name, different login email | De-duplication and search quality; `uq_candidate_contact_email` does not catch them |
| 2 | Multilingual names | 60% non-English (Hindi, Tamil, Arabic, Chinese) | Native script in `full_name`, family-name-first for Chinese | UTF-8 end to end, collation, trigram search |
| 3 | Unknown vs not applicable salary | 65% of current salaries undisclosed; freshers `not_applicable` | `*_disclosure_code` + NULL amounts, never 0 | RG5 |
| 4 | Missing optional data | DOB 30%, gender 15%, summary 40%, phone 20%, resume 30% | NULLs with a documented reason per column | Completeness scoring |
| 5 | Legacy imports | 10% of profiles, 5% of jobs, 5% of applications | `legacy_source_*` pair, application source `imported` | Sync direction and conflict rule |
| 6 | Heavily skewed demand | A few jobs receive a large share of applications | Zipf-like job choice | Hot partitions, index selectivity, `application` hashing on candidate |
| 7 | Shared employer text | 70% of work experience uses free-text employer names | `employer_name` instead of an organisation id | Matching to registered organisations |
| 8 | Stale and closed jobs | 40% of jobs not open | closed / filled / cancelled / on hold | Search surface is the partial index on open published jobs |
| 9 | Unverified contacts | 30-50% unverified | `is_verified` false, no `verified_at` | Contact trust |
| 10 | Overlapping gig bookings | Explicit attempts (sampled from active assignments) | Rejected by `ex_gig_assignment_worker_window`; counted in `seed.gig_overlap_attempt` | B35 proof on realistic data |

## Known synthetic shortcuts
- Password hashes are structurally valid PHC strings and not real credentials.
- Identifiers, phone numbers and emails are synthetic (`@mail.example`, reserved ranges); GSTIN-like values are valid in format only.
- Names come from 16 given and 16 family names per locale, so exact name collisions are common by design.
- Application history timestamps are evenly spaced (3 days per stage); real data is burstier.
- Candidates have no licence seat: device limits apply to licensed employer-side users (see `docs/00_decisions.md` D23).
