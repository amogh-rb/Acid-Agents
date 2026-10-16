<#
.SYNOPSIS
  M22 (B79, Delivery Plan key risk "RLS performance on candidate search"): the same candidate-side queries measured
  as the table owner (RLS bypassed) and as a recruiter through talentra_app (RLS applied). p50/p95 over N runs.

.EXAMPLE
  .\perf\rls_overhead.ps1 -Database talentra_seed -Runs 20
#>
param([string]$Database = 'talentra_seed', [int]$Runs = 20, [string]$Label = 'rls_overhead')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (Test-Path '.env') {
  foreach ($line in Get-Content '.env') {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { Set-Item -Path ("env:" + $Matches[1]) -Value $Matches[2].Trim('"', "'") }
  }
}
$psql = Join-Path $env:PGBIN 'psql.exe'
$env:PGCLIENTENCODING = 'UTF8'

function Get-Percentile([double[]]$v, [double]$p) { $s = $v | Sort-Object; $s[[math]::Max(0, [math]::Min($s.Count - 1, [math]::Ceiling($p / 100.0 * $s.Count) - 1))] }

# a recruiter with an active seat (hiring side), and parameters the queries find
$setup = @'
SELECT s.app_user_id AS rec FROM lic.licence_seat s WHERE s.released_at IS NULL ORDER BY s.id LIMIT 1 \gset
SELECT c.email AS email FROM profile.candidate_contact c JOIN profile.candidate_profile p ON p.id = c.candidate_profile_id
 WHERE c.email IS NOT NULL AND p.deleted_at IS NULL AND p.id > 600000 ORDER BY p.id LIMIT 1 \gset
SELECT id AS cand FROM profile.candidate_profile WHERE id > 600000 AND deleted_at IS NULL ORDER BY id LIMIT 1 \gset
SELECT max(id) AS skill FROM ref.skill \gset
'@
$queries = [ordered]@{
  'R1 candidate by email'                 = "SELECT p.id, p.full_name FROM profile.candidate_contact c JOIN profile.candidate_profile p ON p.id = c.candidate_profile_id WHERE c.email = :'email'"
  'R2 profile with skills and education'  = "SELECT p.full_name, s.skill_id, e.qualification_id FROM profile.candidate_profile p LEFT JOIN profile.candidate_skill s ON s.candidate_profile_id = p.id LEFT JOIN profile.candidate_education e ON e.candidate_profile_id = p.id WHERE p.id = :cand"
  'R3 name search, top 50'                = "SELECT id, full_name FROM profile.candidate_profile WHERE full_name ILIKE '%Iyer%' AND deleted_at IS NULL ORDER BY id LIMIT 50"
  'R4 skill search, top 50 open to work'  = "SELECT p.id, p.full_name FROM profile.candidate_skill s JOIN profile.candidate_profile p ON p.id = s.candidate_profile_id WHERE s.skill_id = :skill AND p.is_open_to_work AND p.deleted_at IS NULL ORDER BY p.id LIMIT 50"
  'R5 name search, count (Q05)'           = "SELECT count(*) FROM profile.candidate_profile WHERE full_name ILIKE '%Iyer%' AND deleted_at IS NULL"
  'R6 name search via app.search_candidates_by_name' = "SELECT * FROM app.search_candidates_by_name('Iyer', 50)"
}

$rows = @()
foreach ($q in $queries.GetEnumerator()) {
  $result = @{}
  foreach ($mode in 'owner', 'recruiter') {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('\set ON_ERROR_STOP on'); [void]$sb.AppendLine('\o NUL'); [void]$sb.AppendLine($setup); [void]$sb.AppendLine('\o')
    [void]$sb.AppendLine('BEGIN;')
    if ($mode -eq 'recruiter') { [void]$sb.AppendLine('SET LOCAL ROLE talentra_app;'); [void]$sb.AppendLine("SELECT set_config('app.current_user_id', :'rec', true) \g NUL") }
    else { [void]$sb.AppendLine("SELECT set_config('app.current_user_id', '1', true) \g NUL") }
    [void]$sb.AppendLine('\pset format unaligned'); [void]$sb.AppendLine('\pset tuples_only on')
    $n_runs = if ($q.Key -like 'R5*') { [math]::Min($Runs, 3) } else { $Runs }   # R5 under RLS takes seconds per run
    [void]$sb.AppendLine("SET LOCAL statement_timeout = '180s';")
    for ($i = 1; $i -le $n_runs + 2; $i++) { [void]$sb.AppendLine("\echo @@RUN $i"); [void]$sb.AppendLine("EXPLAIN (ANALYZE, BUFFERS, TIMING OFF) $($q.Value);") }
    [void]$sb.AppendLine('ROLLBACK;')
    $tmp = Join-Path $env:TEMP 'talentra_rls.sql'
    [IO.File]::WriteAllText($tmp, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
    $ErrorActionPreference = 'Continue'
    $out = & $psql -X -q -d $Database -f $tmp 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    $timedOut = $out -match 'statement timeout'
    if ($out -match 'ERROR:' -and -not $timedOut) { throw "$($q.Key) ($mode): " + (($out -split "`r?`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -First 1)) }
    if ($timedOut) { $result[$mode] = @{ p50 = 180000.0; p95 = 180000.0; rows = 'timeout>180s' }; continue }
    $blocks = $out -split '(?m)^@@RUN \d+\s*$' | Select-Object -Skip 1
    $t = @(); $n = 0; $rowsOut = ''
    foreach ($b in $blocks) {
      $n++
      if ($b -match 'Execution Time:\s*([0-9.]+) ms' -and $n -gt 2) { $t += [double]$Matches[1] }
      if ($n -eq 3) {
        if ($b.Trim() -match '^\S.*?actual rows=([0-9.]+)') { $rowsOut = $Matches[1] }
        $b.Trim() | Set-Content -Path ("perf/plans/rls_{0}_{1}.txt" -f ($q.Key.Substring(0, 2)), $mode) -Encoding UTF8
      }
    }
    $result[$mode] = @{ p50 = (Get-Percentile $t 50); p95 = (Get-Percentile $t 95); rows = $rowsOut }
  }
  $rows += [pscustomobject]@{
    query = $q.Key; owner_rows = $result.owner.rows; recruiter_rows = $result.recruiter.rows
    owner_p50_ms = [math]::Round($result.owner.p50, 3); owner_p95_ms = [math]::Round($result.owner.p95, 3)
    recruiter_p50_ms = [math]::Round($result.recruiter.p50, 3); recruiter_p95_ms = [math]::Round($result.recruiter.p95, 3)
    overhead_x = [math]::Round($result.recruiter.p50 / [math]::Max($result.owner.p50, 0.001), 1)
  }
  $r = $rows[-1]
  Write-Host ("{0,-38} owner p50 {1,9} ms  recruiter (RLS) p50 {2,9} ms  x{3,-6} rows {4}/{5}" -f $r.query, $r.owner_p50_ms, $r.recruiter_p50_ms, $r.overhead_x, $r.owner_rows, $r.recruiter_rows)
}
$rows | Export-Csv -Path "perf/results/$Label.csv" -NoTypeInformation -Encoding UTF8
Write-Host "results: perf/results/$Label.csv"
