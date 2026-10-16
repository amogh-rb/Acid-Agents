# M20 gate: the query set is complete and its committed baseline has a result for every query.
# (Timing is measured on the seeded database by perf/run_queries.ps1; this check runs on any machine.)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$fail = 0
function Check([string]$label, [bool]$ok) {
  if ($ok) { Write-Output "PASS  $label" } else { Write-Output "FAIL  $label"; $script:fail++ }
}

$queries = Get-ChildItem 'queries' -Filter 'Q*.sql' | Sort-Object Name
Check ("at least 12 queries in queries/ ({0})" -f $queries.Count) ($queries.Count -ge 12)
$bad = @($queries | Where-Object { $t = Get-Content $_.FullName -Raw; -not ($t -match '(?m)^-- name:\s*\S' -and $t -match '(?m)^-- kind:\s*\S' -and $t -match '(?m)^-- mode:\s*(select|dml)\b') })
Check ("every query declares name, kind and mode" + $(if ($bad) { ': missing in ' + ($bad.Name -join ', ') } else { '' })) ($bad.Count -eq 0)

$csv = 'perf/results/baseline_laptop.csv'
Check "baseline results exist ($csv)" (Test-Path $csv)
if (Test-Path $csv) {
  $rows = Import-Csv $csv
  $missing = @($queries.BaseName | Where-Object { $_ -notin $rows.query })
  Check ("baseline covers every query" + $(if ($missing) { ': missing ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)
  $failed = @($rows | Where-Object { $_.error -or [int]$_.runs -lt 30 })
  Check ("every query ran 30 measured runs without error" + $(if ($failed) { ': ' + ($failed.query -join ', ') } else { '' })) ($failed.Count -eq 0)
  $plans = @($rows | Where-Object { -not (Test-Path ("perf/plans/{0}_baseline_laptop.txt" -f $_.query)) })
  Check "an EXPLAIN (ANALYZE, BUFFERS) plan is saved for every query" ($plans.Count -eq 0)
}
Check "M20 report exists (docs/phase5/m20_queries.md)" (Test-Path 'docs/phase5/m20_queries.md')
if ($fail -gt 0) { exit 1 }
