# 04 Environment (M1 verified; settings applied in M19; M21 performance evidence)

Recorded on 2026-10-15 from `.\run.ps1 settings` on the build laptop.

## Hardware
| Item | Value |
|---|---|
| CPU | 12th Gen Intel Core i7-1255U, 12 logical processors (docket minimum: 8 cores) |
| RAM | 31.6 GB (docket: 16 GB minimum, 32 GB recommended) |
| Disk C: | 236.8 GB, **19.9 GB free**. Holds the PostgreSQL install and the default data directory |
| Disk D: | 237.9 GB, **170.6 GB free**. Used for the seeded data (see below) |
| OS | Windows 11 Pro 10.0.22631 |

The docket asks for 512 GB of free SSD. We have 190 GB in total, so the laptop-scale seed (1M profiles, 100K jobs, 5M applications) goes on D:.
- **Done in M19 (D32):** `pg_wal` was also moved to `D:	alentra_pg_wal` (a junction in the data directory). Originally planned: create the directory `D:\talentra_pg` and give the PostgreSQL service account (`NETWORK SERVICE`) write access to it. Then run `CREATE TABLESPACE talentra_data LOCATION 'D:/talentra_pg'` and put the big tables and indexes there (`SET default_tablespace` during the load).
- **Recorded here as a deviation from the docket sizing.**

## Server
Applied on 2026-10-15 (M19, `ALTER SYSTEM` + service restart). The M21 measurements ran with the **Applied** column; evidence: `docs/evidence/settings_m21_20261016.txt`.

| Setting | Before (M1) | Source | Applied (M19-M21) |
|---|---|---|---|
| server_version | 18.4 (x86_64-windows, msvc) | - | - |
| server_encoding / database | UTF8; database `talentra` uses ICU locale `und` | - | - |
| shared_buffers | 128 MB | config file | 4 GB (about 1/8 of RAM on Windows) |
| work_mem | 4 MB | default | 32 MB |
| maintenance_work_mem | 64 MB | default | 1 GB (index builds after the COPY load) |
| effective_cache_size | 4 GB | default | 16 GB |
| max_wal_size | 1 GB | config file | 8 GB during the seed load |
| random_page_cost | 4 | default | 1.1 (SSD) |
| io_method | worker | default (PG18 async I/O) | keep |
| shared_preload_libraries | (empty) | default | `pg_stat_statements` (`ddl/00` then creates the extension automatically) |
| track_io_timing | off | default | on (`EXPLAIN (ANALYZE, BUFFERS)` I/O timings) |
| jit | on | default | left **on** (default). No query in the set is expensive enough to trigger JIT (cost thresholds 100K/500K), so it did not affect the measurements |
| max_connections | 100 | config file | keep |

Measurements in M21 state which settings were active; rerun `.\run.ps1 settings` and paste the output into `docs/evidence/`.

## Tooling
- PostgreSQL client tools: `C:\Program Files\PostgreSQL\18\bin` (`PGBIN` in `.env`).
- Python 3.11.4 (data generator, `tools/reserved_words.py`).
- PowerShell 5.1 runs `run.ps1`. Keep `run.ps1` ASCII-only, because PS 5.1 reads BOM-less files as ANSI.
