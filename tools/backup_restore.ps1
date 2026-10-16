<#
.SYNOPSIS
  M23 (B80): timed backup and restore drill of the seeded database.
    1. pg_dump -Fd -j N  (directory format, parallel, compressed) to D:\talentra_backup\<db>_<timestamp>
    2. pg_restore -j N into a fresh database <db>_restore (tablespace talentra_data)
    3. exact row counts of every table compared between source and restore; ANALYZE
  Times are logged against the assumed RTO and written to docs/evidence/backup_restore_<timestamp>.txt.

.EXAMPLE
  .\tools\backup_restore.ps1 -Database talentra_seed -Jobs 6 -RtoMinutes 60
#>
param(
  [string]$Database = 'talentra_seed',
  [int]$Jobs = 6,
  [int]$RtoMinutes = 60,
  [string]$BackupRoot = 'D:\talentra_backup',
  [switch]$KeepRestore
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (Test-Path '.env') {
  foreach ($line in Get-Content '.env') {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { Set-Item -Path ("env:" + $Matches[1]) -Value $Matches[2].Trim('"', "'") }
  }
}
$bin = $env:PGBIN
$psql = Join-Path $bin 'psql.exe'
$env:PGCLIENTENCODING = 'UTF8'
$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
$dir = Join-Path $BackupRoot ("{0}_{1}" -f $Database, $stamp)
$target = "${Database}_restore"
$log = New-Object System.Collections.Generic.List[string]
function Say([string]$t) { Write-Host $t; $log.Add($t) }
function Run([string]$exe, [string[]]$a) {
  $ErrorActionPreference = 'Continue'
  $o = & $exe @a 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($code -ne 0) { throw "$exe failed ($code): $o" }
  return $o
}
function Counts([string]$db) {
  $sql = @'
SELECT format('SELECT %L AS t, count(*) AS n FROM %s', n.nspname || '.' || c.relname, c.oid::regclass)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition
   AND n.nspname IN ('ref','admin','org','profile','job','gig','lic','src','billing','notif','audit','dw')
 ORDER BY 1
'@
  $stmts = (& $psql -X -q -t -A -d $db -c $sql) | Where-Object { $_ }
  $union = ($stmts -join "`nUNION ALL ") + ";"
  $tmp = Join-Path $env:TEMP "talentra_counts_$db.sql"
  [IO.File]::WriteAllText($tmp, $union, (New-Object Text.UTF8Encoding($false)))
  $res = @{}
  foreach ($l in (& $psql -X -q -t -A -F '|' -d $db -f $tmp)) { if ($l -match '^(.+)\|(\d+)$') { $res[$Matches[1]] = [long]$Matches[2] } }
  return $res
}

Say "== backup/restore drill: $Database -> $dir -> $target (jobs $Jobs, assumed RTO $RtoMinutes min) =="
$size = (& $psql -X -q -t -A -d $Database -c "SELECT pg_size_pretty(pg_database_size(current_database()))").Trim()
Say "source size: $size"
New-Item -ItemType Directory -Force $BackupRoot | Out-Null

$t0 = Get-Date
Run (Join-Path $bin 'pg_dump.exe') @('-Fd', '-j', "$Jobs", '-Z', '1', '-f', $dir, '-d', $Database) | Out-Null
$dump = (Get-Date) - $t0
$bytes = (Get-ChildItem $dir -Recurse -File | Measure-Object Length -Sum).Sum
Say ("backup   pg_dump -Fd -j {0}: {1:N1} min, {2:N2} GB on disk" -f $Jobs, $dump.TotalMinutes, ($bytes / 1GB))

Run $psql @('-X', '-q', '-d', 'postgres', '-c', "DROP DATABASE IF EXISTS $target WITH (FORCE)") | Out-Null
Run $psql @('-X', '-q', '-d', 'postgres', '-c', "CREATE DATABASE $target TEMPLATE template0 ENCODING 'UTF8' LOCALE_PROVIDER icu ICU_LOCALE 'und' LOCALE 'C' TABLESPACE talentra_data") | Out-Null
$t1 = Get-Date
Run (Join-Path $bin 'pg_restore.exe') @('-j', "$Jobs", '-d', $target, '--exit-on-error', $dir) | Out-Null
$restore = (Get-Date) - $t1
Say ("restore  pg_restore -j {0}: {1:N1} min" -f $Jobs, $restore.TotalMinutes)
$t2 = Get-Date
Run $psql @('-X', '-q', '-d', $target, '-c', 'ANALYZE') | Out-Null
$analyze = (Get-Date) - $t2
Say ("analyze  {0:N1} min" -f $analyze.TotalMinutes)

$src = Counts $Database
$dst = Counts $target
$diff = @($src.Keys | Where-Object { $src[$_] -ne $dst[$_] })
$total = ($src.Values | Measure-Object -Sum).Sum
Say ("verify   {0} tables, {1:N0} rows; mismatches: {2}" -f $src.Count, $total, $diff.Count)
foreach ($k in $diff) { Say ("  MISMATCH {0}: source {1}, restore {2}" -f $k, $src[$k], $dst[$k]) }
foreach ($k in 'profile.candidate_profile', 'job.job_requirement', 'job.application', 'job.application_status_history', 'billing.wallet_ledger_entry', 'audit.audit_event') {
  Say ("  {0,-34} source {1,12:N0}  restore {2,12:N0}" -f $k, $src[$k], $dst[$k])
}
$invalid = (& $psql -X -q -t -A -d $target -c "SELECT count(*) FROM pg_index WHERE NOT indisvalid").Trim()
$policies = (& $psql -X -q -t -A -d $target -c "SELECT count(*) FROM pg_policies").Trim()
$srcPolicies = (& $psql -X -q -t -A -d $Database -c "SELECT count(*) FROM pg_policies").Trim()
Say "objects  invalid indexes: $invalid; RLS policies: $policies (source $srcPolicies)"

$rto = $restore + $analyze
$ok = ($diff.Count -eq 0 -and $invalid -eq '0' -and $policies -eq $srcPolicies)
Say ("RESULT   restore + analyze = {0:N1} min vs assumed RTO {1} min: {2}; data check: {3}" -f $rto.TotalMinutes, $RtoMinutes,
     $(if ($rto.TotalMinutes -le $RtoMinutes) { 'WITHIN RTO' } else { 'EXCEEDS RTO' }), $(if ($ok) { 'PASS' } else { 'FAIL' }))
if (-not $KeepRestore) {
  Run $psql @('-X', '-q', '-d', 'postgres', '-c', "DROP DATABASE IF EXISTS $target WITH (FORCE)") | Out-Null
  Say "cleanup  dropped $target (backup kept at $dir)"
}
$ev = "docs/evidence/backup_restore_$stamp.txt"
[IO.File]::WriteAllLines((Join-Path (Get-Location) $ev), $log, (New-Object Text.UTF8Encoding($false)))
Write-Host "evidence: $ev"
if (-not $ok) { exit 1 }
