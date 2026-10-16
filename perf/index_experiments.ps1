<#
.SYNOPSIS
  M21 (B71-B73): one index per module, justified by a before-and-after measurement on the seeded database.
  For each experiment the index is dropped (BEFORE), the query is measured, the index is recreated from its saved
  definition (AFTER), and the query is measured again. Server-side execution time over N runs; p50 and p95 are reported.
  The database is left exactly as it was found (every dropped index is recreated, even if a step fails).

.EXAMPLE
  .\perf\index_experiments.ps1 -Database talentra_seed -Runs 20
#>
param(
  [string]$Database = 'talentra_seed',
  [int]$Runs = 20,
  [string]$Label = 'index_experiments'
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (Test-Path '.env') {
  foreach ($line in Get-Content '.env') {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { Set-Item -Path ("env:" + $Matches[1]) -Value $Matches[2].Trim('"', "'") }
  }
}
$psql = Join-Path $env:PGBIN 'psql.exe'
$env:PGCLIENTENCODING = 'UTF8'
New-Item -ItemType Directory -Force 'perf/results', 'perf/plans' | Out-Null

function Invoke-Sql([string]$sql) {
  $ErrorActionPreference = 'Continue'
  $out = & $psql -X -q -t -A -d $Database -v ON_ERROR_STOP=1 -c $sql 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "psql failed: $sql`n$out" }
  return $out.Trim()
}
function Get-Percentile([double[]]$values, [double]$p) {
  $s = $values | Sort-Object
  return $s[[math]::Max(0, [math]::Min($s.Count - 1, [math]::Ceiling($p / 100.0 * $s.Count) - 1))]
}
function Measure-Query([string]$setup, [string]$query, [string]$planFile) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('\set ON_ERROR_STOP on'); [void]$sb.AppendLine($setup)
  [void]$sb.AppendLine('\pset format unaligned'); [void]$sb.AppendLine('\pset tuples_only on')
  for ($i = 1; $i -le ($Runs + 2); $i++) { [void]$sb.AppendLine("\echo @@RUN $i"); [void]$sb.AppendLine("EXPLAIN (ANALYZE, BUFFERS, TIMING OFF) $query;") }
  $tmp = Join-Path $env:TEMP 'talentra_idx_exp.sql'
  [System.IO.File]::WriteAllText($tmp, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
  $ErrorActionPreference = 'Continue'
  $out = & $psql -X -q -d $Database -f $tmp 2>&1 | Out-String
  if ($out -match 'ERROR:') { throw ("query failed: " + (($out -split "`r?`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -First 1))) }
  $blocks = $out -split '(?m)^@@RUN \d+\s*$' | Select-Object -Skip 1
  $times = @(); $n = 0
  foreach ($b in $blocks) {
    $n++
    if ($b -match 'Execution Time:\s*([0-9.]+) ms') { if ($n -gt 2) { $times += [double]$Matches[1] } }
    if ($n -eq 3 -and $planFile) { $b.Trim() | Set-Content -Path $planFile -Encoding UTF8 }
  }
  return $times
}

# Experiments: module, index, the query that justifies it. Parameters are looked up from the data, so every query finds rows.
$experiments = @(
  @{ module = 'Administration'; index = 'audit.idx_audit_event_actor_app_user_id'
     setup = "SELECT actor_app_user_id AS actor FROM audit.audit_event WHERE actor_app_user_id IS NOT NULL GROUP BY 1 ORDER BY count(*) DESC LIMIT 1 \gset"
     query = "SELECT id, audit_action_code, occurred_at FROM audit.audit_event WHERE actor_app_user_id = :actor ORDER BY occurred_at DESC LIMIT 20" },
  @{ module = 'Organisation and account'; index = 'org.idx_recruiter_mapping_organisation_id'
     setup = "SELECT organisation_id AS org FROM org.recruiter_mapping ORDER BY organisation_id DESC LIMIT 1 \gset"
     query = "SELECT app_user_id FROM org.recruiter_mapping WHERE organisation_id = :org AND valid_period @> current_date" },
  @{ module = 'Gig marketplace'; index = 'gig.idx_gig_request_open'
     setup = "SELECT skill_id AS skill FROM gig.gig_request WHERE gig_request_status_code = 'open' AND deleted_at IS NULL GROUP BY 1 ORDER BY count(*) DESC LIMIT 1 \gset"
     query = "SELECT id, gig_title, window_start FROM gig.gig_request WHERE gig_request_status_code = 'open' AND deleted_at IS NULL AND skill_id = :skill ORDER BY window_start LIMIT 20" },
  @{ module = 'Licences, devices and sessions'; index = 'lic.idx_login_session_active_user'
     setup = "SELECT app_user_id AS u FROM lic.login_session WHERE ended_at IS NULL ORDER BY id LIMIT 1 \gset"
     query = "SELECT count(*) FROM lic.login_session WHERE app_user_id = :u AND ended_at IS NULL AND expires_at > now()" },
  @{ module = 'Sourcing and consultant requests'; index = 'src.idx_outreach_recipient_candidate_profile_id'
     setup = "SELECT candidate_profile_id AS cand FROM src.outreach_recipient GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1 \gset"
     query = "SELECT r.outreach_batch_id, r.outreach_recipient_status_code FROM src.outreach_recipient r WHERE r.candidate_profile_id = :cand" },
  @{ module = 'Subscriptions, wallet and downloads'; index = 'billing.idx_wallet_ledger_entry_wallet_id'
     setup = "SELECT wallet_id AS w FROM billing.wallet_ledger_entry ORDER BY wallet_id DESC LIMIT 1 \gset"
     query = "SELECT id, ledger_entry_type_code, amount, balance_after FROM billing.wallet_ledger_entry WHERE wallet_id = :w ORDER BY posted_at DESC LIMIT 20" },
  @{ module = 'Notifications'; index = 'notif.idx_notification_unread'
     setup = "SELECT recipient_app_user_id AS u FROM notif.notification WHERE read_at IS NULL GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1 \gset"
     query = "SELECT count(*) FROM notif.notification WHERE recipient_app_user_id = :u AND read_at IS NULL" },
  @{ module = 'Analytics'; index = 'dw.idx_fact_application_applied_dim_date_id'
     setup = "SELECT max(applied_dim_date_id) - 30 AS d FROM dw.fact_application \gset"
     query = "SELECT job_category, count(*), count(*) FILTER (WHERE is_joined) FROM dw.fact_application WHERE applied_dim_date_id >= :d GROUP BY 1" }
)

$rows = @()
foreach ($e in $experiments) {
  $parts = $e.index -split '\.'
  $schema = $parts[0]; $idx = $parts[1]
  $def = Invoke-Sql "SELECT pg_get_indexdef(c.oid) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = '$schema' AND c.relname = '$idx'"
  if (-not $def) { Write-Host "SKIP  $($e.index): index not found" -ForegroundColor Yellow; continue }
  $size = Invoke-Sql "SELECT pg_size_pretty(pg_relation_size('$($e.index)'))"
  $dropped = $false
  try {
    Invoke-Sql "DROP INDEX $($e.index)" | Out-Null; $dropped = $true
    $before = Measure-Query $e.setup $e.query ("perf/plans/{0}_before.txt" -f $idx)
    $t0 = Get-Date
    Invoke-Sql $def | Out-Null; $dropped = $false
    $build = ((Get-Date) - $t0).TotalSeconds
    Invoke-Sql "ANALYZE $schema.$($def -replace '^.*? ON (\S+) .*$', '$1' -replace '^\S+\.', '')" 2>$null | Out-Null
    $after = Measure-Query $e.setup $e.query ("perf/plans/{0}_after.txt" -f $idx)
  } finally {
    if ($dropped) { Invoke-Sql $def | Out-Null }
  }
  $b50 = Get-Percentile $before 50; $a50 = Get-Percentile $after 50
  $rows += [pscustomobject]@{
    module = $e.module; index = $e.index; index_size = $size; build_seconds = [math]::Round($build, 1)
    before_p50_ms = [math]::Round($b50, 3); before_p95_ms = [math]::Round((Get-Percentile $before 95), 3)
    after_p50_ms = [math]::Round($a50, 3); after_p95_ms = [math]::Round((Get-Percentile $after 95), 3)
    speedup = if ($a50 -gt 0) { [math]::Round($b50 / $a50, 1) } else { 0 }
  }
  $r = $rows[-1]
  Write-Host ("{0,-38} before p50 {1,10} ms  after p50 {2,9} ms  x{3,-7} index {4}" -f $r.module, $r.before_p50_ms, $r.after_p50_ms, $r.speedup, $r.index_size)
}
$rows | Export-Csv -Path "perf/results/$Label.csv" -NoTypeInformation -Encoding UTF8
Write-Host "results: perf/results/$Label.csv"
