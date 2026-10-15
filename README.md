# Talentra Database Design — ACID Agents

Operational and analytical database design for Talentra, a job search and demand management platform (PostgreSQL 18).

## Quick start
1. Install PostgreSQL 18 and copy `.env.example` to `.env` with your password.
2. `.\run.ps1 test` rebuilds the database from `ddl/` and runs every milestone gate.

See `CLAUDE.md` for conventions and workflow, `docs/milestones.md` for status, and `docs/00_decisions.md` for design decisions.
