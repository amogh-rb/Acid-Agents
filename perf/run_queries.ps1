<#
.SYNOPSIS
  Query set runner (M20 B65, M21 B70). For every queries/Q*.sql: saves the EXPLAIN (ANALYZE, BUFFERS) plan and measures
  the server-side execution time over N runs, then writes p50/p95/p99 to perf/results/.

.EXAMPLE
  .\perf\run_queries.ps1 -Database talentra_seed -Runs 30 -Label baseline_laptop
  .\perf\run_queries.ps1 -Database talentra_seed -Runs 30 -Label after_index -Only Q09
#>
param(
  [string]$Database = 'talentra_seed',
  [int]$Runs = 30,
  [int]$Warmup = 3,
  [string]$Label = 'baseline',
  [string]$Only = '',
  [string]$ActorUser = ''
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
New-Item -ItemType Directory -Force 'perf/plans', 'perf/results' | Out-Null

function Get-Percentile([double[]]$values, [double]$p) {
  $s = $values | Sort-Object
  $rank = [math]::Ceiling($p / 100.0 * $s.Count) - 1
  return $s[[math]::Max(0, [math]::Min($s.Count - 1, $rank))]
}

$rows = @()
$files = Get-ChildItem 'queries' -Filter 'Q*.sql' | Where-Object { -not $Only -or $_.Name -like "$Only*" } | Sort-Object Name
foreach ($f in $files) {
  $text = Get-Content $f.FullName -Raw
  $name = if ($text -match '(?m)^-- name:\s*(.+)$') { $Matches[1].Trim() } else { $f.BaseName }
  $kind = if ($text -match '(?m)^-- kind:\s*(.+)$') { $Matches[1].Trim() } else { '' }
  $mode = if ($text -match '(?m)^-- mode:\s*(\w+)') { $Matches[1] } else { 'select' }
  $stmt = (($text -split "`r?`n") | Where-Object { $_ -notmatch '^\s*--' }) -join "`n"
  $stmt = $stmt.Trim().TrimEnd(';')

  $script = New-Object System.Text.StringBuilder
  [void]$script.AppendLine('\set ON_ERROR_STOP on')
  [void]$script.AppendLine('\o NUL')
  [void]$script.AppendLine('\i ' + ((Resolve-Path 'queries/_params.sql').Path -replace '\\', '/'))
  [void]$script.AppendLine('\o')
  [void]$script.AppendLine("SET app.current_user_id = '" + $(if ($ActorUser) { $ActorUser } else { '1' }) + "';")
  if ($mode -eq 'dml') { [void]$script.AppendLine('SET app.current_user_id = :rec_user;') }
  [void]$script.AppendLine('\pset format unaligned')
  [void]$script.AppendLine('\pset tuples_only on')
  for ($i = 1; $i -le ($Warmup + $Runs); $i++) {
    [void]$script.AppendLine("\echo @@RUN $i")
    [void]$script.AppendLine('BEGIN;')
    [void]$script.AppendLine("EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, SUMMARY ON) $stmt;")
    [void]$script.AppendLine('ROLLBACK;')
  }
  $tmp = Join-Path $env:TEMP ("talentra_q_" + $f.BaseName + ".sql")
  [System.IO.File]::WriteAllText($tmp, $script.ToString(), (New-Object System.Text.UTF8Encoding($false)))

  $ErrorActionPreference = 'Continue'
  $out = & $psql -X -q -d $Database -f $tmp 2>&1 | Out-String
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0 -or $out -match 'ERROR:') {
    Write-Host ("FAIL  {0}: {1}" -f $f.BaseName, (($out -split "`r?`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -First 1))) -ForegroundColor Red
    $rows += [pscustomobject]@{ query = $f.BaseName; name = $name; kind = $kind; runs = 0; p50_ms = ''; p95_ms = ''; p99_ms = ''; planning_ms = ''; shared_hit = ''; shared_read = ''; error = 'failed' }
    continue
  }
  $blocks = $out -split '(?m)^@@RUN \d+\s*$' | Select-Object -Skip 1
  $exec = @(); $plan = @(); $hits = @(); $reads = @()
  $n = 0
  foreach ($b in $blocks) {
    $n++
    if ($b -match 'Execution Time:\s*([0-9.]+) ms') { $e = [double]$Matches[1] } else { continue }
    if ($b -match 'Planning Time:\s*([0-9.]+) ms') { $plan += [double]$Matches[1] }
    if ($b -match 'shared hit=(\d+)') { $hits += [double]$Matches[1] }
    if ($b -match 'shared hit=\d+(?: read=(\d+))?') { if ($Matches[1]) { $reads += [double]$Matches[1] } }
    if ($n -gt $Warmup) { $exec += $e }
    if ($n -eq $Warmup + 1) { $b.Trim() | Set-Content -Path ("perf/plans/{0}_{1}.txt" -f $f.BaseName, $Label) -Encoding UTF8 }
  }
  $rows += [pscustomobject]@{
    query = $f.BaseName; name = $name; kind = $kind; runs = $exec.Count
    p50_ms = [math]::Round((Get-Percentile $exec 50), 3); p95_ms = [math]::Round((Get-Percentile $exec 95), 3); p99_ms = [math]::Round((Get-Percentile $exec 99), 3)
    planning_ms = [math]::Round(($plan | Measure-Object -Average).Average, 3)
    shared_hit = if ($hits.Count) { [math]::Round(($hits | Measure-Object -Average).Average, 0) } else { 0 }
    shared_read = if ($reads.Count) { [math]::Round(($reads | Measure-Object -Average).Average, 0) } else { 0 }
    error = ''
  }
  $r = $rows[-1]
  Write-Host ("{0,-4} p50 {1,9} ms  p95 {2,9} ms  p99 {3,9} ms  {4}" -f $f.BaseName.Substring(0, 3), $r.p50_ms, $r.p95_ms, $r.p99_ms, $name)
}
$csv = "perf/results/${Label}.csv"
$rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "results: $csv"
